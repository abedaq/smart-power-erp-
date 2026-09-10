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
	LostUnits        float64 `json:"lost_units"`
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

		// 6. Calculate Arrears from previous unpaid invoices
		var arrearsSummary struct {
			TotalRemaining float64
		}
		tx.Model(&models.Invoice{}).
			Select("COALESCE(SUM(remaining_amount), 0) as total_remaining").
			Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid')", customer.ID).
			Scan(&arrearsSummary)

		arrears := arrearsSummary.TotalRemaining
		totalDue := totalAmount + arrears

		approvalStatus := req.ApprovalStatus
		if approvalStatus == "" {
			approvalStatus = "APPROVED"
		}

		mutationID := req.ClientMutationID
		if mutationID == nil || *mutationID == "" {
			generatedUUID := uuid.New().String()
			mutationID = &generatedUUID
		}

		// 7. Insert MeterReading
		now := time.Now().UTC()
		reading := models.MeterReading{
			CustomerID:       &customer.ID,
			ReadingValue:     req.ReadingValue,
			ReadingDate:      &now,
			CollectorName:    req.CollectorName,
			CollectorUserID:  req.CollectorUserID,
			ApprovalStatus:   approvalStatus,
			LostUnits:        req.LostUnits,
			ClientMutationID: mutationID,
		}
		if err := tx.Create(&reading).Error; err != nil {
			return fmt.Errorf("failed to save reading: %w", err)
		}

		// 8. Generate Composite Deterministic Invoice Number with Canonical Cycle
		cycle := FormatCanonicalCycle(req.BillingCycle)
		if cycle == "" {
			cycle = FormatCanonicalCycle(now.Format("2006-01-2"))
		}
		invNumber := fmt.Sprintf("INV-%s-%s", strings.ReplaceAll(cycle, " ", "-"), customer.SubscriberNumber)
		dueDate := now.AddDate(0, 0, graceDays)

		// 9. Check if an invoice already exists for this customer in the target cycle
		var existingInv models.Invoice
		aliases := getCycleAliases(cycle)
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("customer_id = ? AND (billing_cycle = ? OR billing_cycle IN ?)", customer.ID, cycle, aliases).
			First(&existingInv).Error; err == nil && existingInv.ID > 0 {
			
			// Update existing invoice instead of creating duplicate row
			existingInv.ReadingID = &reading.ID
			existingInv.BillingCycle = &cycle
			existingInv.PreviousReading = previousReadingValue
			existingInv.CurrentReading = req.ReadingValue
			existingInv.Consumption = consumption
			existingInv.LostUnits = req.LostUnits
			existingInv.ConsumptionValue = consumptionValue
			existingInv.KwhPriceSnapshot = kwhPrice
			existingInv.FixedFeeSnapshot = fixedFee
			existingInv.Arrears = arrears
			existingInv.TotalAmount = totalAmount
			existingInv.TotalDue = totalDue
			existingInv.RemainingAmount = math.Round((totalDue-existingInv.PaidAmount)*100) / 100
			if existingInv.RemainingAmount <= 0 && existingInv.PaidAmount > 0 {
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
			invoice := models.Invoice{
				CustomerID:         &customer.ID,
				ReadingID:          &reading.ID,
				InvoiceNumber:      &invNumber,
				PreviousReading:    previousReadingValue,
				CurrentReading:     req.ReadingValue,
				Consumption:        consumption,
				LostUnits:          req.LostUnits,
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
				Status:             "Unpaid",
				CreatedAt:          &now,
			}

			if err := tx.Create(&invoice).Error; err != nil {
				return fmt.Errorf("failed to save invoice: %w", err)
			}
			result.Invoice = invoice
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
		if err := tx.First(&reading, id).Error; err != nil {
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
		Preload("Customer.SubscriptionPlan").
		Order("id DESC").
		Limit(limit).
		Offset(offset).
		Find(&readings).Error

	return readings, total, err
}