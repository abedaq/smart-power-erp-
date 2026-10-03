package services

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type PaymentService struct {
	db *gorm.DB
}

func NewPaymentService() *PaymentService {
	return &PaymentService{
		db: database.DB,
	}
}

type CreatePaymentRequest struct {
	CustomerID       int64   `json:"customer_id"`
	InvoiceID        *int64  `json:"invoice_id"`
	ShiftID          *int64  `json:"shift_id"`
	AmountPaid       float64 `json:"amount_paid"`
	PaymentMethod    string  `json:"payment_method"` // CASH, TRANSFER, BANK, KURAMI
	AccountantName   string  `json:"accountant_name"`
	AccountantUserID *int64  `json:"accountant_user_id"`
	IPAddress        string  `json:"ip_address"`
	Notes            *string `json:"notes"`
	ClientMutationID *string `json:"client_mutation_id"`
}

type PaymentResult struct {
	Payment     models.Payment             `json:"payment"`
	Allocations []models.PaymentAllocation `json:"allocations"`
	Credit      *models.CustomerCredit     `json:"credit,omitempty"`
}

func (s *PaymentService) CreatePayment(req CreatePaymentRequest) (*PaymentResult, error) {
	if req.CustomerID <= 0 {
		return nil, errors.New("customer_id is required")
	}
	if req.AmountPaid <= 0 {
		return nil, errors.New("amount_paid must be greater than 0")
	}

	var result PaymentResult

	err := s.db.Transaction(func(tx *gorm.DB) error {
		// 1. Lock customer row
		var customer models.Customer
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&customer, req.CustomerID).Error; err != nil {
			return fmt.Errorf("customer not found: %w", err)
		}

		// 2. Generate Thread-Safe Receipt Number
		year := time.Now().Year()
		var counter models.PaymentReceiptCounter
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("year = ?", year).First(&counter).Error; err != nil {
			counter = models.PaymentReceiptCounter{
				Year:      year,
				LastValue: 1,
			}
			if err := tx.Create(&counter).Error; err != nil {
				return fmt.Errorf("failed to initialize receipt counter: %w", err)
			}
		} else {
			counter.LastValue++
			if err := tx.Save(&counter).Error; err != nil {
				return fmt.Errorf("failed to increment receipt counter: %w", err)
			}
		}
		receiptNumber := fmt.Sprintf("REC-%d-%06d", year, counter.LastValue)

		// 3. Create Payment Record
		now := time.Now().UTC()
		paymentMethod := strings.ToUpper(strings.TrimSpace(req.PaymentMethod))
		if paymentMethod == "TRANSFER" || paymentMethod == "BANK" {
			paymentMethod = "BANK_TRANSFER"
		} else if paymentMethod == "KURAMI" {
			paymentMethod = "KURSHI"
		} else if paymentMethod != "CASH" && paymentMethod != "BANK_TRANSFER" && paymentMethod != "KURSHI" && paymentMethod != "OTHER" {
			paymentMethod = "CASH"
		}

		mutationID := req.ClientMutationID
		if mutationID == nil || *mutationID == "" {
			generatedUUID := uuid.New().String()
			mutationID = &generatedUUID
		}

		payment := models.Payment{
			CustomerID:         &customer.ID,
			InvoiceID:          req.InvoiceID,
			ShiftID:            req.ShiftID,
			ReceiptNumber:      &receiptNumber,
			PaymentMethod:      paymentMethod,
			AmountPaid:         req.AmountPaid,
			PaymentDate:        &now,
			AccountantName:     req.AccountantName,
			AccountantUserID:   req.AccountantUserID,
			ApprovalStatus:     "APPROVED",
			Notes:              req.Notes,
			ClientMutationID:   mutationID,
			CreatedAt:          &now,
		}

		if err := tx.Create(&payment).Error; err != nil {
			return fmt.Errorf("failed to create payment: %w", err)
		}

		// 4. Payment Allocation (Targeted Invoice vs Unified FIFO Waterfall)
		var allocations []models.PaymentAllocation
		var creditRecord *models.CustomerCredit

		var targetInvoice *models.Invoice
		if req.InvoiceID != nil && *req.InvoiceID > 0 {
			var inv models.Invoice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&inv, *req.InvoiceID).Error; err == nil && inv.ID > 0 {
				targetInvoice = &inv
			}
		}

		if targetInvoice != nil {
			allocAmount := req.AmountPaid
			targetInvoice.PaidAmount += allocAmount
			targetInvoice.RemainingAmount = math.Round((targetInvoice.TotalDue - targetInvoice.PaidAmount) * 100) / 100
			if targetInvoice.RemainingAmount <= 0 {
				targetInvoice.Status = "Paid"
			} else {
				targetInvoice.Status = "Partially_Paid"
			}
			_ = tx.Save(targetInvoice)

			alloc := models.PaymentAllocation{
				PaymentID:       payment.ID,
				InvoiceID:       targetInvoice.ID,
				AmountAllocated: allocAmount,
				CreatedAt:       &now,
			}
			_ = tx.Create(&alloc)
			allocations = append(allocations, alloc)

			// If targetInvoice carried arrears from prior invoices, settle those prior invoices
			// once cumulative payment on targetInvoice covers the arrears
			if targetInvoice.Arrears > 0 && targetInvoice.PaidAmount >= targetInvoice.Arrears {
				var priorInvoices []models.Invoice
				if err := tx.Where("customer_id = ? AND approval_status != 'REJECTED' AND status IN ('Unpaid', 'Partially_Paid')", customer.ID).
					Find(&priorInvoices).Error; err == nil {
					targetIdx := 0
					if targetInvoice.BillingCycle != nil {
						targetIdx = GetCycleSortIndex(*targetInvoice.BillingCycle)
					}
					for p := range priorInvoices {
						pInv := &priorInvoices[p]
						if pInv.ID == targetInvoice.ID {
							continue
						}
						pIdx := 0
						if pInv.BillingCycle != nil {
							pIdx = GetCycleSortIndex(*pInv.BillingCycle)
						}
						if pIdx < targetIdx || (pIdx == targetIdx && pInv.ID < targetInvoice.ID) {
							if pInv.TotalDue <= targetInvoice.Arrears {
								pInv.PaidAmount = pInv.TotalDue
								pInv.RemainingAmount = 0
								pInv.Status = "Paid"
								_ = tx.Save(pInv)
							}
						}
					}
				}
			}

			// If payment created negative remaining amount (overpayment / credit), record CustomerCredit
			if targetInvoice.RemainingAmount < 0 {
				creditAmount := math.Abs(targetInvoice.RemainingAmount)
				credit := models.CustomerCredit{
					CustomerID:      customer.ID,
					PaymentID:       payment.ID,
					Amount:          creditAmount,
					RemainingAmount: creditAmount,
					Status:          "AVAILABLE",
					CreatedAt:       &now,
				}
				if err := tx.Create(&credit).Error; err != nil {
					return fmt.Errorf("failed to create credit: %w", err)
				}
				creditRecord = &credit
			}
		} else {
			var invoices []models.Invoice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("customer_id = ? AND approval_status != 'REJECTED' AND status IN ('Unpaid', 'Partially_Paid')", customer.ID).
				Limit(3).
				Find(&invoices).Error; err != nil {
				return fmt.Errorf("failed to fetch unpaid invoices: %w", err)
			}

			if len(invoices) == 0 {
				var latestInv models.Invoice
				if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
					Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
					Order("id DESC").
					First(&latestInv).Error; err == nil && latestInv.ID > 0 {
					invoices = append(invoices, latestInv)
				}
			}

			sort.Slice(invoices, func(i, j int) bool {
				cI := ""
				if invoices[i].BillingCycle != nil {
					cI = *invoices[i].BillingCycle
				}
				cJ := ""
				if invoices[j].BillingCycle != nil {
					cJ = *invoices[j].BillingCycle
				}
				idxI := GetCycleSortIndex(cI)
				idxJ := GetCycleSortIndex(cJ)
				if idxI != idxJ {
					return idxI < idxJ
				}
				return invoices[i].ID < invoices[j].ID
			})

			remainingPaymentToAllocate := req.AmountPaid
			var priorUnpaidRemainder float64 = 0
			hasPriorInvoiceInChain := false

			for i := range invoices {
				if remainingPaymentToAllocate <= 0 {
					break
				}

				needed := invoices[i].RemainingAmount
				if hasPriorInvoiceInChain && invoices[i].Arrears > 0 && invoices[i].TotalAmount > 0 {
					ownUnpaid := math.Max(0, invoices[i].TotalAmount-invoices[i].PaidAmount)
					needed = math.Round((ownUnpaid+priorUnpaidRemainder)*100) / 100
				}

				if needed <= 0 {
					priorUnpaidRemainder = 0
					hasPriorInvoiceInChain = true
					continue
				}

				var allocAmount float64
				if remainingPaymentToAllocate >= needed {
					allocAmount = needed
					invoices[i].PaidAmount += allocAmount
					invoices[i].RemainingAmount = 0
					invoices[i].Status = "Paid"
					remainingPaymentToAllocate = math.Round((remainingPaymentToAllocate-needed)*100) / 100
					priorUnpaidRemainder = 0
				} else {
					allocAmount = remainingPaymentToAllocate
					invoices[i].PaidAmount += allocAmount
					invoices[i].RemainingAmount = math.Round((needed-allocAmount)*100) / 100
					invoices[i].Status = "Partially_Paid"
					remainingPaymentToAllocate = 0
					priorUnpaidRemainder = invoices[i].RemainingAmount
				}
				hasPriorInvoiceInChain = true

				if err := tx.Save(&invoices[i]).Error; err != nil {
					return fmt.Errorf("failed to update invoice %d: %w", invoices[i].ID, err)
				}

				if allocAmount > 0 {
					alloc := models.PaymentAllocation{
						PaymentID:       payment.ID,
						InvoiceID:       invoices[i].ID,
						AmountAllocated: allocAmount,
						CreatedAt:       &now,
					}
					if err := tx.Create(&alloc).Error; err != nil {
						return fmt.Errorf("failed to create allocation: %w", err)
					}
					allocations = append(allocations, alloc)
				}
			}

			// Handle Overpayment: Record credit if payment exceeds all open invoices
			if remainingPaymentToAllocate > 0 {
				if len(invoices) > 0 {
					lastInv := &invoices[len(invoices)-1]
					lastInv.PaidAmount += remainingPaymentToAllocate
					lastInv.RemainingAmount = math.Round((lastInv.RemainingAmount-remainingPaymentToAllocate)*100) / 100
					lastInv.Status = "Paid"
					_ = tx.Save(lastInv)

					if len(allocations) > 0 {
						lastAlloc := &allocations[len(allocations)-1]
						lastAlloc.AmountAllocated += remainingPaymentToAllocate
						tx.Save(lastAlloc)
					}
				}

				credit := models.CustomerCredit{
					CustomerID:      customer.ID,
					PaymentID:       payment.ID,
					Amount:          remainingPaymentToAllocate,
					RemainingAmount: remainingPaymentToAllocate,
					Status:          "AVAILABLE",
					CreatedAt:       &now,
				}
				if err := tx.Create(&credit).Error; err != nil {
					return fmt.Errorf("failed to create credit: %w", err)
				}
				creditRecord = &credit
			}
		}

		// Cascade downstream to subsequent billing cycles starting from the earliest touched invoice
		var earliestInvID int64
		if len(allocations) > 0 {
			earliestInvID = allocations[0].InvoiceID
		} else if targetInvoice != nil {
			earliestInvID = targetInvoice.ID
		}

		if earliestInvID > 0 {
			var earliestTouchedInv models.Invoice
			if err := tx.First(&earliestTouchedInv, earliestInvID).Error; err == nil && earliestTouchedInv.ID > 0 {
				var allInvoices []models.Invoice
				if tx.Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
					Find(&allInvoices).Error == nil {
					earliestCycleIdx := 0
					if earliestTouchedInv.BillingCycle != nil {
						earliestCycleIdx = GetCycleSortIndex(*earliestTouchedInv.BillingCycle)
					}

					var downstreamInvoices []models.Invoice
					for _, inv := range allInvoices {
						if inv.ID == earliestTouchedInv.ID {
							continue
						}
						invCycle := ""
						if inv.BillingCycle != nil {
							invCycle = *inv.BillingCycle
						}
						if GetCycleSortIndex(invCycle) > earliestCycleIdx {
							downstreamInvoices = append(downstreamInvoices, inv)
						}
					}

					sort.Slice(downstreamInvoices, func(i, j int) bool {
						cI := ""
						if downstreamInvoices[i].BillingCycle != nil {
							cI = *downstreamInvoices[i].BillingCycle
						}
						cJ := ""
						if downstreamInvoices[j].BillingCycle != nil {
							cJ = *downstreamInvoices[j].BillingCycle
						}
						return GetCycleSortIndex(cI) < GetCycleSortIndex(cJ)
					})

					cascadeArr := earliestTouchedInv.RemainingAmount
					cascadePrev := earliestTouchedInv.CurrentReading
					if cascadePrev == 0 {
						cascadePrev = earliestTouchedInv.PreviousReading
					}

					for _, downInv := range downstreamInvoices {
						_ = tx.First(&downInv, downInv.ID)
						if cascadePrev > 0 {
							downInv.PreviousReading = cascadePrev
						}
						if downInv.CurrentReading > 0 && downInv.CurrentReading < downInv.PreviousReading {
							downInv.CurrentReading = downInv.PreviousReading
						}

						downInv.Arrears = cascadeArr
						if downInv.TotalAmount <= 0 {
							downCons := 0.0
							if downInv.CurrentReading > 0 && downInv.CurrentReading >= downInv.PreviousReading {
								downCons = downInv.CurrentReading - downInv.PreviousReading
							}
							downInv.Consumption = downCons
							downInv.ConsumptionValue = math.Round(downCons*downInv.KwhPriceSnapshot*100) / 100
							downInv.TotalAmount = math.Round((downInv.ConsumptionValue+downInv.FixedFeeSnapshot)*100) / 100
						}
						downInv.TotalDue = math.Round((downInv.TotalAmount+downInv.Arrears)*100) / 100
						downInv.RemainingAmount = math.Round((downInv.TotalDue-downInv.PaidAmount)*100) / 100
						if downInv.RemainingAmount <= 0 {
							downInv.Status = "Paid"
						} else if downInv.PaidAmount > 0 {
							downInv.Status = "Partially_Paid"
						} else {
							downInv.Status = "Unpaid"
						}
						_ = tx.Save(&downInv)

						if downInv.CurrentReading > 0 {
							cascadePrev = downInv.CurrentReading
						}
						// في حال وجود دورات مستقبلية فارغة أو غير معتمدة، منع ترحيل رسوم افتراضية إذا كان الرصيد السابق 0 مع الحفاظ التام على الرصيد الدائن (السالب)
						if downInv.ApprovalStatus == "PENDING" && downInv.Consumption == 0 {
							if cascadeArr < 0 {
								cascadeArr = downInv.RemainingAmount
							} else if cascadeArr == 0 {
								cascadeArr = 0
							} else {
								cascadeArr = downInv.RemainingAmount
							}
						} else {
							cascadeArr = downInv.RemainingAmount
						}
					}
				}
			}
		}
		// 6. Update Shift total if shift is active
		if req.ShiftID != nil && *req.ShiftID > 0 {
			tx.Model(&models.Shift{}).
				Where("id = ? AND status = 'OPEN'", *req.ShiftID).
				Update("total_collected", gorm.Expr("total_collected + ?", req.AmountPaid))
		}

		// 8. In-Transaction Atomic Audit Log
		var ipPtr *string
		if req.IPAddress != "" {
			ipPtr = &req.IPAddress
		}
		tx.Create(&models.AuditLog{
			UserID:    req.AccountantUserID,
			Action:    "CREATE_PAYMENT",
			Entity:    "PAYMENT",
			EntityID:  strPtr(receiptNumber),
			IPAddress: ipPtr,
			Details:   strPtr(fmt.Sprintf("تم تحصيل سند قبض وسداد بمبلغ %.2f ريال وتوزيعه آلياً على %d فاتورة مستحقة", req.AmountPaid, len(allocations))),
		})

		// 9. مزامنة مديونية ورصيد المشترك في جدول customers
		if err := SyncCustomerFinancials(tx, customer.ID); err != nil {
			return fmt.Errorf("failed to sync customer financials: %w", err)
		}

		result.Payment = payment
		result.Allocations = allocations
		result.Credit = creditRecord
		return nil
	})

	if err != nil {
		return nil, err
	}

	return &result, nil
}

func (s *PaymentService) ApprovePayment(id int64, auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var payment models.Payment
		if err := tx.First(&payment, id).Error; err != nil {
			return err
		}
		if err := tx.Model(&payment).Update("approval_status", "APPROVED").Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		receipt := ""
		if payment.ReceiptNumber != nil {
			receipt = *payment.ReceiptNumber
		}
		details := fmt.Sprintf("تم اعتماد سند القبض رقم [%s] بمبلغ %.2f ريال", receipt, payment.AmountPaid)

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "PAYMENT_APPROVE",
			Entity:    "PAYMENT",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *PaymentService) RejectPayment(id int64, reason string, auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var payment models.Payment
		if err := tx.Preload("Allocations").First(&payment, id).Error; err != nil {
			return err
		}

		// 1. Lock customer row first (Deterministic Global Lock Ordering)
		var customer models.Customer
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&customer, payment.CustomerID).Error; err != nil {
			return fmt.Errorf("customer not found: %w", err)
		}

		now := time.Now().UTC()
		// Reverse allocations
		for _, alloc := range payment.Allocations {
			var inv models.Invoice
			if err := tx.First(&inv, alloc.InvoiceID).Error; err == nil {
				inv.PaidAmount -= alloc.AmountAllocated
				inv.RemainingAmount += alloc.AmountAllocated
				if inv.RemainingAmount >= inv.TotalDue {
					inv.Status = "Unpaid"
				} else if inv.PaidAmount > 0 {
					inv.Status = "Partially_Paid"
				}
				tx.Save(&inv)
			}
			alloc.IsReversed = true
			alloc.ReversedAt = &now
			alloc.ReversalReason = &reason
			tx.Save(&alloc)
		}

		// Cancel credit if any
		tx.Model(&models.CustomerCredit{}).Where("payment_id = ?", id).Update("status", "CANCELLED")

		if err := tx.Model(&models.Payment{}).Where("id = ?", id).Updates(map[string]interface{}{
			"approval_status":  "REJECTED",
			"rejection_reason": reason,
		}).Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		receipt := ""
		if payment.ReceiptNumber != nil {
			receipt = *payment.ReceiptNumber
		}
		details := fmt.Sprintf("تم إلغاء/رفض سند القبض رقم [%s] بمبلغ %.2f ريال - السبب: %s", receipt, payment.AmountPaid, reason)

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "PAYMENT_REJECT",
			Entity:    "PAYMENT",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *PaymentService) ListPayments(customerID int64, page, limit int) ([]models.Payment, int64, error) {
	var payments []models.Payment
	var total int64

	query := s.db.Model(&models.Payment{})
	if customerID > 0 {
		query = query.Where("customer_id = ?", customerID)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	if limit <= 0 {
		limit = 100
	}
	offset := 0
	if page > 1 {
		offset = (page - 1) * limit
	}

	err := query.Preload("Customer").
		Preload("Allocations").
		Order("id DESC").
		Limit(limit).
		Offset(offset).
		Find(&payments).Error

	return payments, total, err
}

func (s *PaymentService) ReversePayment(id int64, reason string, auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var payment models.Payment
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&payment, id).Error; err != nil {
			return fmt.Errorf("payment not found: %w", err)
		}
		if payment.ApprovalStatus == "REVERSED" {
			return fmt.Errorf("payment is already reversed")
		}

		// 0. Deterministic Lock Ordering: Lock customer row first
		var customer models.Customer
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&customer, payment.CustomerID).Error; err != nil {
			return fmt.Errorf("customer not found: %w", err)
		}

		// 1. Accounting Safety Check: Customer Credit
		var credit models.CustomerCredit
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("payment_id = ?", payment.ID).First(&credit).Error
		if err == nil {
			if credit.Status == "USED" || credit.RemainingAmount < credit.Amount {
				return fmt.Errorf("لا يمكن إلغاء السند لوجود رصيد دائن مستخدم جزئياً أو كلياً بقيمة %.2f ريال", credit.Amount-credit.RemainingAmount)
			}
			credit.Status = "CANCELLED"
			credit.RemainingAmount = 0
			if err := tx.Save(&credit).Error; err != nil {
				return fmt.Errorf("failed to cancel customer credit: %w", err)
			}
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check customer credit: %w", err)
		}

		var allocations []models.PaymentAllocation
		if err := tx.Where("payment_id = ?", payment.ID).Find(&allocations).Error; err != nil {
			return err
		}

		now := time.Now()
		var touchedInvoiceIDs []int64
		for i := range allocations {
			alloc := &allocations[i]
			alloc.IsReversed = true
			alloc.ReversedAt = &now
			alloc.ReversalReason = &reason
			if err := tx.Save(alloc).Error; err != nil {
				return fmt.Errorf("failed to reverse allocation %d: %w", alloc.ID, err)
			}

			var inv models.Invoice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&inv, alloc.InvoiceID).Error; err == nil {
				inv.PaidAmount = math.Round(math.Max(0, inv.PaidAmount-alloc.AmountAllocated)*100) / 100
				inv.RemainingAmount = math.Round((inv.TotalDue-inv.PaidAmount)*100) / 100
				if inv.PaidAmount <= 0 {
					inv.Status = "Unpaid"
				} else if inv.RemainingAmount > 0 {
					inv.Status = "Partially_Paid"
				} else {
					inv.Status = "Paid"
				}
				if err := tx.Save(&inv).Error; err != nil {
					return fmt.Errorf("failed to save invoice %d: %w", inv.ID, err)
				}
				touchedInvoiceIDs = append(touchedInvoiceIDs, inv.ID)

				// R1 Reversal Invariant: If target invoice had cumulative arrears and its paid amount
				// dropped below its arrears, any prior invoices that were marked Paid solely by this
				// cumulative payment (i.e. having no active allocations of their own and chained within arrears) must be reopened.
				if inv.Arrears > 0 && inv.PaidAmount < inv.Arrears {
					targetCycleIdx := 0
					if inv.BillingCycle != nil {
						targetCycleIdx = GetCycleSortIndex(*inv.BillingCycle)
					}
					var priorInvs []models.Invoice
					if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
						Where("customer_id = ? AND id != ? AND approval_status != 'REJECTED'", payment.CustomerID, inv.ID).
						Find(&priorInvs).Error; err == nil {

						// Sort strictly descending by chronological cycle index / ID (walk backwards from target invoice)
						sort.Slice(priorInvs, func(i, j int) bool {
							cI := ""
							if priorInvs[i].BillingCycle != nil {
								cI = *priorInvs[i].BillingCycle
							}
							cJ := ""
							if priorInvs[j].BillingCycle != nil {
								cJ = *priorInvs[j].BillingCycle
							}
							idxI := GetCycleSortIndex(cI)
							idxJ := GetCycleSortIndex(cJ)
							if idxI != idxJ {
								return idxI > idxJ // descending
							}
							return priorInvs[i].ID > priorInvs[j].ID // descending
						})

						for p := range priorInvs {
							pInv := &priorInvs[p]
							pCycle := ""
							if pInv.BillingCycle != nil {
								pCycle = *pInv.BillingCycle
							}
							isPrior := false
							if targetCycleIdx > 0 && pCycle != "" {
								isPrior = GetCycleSortIndex(pCycle) < targetCycleIdx
							} else {
								isPrior = pInv.ID < inv.ID
							}
							if !isPrior {
								continue
							}

							// Check if this prior invoice has active allocations of its own
							var activeAllocCount int64
							tx.Model(&models.PaymentAllocation{}).
								Where("invoice_id = ? AND is_reversed = false", pInv.ID).
								Count(&activeAllocCount)

							// A prior invoice with active payment allocations was paid by its own payment.
							// It forms a definitive payment barrier: no arrears on subsequent invoices could have come from before it.
							if activeAllocCount > 0 {
								break
							}

							// Only reopen invoices that were marked Paid solely by cumulative arrears absorption
							// (i.e. Paid with 0 remaining, no active allocations, and TotalDue <= inv.Arrears)
							if pInv.Status == "Paid" && pInv.RemainingAmount == 0 && pInv.TotalDue <= inv.Arrears {
								pInv.PaidAmount = 0
								pInv.RemainingAmount = pInv.TotalDue
								pInv.Status = "Unpaid"
								_ = tx.Save(pInv)
								touchedInvoiceIDs = append(touchedInvoiceIDs, pInv.ID)
							} else {
								// Broken chain (e.g. invoice was already Unpaid, or exceeded inv.Arrears)
								break
							}
						}
					}
				}
			} else if !errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("failed to lock invoice %d: %w", alloc.InvoiceID, err)
			}
		}

		if len(touchedInvoiceIDs) > 0 {
			var allInvoices []models.Invoice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("customer_id = ? AND approval_status != 'REJECTED'", payment.CustomerID).
				Find(&allInvoices).Error; err == nil && len(allInvoices) > 0 {

				// Sort in strict chronological cycle order
				sort.Slice(allInvoices, func(i, j int) bool {
					cI := ""
					if allInvoices[i].BillingCycle != nil {
						cI = *allInvoices[i].BillingCycle
					}
					cJ := ""
					if allInvoices[j].BillingCycle != nil {
						cJ = *allInvoices[j].BillingCycle
					}
					idxI := GetCycleSortIndex(cI)
					idxJ := GetCycleSortIndex(cJ)
					if idxI != idxJ {
						return idxI < idxJ
					}
					return allInvoices[i].ID < allInvoices[j].ID
				})

				touchedSet := make(map[int64]bool, len(touchedInvoiceIDs))
				for _, tid := range touchedInvoiceIDs {
					touchedSet[tid] = true
				}

				startIndex := -1
				for k, inv := range allInvoices {
					if touchedSet[inv.ID] {
						startIndex = k
						break
					}
				}

				if startIndex >= 0 {
					startInv := allInvoices[startIndex]
					_ = tx.First(&startInv, startInv.ID)
					cascadeArr := startInv.RemainingAmount
					cascadePrev := startInv.CurrentReading
					if cascadePrev == 0 {
						cascadePrev = startInv.PreviousReading
					}

					for k := startIndex + 1; k < len(allInvoices); k++ {
						downInv := allInvoices[k]
						if err := tx.First(&downInv, downInv.ID).Error; err != nil {
							return fmt.Errorf("failed to fetch cascade invoice %d: %w", downInv.ID, err)
						}
						if cascadePrev > 0 {
							downInv.PreviousReading = cascadePrev
						}
						if downInv.CurrentReading > 0 && downInv.CurrentReading < downInv.PreviousReading {
							downInv.CurrentReading = downInv.PreviousReading
						}
						preserveArrears := false
						if downInv.Arrears > 0 && cascadeArr < downInv.Arrears {
							if downInv.Status == "Paid" || downInv.RemainingAmount <= 0 || downInv.PaidAmount > 0 {
								preserveArrears = true
							}
						} else if downInv.Arrears < 0 && cascadeArr >= 0 {
							preserveArrears = true
						}

						if !preserveArrears {
							downInv.Arrears = cascadeArr
						}
						if downInv.TotalAmount <= 0 {
							downCons := 0.0
							if downInv.CurrentReading > 0 && downInv.CurrentReading >= downInv.PreviousReading {
								downCons = downInv.CurrentReading - downInv.PreviousReading
							}
							downInv.Consumption = downCons
							downInv.ConsumptionValue = math.Round(downCons*downInv.KwhPriceSnapshot*100) / 100
							downInv.TotalAmount = math.Round((downInv.ConsumptionValue+downInv.FixedFeeSnapshot)*100) / 100
						}
						downInv.TotalDue = math.Round((downInv.TotalAmount+downInv.Arrears)*100) / 100
						downInv.RemainingAmount = math.Round((downInv.TotalDue-downInv.PaidAmount)*100) / 100
						if downInv.RemainingAmount <= 0 {
							downInv.Status = "Paid"
						} else if downInv.PaidAmount > 0 {
							downInv.Status = "Partially_Paid"
						} else {
							downInv.Status = "Unpaid"
						}
						if err := tx.Save(&downInv).Error; err != nil {
							return fmt.Errorf("failed to save cascade invoice %d: %w", downInv.ID, err)
						}

						if downInv.CurrentReading > 0 {
							cascadePrev = downInv.CurrentReading
						}
						cascadeArr = downInv.RemainingAmount
					}
				}
			}
		}

		if payment.ShiftID != nil && *payment.ShiftID > 0 {
			var shift models.Shift
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&shift, *payment.ShiftID).Error; err == nil {
				if shift.Status == "OPEN" {
					shift.TotalCollected = math.Round(math.Max(0, shift.TotalCollected-payment.AmountPaid)*100) / 100
					if err := tx.Save(&shift).Error; err != nil {
						return fmt.Errorf("failed to update shift: %w", err)
					}
				}
			} else if !errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("failed to lock shift: %w", err)
			}
		}

		revReason := reason
		payment.ApprovalStatus = "REVERSED"
		payment.RejectionReason = &revReason
		payment.UpdatedAt = &now
		if err := tx.Save(&payment).Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		receipt := fmt.Sprintf("REC-%d", payment.ID)
		if payment.ReceiptNumber != nil {
			receipt = *payment.ReceiptNumber
		}
		details := fmt.Sprintf("تم إلغاء وعكس سند القبض [%s] بمبلغ %.2f ريال. السبب: %s", receipt, payment.AmountPaid, revReason)

		if err := tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "PAYMENT_REVERSE",
			Entity:    "PAYMENT",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error; err != nil {
			return err
		}

		// مزامنة مديونية ورصيد المشترك بعد إلغاء السند
		if err := SyncCustomerFinancials(tx, *payment.CustomerID); err != nil {
			return fmt.Errorf("failed to sync customer financials after reversal: %w", err)
		}

		return nil
	})
}

// SyncCustomerFinancials تقوم بإعادة احتساب وتحديث total_due و balance في جدول customers
// ذرياً داخل المعاملة (tx) لمنع تشتت الحسابات وضمان التوافق مع قاعدة البيانات.
func SyncCustomerFinancials(tx *gorm.DB, customerID int64) error {
	var totalDebt float64
	var totalCredits float64

	// 1. حساب إجمالي الديون من أحدث فاتورة للمشترك (بدون تكرار أو تضخيم)
	// مع منع ظهور مديونية اشتراك معلقة لمشترك صفى حسابه في حال وجود دورات مستقبلية فارغة أو غير معتمدة
	var latestInv models.Invoice
	if err := tx.Where("customer_id = ? AND approval_status != 'REJECTED'", customerID).
		Order("id DESC").First(&latestInv).Error; err == nil {
		if latestInv.ApprovalStatus == "PENDING" && latestInv.Consumption == 0 && (latestInv.CurrentReading == 0 || latestInv.CurrentReading <= latestInv.PreviousReading) {
			if latestInv.Arrears > 0 {
				totalDebt = latestInv.Arrears
			} else {
				totalDebt = 0
			}
		} else if latestInv.RemainingAmount > 0 {
			totalDebt = latestInv.RemainingAmount
		} else {
			totalDebt = 0
		}
	}

	// 2. حساب إجمالي الأرصدة الدائنة المتاحة
	if err := tx.Model(&models.CustomerCredit{}).
		Where("customer_id = ? AND status = 'AVAILABLE'", customerID).
		Select("COALESCE(SUM(remaining_amount), 0)").
		Scan(&totalCredits).Error; err != nil {
		return err
	}

	now := time.Now().UTC()
	return tx.Model(&models.Customer{}).Where("id = ?", customerID).Updates(map[string]interface{}{
		"total_due":  totalDebt,
		"balance":    totalCredits,
		"updated_at": now,
	}).Error
}

