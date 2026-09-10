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

		// 4. Payment Allocation
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
			// Direct invoice payment: apply the entire payment amount to the chosen invoice
			targetInvoice.PaidAmount += req.AmountPaid
			targetInvoice.RemainingAmount = math.Round((targetInvoice.TotalDue - targetInvoice.PaidAmount) * 100) / 100
			if targetInvoice.RemainingAmount <= 0 {
				targetInvoice.Status = "Paid"
			} else {
				targetInvoice.Status = "Partially_Paid"
			}

			if err := tx.Save(targetInvoice).Error; err != nil {
				return fmt.Errorf("failed to update target invoice %d: %w", targetInvoice.ID, err)
			}

			alloc := models.PaymentAllocation{
				PaymentID:       payment.ID,
				InvoiceID:       targetInvoice.ID,
				AmountAllocated: req.AmountPaid,
				CreatedAt:       &now,
			}
			if err := tx.Create(&alloc).Error; err != nil {
				return fmt.Errorf("failed to create allocation: %w", err)
			}
			allocations = append(allocations, alloc)

			// Record credit if overpayment occurs
			if targetInvoice.RemainingAmount < 0 {
				credit := models.CustomerCredit{
					CustomerID:      customer.ID,
					PaymentID:       payment.ID,
					Amount:          math.Abs(targetInvoice.RemainingAmount),
					RemainingAmount: math.Abs(targetInvoice.RemainingAmount),
					Status:          "AVAILABLE",
					CreatedAt:       &now,
				}
				if err := tx.Create(&credit).Error; err != nil {
					return fmt.Errorf("failed to create credit: %w", err)
				}
				creditRecord = &credit
			}

			// Cascade downstream to subsequent billing cycles in strict chronological order
			var allInvoices []models.Invoice
			if tx.Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
				Find(&allInvoices).Error == nil {
				targetCycleIdx := 0
				if targetInvoice.BillingCycle != nil {
					targetCycleIdx = GetCycleSortIndex(*targetInvoice.BillingCycle)
				}

				var downstreamInvoices []models.Invoice
				for _, inv := range allInvoices {
					if inv.ID == targetInvoice.ID {
						continue
					}
					invCycle := ""
					if inv.BillingCycle != nil {
						invCycle = *inv.BillingCycle
					}
					if GetCycleSortIndex(invCycle) > targetCycleIdx {
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

				cascadeArr := targetInvoice.RemainingAmount
				cascadePrev := targetInvoice.CurrentReading
				if cascadePrev == 0 {
					cascadePrev = targetInvoice.PreviousReading
				}

				for _, downInv := range downstreamInvoices {
					if cascadePrev > 0 {
						downInv.PreviousReading = cascadePrev
					}
					downInv.Arrears = cascadeArr
					downCons := 0.0
					if downInv.CurrentReading > 0 && downInv.CurrentReading >= downInv.PreviousReading {
						downCons = downInv.CurrentReading - downInv.PreviousReading
					}
					downInv.Consumption = downCons
					downInv.ConsumptionValue = math.Round(downCons*downInv.KwhPriceSnapshot*100) / 100
					downInv.TotalAmount = math.Round((downInv.ConsumptionValue+downInv.FixedFeeSnapshot)*100) / 100
					downInv.TotalDue = math.Round((downInv.TotalAmount+downInv.Arrears)*100) / 100
					downInv.RemainingAmount = math.Round((downInv.TotalDue-downInv.PaidAmount)*100) / 100
					if downInv.RemainingAmount <= 0 && downInv.PaidAmount > 0 {
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
					cascadeArr = downInv.RemainingAmount
				}
			}
		} else {
			// Fallback FIFO Waterfall Allocation across unpaid/partially paid invoices
			var invoices []models.Invoice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid')", customer.ID).
				Order("due_date ASC, id ASC").
				Find(&invoices).Error; err != nil {
				return fmt.Errorf("failed to fetch unpaid invoices: %w", err)
			}

			if len(invoices) == 0 {
				var latestInv models.Invoice
				if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
					Where("customer_id = ?", customer.ID).
					Order("id DESC").
					First(&latestInv).Error; err == nil && latestInv.ID > 0 {
					invoices = append(invoices, latestInv)
				}
			}

			remainingPaymentToAllocate := req.AmountPaid

			for i := range invoices {
				if remainingPaymentToAllocate <= 0 {
					break
				}

				var allocAmount float64
				if remainingPaymentToAllocate >= invoices[i].RemainingAmount {
					allocAmount = invoices[i].RemainingAmount
					remainingPaymentToAllocate -= invoices[i].RemainingAmount

					invoices[i].PaidAmount += allocAmount
					invoices[i].RemainingAmount = 0
					invoices[i].Status = "Paid"
				} else {
					allocAmount = remainingPaymentToAllocate
					invoices[i].PaidAmount += allocAmount
					invoices[i].RemainingAmount -= allocAmount
					invoices[i].Status = "Partially_Paid"
					remainingPaymentToAllocate = 0
				}

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

			if remainingPaymentToAllocate > 0 {
				if len(invoices) > 0 {
					lastInv := &invoices[len(invoices)-1]
					lastInv.PaidAmount += remainingPaymentToAllocate
					lastInv.RemainingAmount -= remainingPaymentToAllocate
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
				_ = tx.Create(&credit)
				creditRecord = &credit
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