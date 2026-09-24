package services

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type ReadingService struct {
	db *gorm.DB
}

func NewReadingService() *ReadingService {
	return &ReadingService{
		db: database.DB,
	}
}

type CreateReadingRequest struct {
	CustomerID       int64   `json:"customer_id"`
	ReadingValue     float64 `json:"reading_value"`
	CollectorName    string  `json:"collector_name"`
	CollectorUserID  *int64  `json:"collector_user_id"`
	IPAddress        string  `json:"ip_address"`
	ApprovalStatus   string  `json:"approval_status"`
	BillingCycle     string  `json:"billing_cycle"`
	ClientMutationID *string `json:"client_mutation_id"`
}

type ReadingResult struct {
	Reading models.MeterReading `json:"reading"`
	Invoice models.Invoice      `json:"invoice"`
}

func (s *ReadingService) CreateReading(req CreateReadingRequest) (*ReadingResult, error) {
	if req.CustomerID <= 0 {
		return nil, errors.New("customer_id is required")
	}

	var result ReadingResult

	err := s.db.Transaction(func(tx *gorm.DB) error {
		// 1. Fetch and lock customer row
		var customer models.Customer
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Preload("SubscriptionPlan").
			First(&customer, req.CustomerID).Error; err != nil {
			return fmt.Errorf("customer not found: %w", err)
		}

		// 2. Fetch system settings for fallback pricing
		var settings models.SystemSettings
		if err := tx.First(&settings).Error; err != nil {
			settings.DefaultKwhPrice = 1000
			settings.DefaultFixedFee = 1000
			settings.MaxOverdueDays = 10
		}

		kwhPrice := settings.DefaultKwhPrice
		fixedFee := settings.DefaultFixedFee
		graceDays := settings.MaxOverdueDays
		if graceDays <= 0 {
			graceDays = 10
		}

		if customer.SubscriptionPlan != nil {
			kwhPrice = customer.SubscriptionPlan.KwhPrice
			fixedFee = customer.SubscriptionPlan.FixedFee
			if customer.SubscriptionPlan.GracePeriodDays > 0 {
				graceDays = customer.SubscriptionPlan.GracePeriodDays
			}
		}

		// 3. Determine Previous Reading
		var previousReadingValue float64 = customer.InitialReading
		var lastReading models.MeterReading
		if err := tx.Where("customer_id = ? AND approval_status = 'APPROVED'", customer.ID).
			Order("id DESC").First(&lastReading).Error; err == nil {
			previousReadingValue = lastReading.ReadingValue
		}

		// 4. Strict Monotonicity Guard
		if req.ReadingValue < previousReadingValue {
			return fmt.Errorf("invalid reading: current reading (%.2f) cannot be less than previous reading (%.2f)",
				req.ReadingValue, previousReadingValue)
		}

		// 5. Calculate consumption and financials
		consumption := req.ReadingValue - previousReadingValue
		consumptionValue := consumption * kwhPrice
		totalAmount := consumptionValue + fixedFee

		now := time.Now().UTC()

		// 6. Resolve Canonical Cycle and look up existing invoice for this cycle first
		cycle := FormatCanonicalCycle(req.BillingCycle)
		if cycle == "" {
			cycle = FormatCanonicalCycle(now.Format("2006-01-2"))
		}
		aliases := getCycleAliases(cycle)

		var existingInv models.Invoice
		_ = tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("customer_id = ? AND (billing_cycle = ? OR billing_cycle IN ?)", customer.ID, cycle, aliases).
			First(&existingInv)

		// 7. Calculate Arrears strictly from the immediately preceding invoice (preventing duplicate debt compounding)
		var priorInvoices []models.Invoice
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("customer_id = ? AND billing_cycle != ? AND billing_cycle NOT IN ?", customer.ID, cycle, aliases).
			Order("id ASC").
			Find(&priorInvoices).Error; err != nil {
			return fmt.Errorf("failed to calculate arrears: %w", err)
		}

		targetCycleIdx := GetCycleSortIndex(cycle)
		// Chronological Sequence Lock: reject inserting or modifying readings for a past cycle when a newer cycle already exists
		if targetCycleIdx > 0 {
			for i := range priorInvoices {
				inv := &priorInvoices[i]
				if inv.BillingCycle != nil && inv.ApprovalStatus != "REJECTED" {
					idx := GetCycleSortIndex(*inv.BillingCycle)
					if idx > targetCycleIdx {
						return fmt.Errorf("chronological sequence violation: cannot insert or modify reading for past cycle '%s' when newer cycle '%s' already exists", cycle, *inv.BillingCycle)
					}
				}
			}
		}

		var prevInvoice *models.Invoice
		maxPrevIdx := -1
		for i := range priorInvoices {
			inv := &priorInvoices[i]
			if existingInv.ID > 0 && inv.ID == existingInv.ID {
				continue
			}
			if inv.BillingCycle == nil {
				continue
			}
			idx := GetCycleSortIndex(*inv.BillingCycle)
			if targetCycleIdx > 0 && idx > 0 {
				if idx < targetCycleIdx && idx > maxPrevIdx {
					maxPrevIdx = idx
					prevInvoice = inv
				}
			} else if prevInvoice == nil || inv.ID > prevInvoice.ID {
				prevInvoice = inv
			}
		}

		// Fallback: If cycle indexing didn't resolve, take the highest ID prior invoice
		if prevInvoice == nil && len(priorInvoices) > 0 {
			for i := len(priorInvoices) - 1; i >= 0; i-- {
				if existingInv.ID == 0 || priorInvoices[i].ID != existingInv.ID {
					prevInvoice = &priorInvoices[i]
					break
				}
			}
		}

		arrears := 0.0
		if prevInvoice != nil {
			arrears = prevInvoice.RemainingAmount
		} else {
			arrears = customer.Arrears
		}
		totalDue := math.Round((totalAmount+arrears)*100) / 100

		approvalStatus := req.ApprovalStatus
		if approvalStatus == "" {
			approvalStatus = "APPROVED"
		}

		mutationID := req.ClientMutationID
		if mutationID == nil || *mutationID == "" {
			generatedUUID := uuid.New().String()
			mutationID = &generatedUUID
		}

		// 8. Insert MeterReading
		reading := models.MeterReading{
			CustomerID:       &customer.ID,
			ReadingValue:     req.ReadingValue,
			ReadingDate:      &now,
			CollectorName:    req.CollectorName,
			CollectorUserID:  req.CollectorUserID,
			ApprovalStatus:   approvalStatus,
			ClientMutationID: mutationID,
		}
		if err := tx.Create(&reading).Error; err != nil {
			return fmt.Errorf("failed to save reading: %w", err)
		}

		invNumber := fmt.Sprintf("INV-%s-%s", strings.ReplaceAll(cycle, " ", "-"), customer.SubscriberNumber)
		dueDate := now.AddDate(0, 0, graceDays)

		// 9. Update existing invoice or insert new invoice
		if existingInv.ID > 0 {
			// Update existing invoice instead of creating duplicate row
			existingInv.ReadingID = &reading.ID
			existingInv.BillingCycle = &cycle
			existingInv.PreviousReading = previousReadingValue
			existingInv.CurrentReading = req.ReadingValue
			existingInv.Consumption = consumption
			existingInv.ConsumptionValue = consumptionValue
			existingInv.KwhPriceSnapshot = kwhPrice
			existingInv.FixedFeeSnapshot = fixedFee
			existingInv.Arrears = arrears
			existingInv.TotalAmount = totalAmount
			existingInv.TotalDue = totalDue
			existingInv.RemainingAmount = math.Round((totalDue-existingInv.PaidAmount)*100) / 100
			if existingInv.RemainingAmount <= 0 {
				existingInv.Status = "Paid"
			} else if existingInv.PaidAmount > 0 {
				existingInv.Status = "Partially_Paid"
			} else {
				existingInv.Status = "Unpaid"
			}
			existingInv.ApprovalStatus = approvalStatus

			if err := tx.Save(&existingInv).Error; err != nil {
				return fmt.Errorf("failed to update existing invoice: %w", err)
			}
			result.Invoice = existingInv
		} else {
			// Insert new invoice if none existed
			newStatus := "Unpaid"
			if totalDue <= 0 {
				newStatus = "Paid"
			}
			invoice := models.Invoice{
				CustomerID:         &customer.ID,
				ReadingID:          &reading.ID,
				InvoiceNumber:      &invNumber,
				PreviousReading:    previousReadingValue,
				CurrentReading:     req.ReadingValue,
				Consumption:        consumption,
				ConsumptionValue:   consumptionValue,
				KwhPriceSnapshot:   kwhPrice,
				FixedFeeSnapshot:   fixedFee,
				Arrears:            arrears,
				TotalDue:           totalDue,
				PaidAmount:         0,
				RemainingAmount:    totalDue,
				BillingCycle:       &cycle,
				TotalAmount:        totalAmount,
				DueDate:            dueDate,
				ApprovalStatus:     approvalStatus,
				Status:             newStatus,
				CreatedAt:          &now,
			}

			if err := tx.Create(&invoice).Error; err != nil {
				return fmt.Errorf("failed to save invoice: %w", err)
			}
			result.Invoice = invoice
		}

		// 9.1 Credit Roll-Forward: تصفير أرصدة الفواتير السابقة السالبة التي تم استيعابها في الدورة الحالية
		if arrears < 0 {
			if err := tx.Model(&models.Invoice{}).
				Where("customer_id = ? AND remaining_amount < 0 AND id != ?", customer.ID, result.Invoice.ID).
				Updates(map[string]interface{}{
					"remaining_amount": 0.00,
					"status":           "Paid",
					"updated_at":       time.Now().UTC(),
				}).Error; err != nil {
				return fmt.Errorf("failed to roll forward previous invoice credits: %w", err)
			}
		}

		// 10. In-Transaction Atomic Audit Log
		var ipPtr *string
		if req.IPAddress != "" {
			ipPtr = &req.IPAddress
		}
		details := fmt.Sprintf("تسجيل قراءة عداد جديدة للمشترك رقم [%d] - القراءة: [%.2f]", req.CustomerID, req.ReadingValue)
		tx.Create(&models.AuditLog{
			UserID:    req.CollectorUserID,
			Action:    "READING_CREATE",
			Entity:    "READING",
			EntityID:  strPtr(fmt.Sprintf("%d", reading.ID)),
			IPAddress: ipPtr,
			Details:   &details,
		})

		result.Reading = reading

		// 11. تحديث آخر قراءة للمشترك بأحدث قراءة زمنياً فقط لمنع تراجع العداد (Chronological Guard)
		var latestReading float64
		if err := tx.Model(&models.MeterReading{}).
			Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
			Order("reading_date DESC, id DESC").
			Limit(1).
			Pluck("reading_value", &latestReading).Error; err == nil {
			tx.Model(&models.Customer{}).Where("id = ?", customer.ID).Update("last_reading", latestReading)
		}

		// 12. مزامنة مديونية المشترك مع الدورة الجديدة في جدول customers
		if err := SyncCustomerFinancials(tx, customer.ID); err != nil {
			return fmt.Errorf("failed to sync customer financials after reading: %w", err)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	return &result, nil
}

func (s *ReadingService) ApproveReading(id int64, auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.MeterReading{}).Where("id = ?", id).Update("approval_status", "APPROVED").Error; err != nil {
			return err
		}
		if err := tx.Model(&models.Invoice{}).Where("reading_id = ?", id).Update("approval_status", "APPROVED").Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		details := fmt.Sprintf("اعتماد قراءة العداد رقم [%d] واحتساب الفاتورة", id)

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "READING_APPROVE",
			Entity:    "READING",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *ReadingService) RejectReading(id int64, reason string, auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.MeterReading{}).Where("id = ?", id).Updates(map[string]interface{}{
			"approval_status":  "REJECTED",
			"rejection_reason": reason,
		}).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.Invoice{}).Where("reading_id = ?", id).Updates(map[string]interface{}{
			"approval_status": "REJECTED",
			"status":          "Cancelled",
		}).Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		details := fmt.Sprintf("رفض قراءة العداد رقم [%d] - السبب: %s", id, reason)

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "READING_REJECT",
			Entity:    "READING",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *ReadingService) ApproveAllPending(auditCtx models.AuditContext) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.MeterReading{}).Where("approval_status != 'APPROVED'").Update("approval_status", "APPROVED").Error; err != nil {
			return err
		}
		if err := tx.Model(&models.Invoice{}).Where("approval_status != 'APPROVED'").Update("approval_status", "APPROVED").Error; err != nil {
			return err
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}
		details := "اعتماد جماعي لكافة القراءات المعلقة"

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "READING_APPROVE_ALL",
			Entity:    "READING",
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *ReadingService) UpdateReading(id int64, updates map[string]interface{}, auditCtx models.AuditContext) (*models.MeterReading, error) {
	var reading models.MeterReading
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&reading, id).Error; err != nil {
			return err
		}

		diffObj := map[string]interface{}{
			"reading_id": id,
			"old_value":  reading.ReadingValue,
			"updates":    updates,
		}
		diffBytes, _ := json.Marshal(diffObj)
		diffStr := string(diffBytes)

		if err := tx.Model(&reading).Updates(updates).Error; err != nil {
			return err
		}

		// إعادة قراءة السجل بالقيم المحدثة
		if err := tx.First(&reading, id).Error; err != nil {
			return err
		}

		// 1. تحديث الفاتورة المرتبطة بالقراءة
		var linkedInv models.Invoice
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("reading_id = ?", reading.ID).
			First(&linkedInv).Error; err == nil && linkedInv.ID > 0 {

			consumption := math.Max(0, reading.ReadingValue-linkedInv.PreviousReading)
			consumptionValue := math.Round(consumption*linkedInv.KwhPriceSnapshot*100) / 100
			totalAmount := math.Round((consumptionValue+linkedInv.FixedFeeSnapshot)*100) / 100
			totalDue := math.Round((totalAmount+linkedInv.Arrears)*100) / 100
			remainingAmount := math.Round((totalDue-linkedInv.PaidAmount)*100) / 100

			linkedInv.CurrentReading = reading.ReadingValue
			linkedInv.Consumption = consumption
			linkedInv.ConsumptionValue = consumptionValue
			linkedInv.TotalAmount = totalAmount
			linkedInv.TotalDue = totalDue
			linkedInv.RemainingAmount = remainingAmount
			if remainingAmount <= 0 {
				linkedInv.Status = "Paid"
			} else if linkedInv.PaidAmount > 0 {
				linkedInv.Status = "Partially_Paid"
			} else {
				linkedInv.Status = "Unpaid"
			}

			if err := tx.Save(&linkedInv).Error; err != nil {
				return fmt.Errorf("failed to sync linked invoice: %w", err)
			}
		}

		if reading.CustomerID != nil && *reading.CustomerID > 0 {
			custID := *reading.CustomerID

			// 2. ترحيل وتحديث الكاسكاد لكافة الفواتير اللاحقة للمشترك
			billingSvc := &BillingService{db: tx}
			_ = billingSvc.ResyncCustomerInvoicesChain(custID)

			// 3. تحديث آخر قراءة للمشترك ومزامنة رصيده المالي
			var latestReading float64
			if err := tx.Model(&models.MeterReading{}).
				Where("customer_id = ? AND approval_status != 'REJECTED'", custID).
				Order("reading_date DESC, id DESC").
				Limit(1).
				Pluck("reading_value", &latestReading).Error; err == nil {
				tx.Model(&models.Customer{}).Where("id = ?", custID).Update("last_reading", latestReading)
			}

			_ = SyncCustomerFinancials(tx, custID)
		}

		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}

		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "READING_UPDATE",
			Entity:    "READING",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &diffStr,
		}).Error
	})
	if err != nil {
		return nil, err
	}
	return &reading, nil
}

func (s *ReadingService) ListReadings(customerID int64, cycle string, page, limit int) ([]models.MeterReading, int64, error) {
	var readings []models.MeterReading
	var total int64

	query := s.db.Model(&models.MeterReading{})
	if customerID > 0 {
		query = query.Where("meter_readings.customer_id = ?", customerID)
	}

	trimmedCycle := strings.TrimSpace(cycle)
	if trimmedCycle != "" && !strings.EqualFold(trimmedCycle, "ALL") {
		aliases := getCycleAliases(trimmedCycle)
		if len(aliases) > 0 {
			query = query.Joins("JOIN invoices ON invoices.reading_id = meter_readings.id").
				Where("invoices.billing_cycle IN ?", aliases)
		}
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
		Preload("Customer.SubscriptionPlan").
		Order("meter_readings.id DESC").
		Limit(limit).
		Offset(offset).
		Find(&readings).Error

	return readings, total, err
}