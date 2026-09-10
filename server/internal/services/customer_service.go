package services

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type CustomerService struct {
	db *gorm.DB
}

func NewCustomerService() *CustomerService {
	return &CustomerService{
		db: database.DB,
	}
}

var leadingZeroRegex = regexp.MustCompile(`^0+`)

// NormalizeSubscriberNumber cleans and normalizes subscriber numbers by trimming whitespace,
// lowercasing, and stripping leading zeros. If the string consists only of zeros, it returns "0"
// to ensure 100% parity with COALESCE(NULLIF(REGEXP_REPLACE(..., '^0+', ''), ''), '0').
func NormalizeSubscriberNumber(sub string) string {
	trimmed := strings.ToLower(strings.TrimSpace(sub))
	cleaned := leadingZeroRegex.ReplaceAllString(trimmed, "")
	if cleaned == "" {
		return "0"
	}
	return cleaned
}

type CustomerFilter struct {
	Search      string
	RouteNumber string
	Status      string
	Page        int
	Limit       int
}

func (s *CustomerService) ListCustomers(filter CustomerFilter) ([]models.Customer, int64, error) {
	var customers []models.Customer
	var total int64

	query := s.db.Model(&models.Customer{}).Where("is_deleted = false")

	if filter.Search != "" {
		searchTerm := "%" + strings.TrimSpace(filter.Search) + "%"
		query = query.Where("full_name ILIKE ? OR subscriber_number ILIKE ? OR phone_number ILIKE ? OR meter_number ILIKE ? OR address ILIKE ?",
			searchTerm, searchTerm, searchTerm, searchTerm, searchTerm)
	}

	if filter.RouteNumber != "" && filter.RouteNumber != "ALL" && filter.RouteNumber != "all" {
		query = query.Where("route_number = ?", filter.RouteNumber)
	}

	if filter.Status != "" && filter.Status != "ALL" && filter.Status != "all" {
		query = query.Where("status ILIKE ?", filter.Status)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	limit := filter.Limit
	if limit <= 0 {
		limit = 5000
	}
	offset := 0
	if filter.Page > 1 {
		offset = (filter.Page - 1) * limit
	}

	err := query.Preload("SubscriptionPlan").
		Order("sort_order ASC, id ASC").
		Limit(limit).
		Offset(offset).
		Find(&customers).Error
	if err != nil {
		return nil, 0, err
	}

	s.enrichCustomersBatch(customers)

	return customers, total, nil
}

func (s *CustomerService) GetCustomer(id int64) (*models.Customer, error) {
	var customer models.Customer
	err := s.db.Where("id = ? AND is_deleted = false", id).
		Preload("SubscriptionPlan").
		Preload("MeterReadings", func(db *gorm.DB) *gorm.DB {
			return db.Order("id DESC").Limit(10)
		}).
		Preload("Invoices", func(db *gorm.DB) *gorm.DB {
			return db.Order("id DESC").Limit(12)
		}).
		Preload("Payments", func(db *gorm.DB) *gorm.DB {
			return db.Order("id DESC").Limit(10)
		}).
		Preload("Credits", func(db *gorm.DB) *gorm.DB {
			return db.Where("status = 'AVAILABLE'")
		}).
		First(&customer).Error

	if err != nil {
		return nil, err
	}

	s.enrichCustomerCalculations(&customer)
	return &customer, nil
}

func (s *CustomerService) GetNextSubscriberNumber() string {
	var subNumbers []string
	s.db.Model(&models.Customer{}).Where("is_deleted = false").Pluck("subscriber_number", &subNumbers)

	maxNum := int64(910000)
	reDigits := regexp.MustCompile(`^\d+$`)

	for _, sn := range subNumbers {
		trimmed := strings.TrimSpace(sn)
		if reDigits.MatchString(trimmed) {
			if num, err := strconv.ParseInt(trimmed, 10, 64); err == nil {
				// Search for numbers in the 910xxx sequence or overall max numeric
				if num >= 910000 && num < 920000 && num > maxNum {
					maxNum = num
				}
			}
		}
	}

	// Collision check loop ensuring the generated number is 100% available
	candidate := maxNum + 1
	for {
		candidateStr := fmt.Sprintf("%d", candidate)
		var count int64
		s.db.Model(&models.Customer{}).Where("REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', '') = ? AND is_deleted = false", NormalizeSubscriberNumber(candidateStr)).Count(&count)
		if count == 0 {
			return candidateStr
		}
		candidate++
	}
}

func (s *CustomerService) CreateCustomer(customer *models.Customer, auditCtx models.AuditContext) (*models.Customer, error) {
	trimmedSubNo := strings.TrimSpace(customer.SubscriberNumber)
	if trimmedSubNo == "" {
		customer.SubscriberNumber = s.GetNextSubscriberNumber()
	} else {
		customer.SubscriberNumber = trimmedSubNo
		cleanSub := NormalizeSubscriberNumber(trimmedSubNo)
		// Strict duplicate check before inserting (stripping leading zeros with COALESCE/NULLIF parity)
		var existing models.Customer
		if err := s.db.Where("COALESCE(NULLIF(REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', ''), ''), '0') = ? AND is_deleted = false", cleanSub).First(&existing).Error; err == nil && existing.ID > 0 {
			return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع منعاً باتاً تكرار رقم المشترك.", customer.SubscriberNumber, existing.FullName)
		}
	}

	customer.PhoneNumber = NormalizeCustomerPhone(customer.PhoneNumber)

	if customer.Status == "" {
		customer.Status = "Active"
	}

	if customer.StartCycle == "" {
		customer.StartCycle = "أغسطس 1"
	} else {
		customer.StartCycle = FormatCanonicalCycle(customer.StartCycle)
	}

	err := s.db.Create(customer).Error
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "uq_customers_subscriber_number") {
			return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً لمشترك آخر في قاعدة البيانات!", customer.SubscriberNumber)
		}
		return nil, err
	}

	_ = s.db.Preload("SubscriptionPlan").First(customer, customer.ID)

	targetCycle := FormatCanonicalCycle(customer.StartCycle)
	if targetCycle == "" {
		targetCycle = "أغسطس 1"
	}
	primaryCycleName := targetCycle

	mutationID := uuid.New().String()
	reading := models.MeterReading{
		CustomerID:       &customer.ID,
		ReadingValue:     customer.InitialReading,
		CollectorName:    "النظام",
		ApprovalStatus:   "APPROVED",
		ClientMutationID: &mutationID,
	}
	_ = s.db.Create(&reading)

	kwhPrice := 1400.0
	fixedFee := 1000.0
	if customer.SubscriptionPlan != nil {
		if customer.SubscriptionPlan.KwhPrice > 0 {
			kwhPrice = customer.SubscriptionPlan.KwhPrice
		}
		if customer.SubscriptionPlan.FixedFee > 0 {
			fixedFee = customer.SubscriptionPlan.FixedFee
		}
	}

	cleanCycleForInv := strings.ReplaceAll(primaryCycleName, " ", "-")
	cleanCycleForInv = regexp.MustCompile(`-+`).ReplaceAllString(cleanCycleForInv, "-")
	invNum := fmt.Sprintf("INV-%s-%s", cleanCycleForInv, customer.SubscriberNumber)

	now := time.Now()
	dueDate := now.AddDate(0, 0, 15)
	totalDue := customer.Arrears + fixedFee
	invoice := models.Invoice{
		CustomerID:       &customer.ID,
		ReadingID:        &reading.ID,
		InvoiceNumber:    &invNum,
		PreviousReading:  customer.InitialReading,
		CurrentReading:   0,
		Consumption:      0,
		LostUnits:        0,
		ConsumptionValue: 0,
		KwhPriceSnapshot: kwhPrice,
		FixedFeeSnapshot: fixedFee,
		Arrears:          customer.Arrears,
		TotalDue:         totalDue,
		PaidAmount:       0,
		RemainingAmount:  totalDue,
		BillingCycle:     &primaryCycleName,
		TotalAmount:      totalDue,
		DueDate:          dueDate,
		ApprovalStatus:   "PENDING",
		Status:           "Unpaid",
	}
	_ = s.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&invoice)

	var ipPtr *string
	if auditCtx.IPAddress != "" {
		ipPtr = &auditCtx.IPAddress
	}
	details := fmt.Sprintf("تمت إضافة مشترك جديد [%s] برقم اشتراك [%s]", customer.FullName, customer.SubscriberNumber)
	_ = s.db.Create(&models.AuditLog{
		UserID:    auditCtx.UserID,
		Action:    "CUSTOMER_CREATE",
		Entity:    "CUSTOMER",
		EntityID:  strPtr(fmt.Sprintf("%d", customer.ID)),
		IPAddress: ipPtr,
		Details:   &details,
	})

	return customer, nil
}

func (s *CustomerService) EnsureAllCustomersHaveActiveInvoice() error {
	var latestCycle string

	// 1. استخراج الدورة المفتوحة بأعلى موثوقية (جدول الدورات -> آخر فاتورة -> تاريخ الشهر الحالي)
	var cycleCodes []string
	_ = s.db.Table("billing_cycles").
		Where("status = 'OPEN' OR status = 'ACTIVE'").
		Order("id DESC").
		Limit(1).
		Pluck("code", &cycleCodes)

	if len(cycleCodes) > 0 && cycleCodes[0] != "" {
		latestCycle = cycleCodes[0]
	} else {
		var invoiceCycles []string
		_ = s.db.Model(&models.Invoice{}).
			Where("billing_cycle IS NOT NULL AND billing_cycle != ''").
			Order("id DESC").
			Limit(1).
			Pluck("billing_cycle", &invoiceCycles)
		if len(invoiceCycles) > 0 && invoiceCycles[0] != "" {
			latestCycle = invoiceCycles[0]
		} else {
			latestCycle = time.Now().Format("2006-01")
		}
	}

	// 2. تنفيذ العملية داخل معاملة ذرية متكاملة
	tx := s.db.Begin()
	if tx.Error != nil {
		return tx.Error
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 2.1 ضمان وجود سجل الدورة في جدول billing_cycles بكافة الحقول الإلزامية
	ensureCycleSQL := `
		INSERT INTO billing_cycles (code, name, start_date, end_date, due_date, status, created_at, updated_at)
		VALUES (
			?,
			'دورة ' || ?,
			CURRENT_DATE,
			CURRENT_DATE + INTERVAL '30 days',
			CURRENT_DATE + INTERVAL '40 days',
			'OPEN',
			CURRENT_TIMESTAMP,
			CURRENT_TIMESTAMP
		)
		ON CONFLICT (code) DO NOTHING;
	`
	if err := tx.Exec(ensureCycleSQL, latestCycle, latestCycle).Error; err != nil {
		log.Printf("⚠️ Warning ensuring billing cycle record: %v", err)
	}

	// 2.2 إدراج القراءات الصفرية التأسيسية للمشتركين النشطين الجدد الذين ليس لديهم أي قراءة سابقة
	insertReadingsSQL := `
		INSERT INTO meter_readings (
			customer_id, reading_value, collector_name, approval_status, reading_date, created_at, updated_at
		)
		SELECT c.id, c.initial_reading, 'النظام', 'APPROVED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
		FROM customers c
		WHERE c.is_deleted = false
		  AND LOWER(c.status) = 'active'
		  AND NOT EXISTS (
			  SELECT 1 FROM meter_readings mr WHERE mr.customer_id = c.id
		  );
	`
	if err := tx.Exec(insertReadingsSQL).Error; err != nil {
		log.Printf("⚠️ Warning inserting baseline meter readings: %v", err)
	}

	// 2.3 إدراج فواتير الدورة النشطة محصنة محاسبياً وبرمجياً
	insertInvoicesSQL := `
		INSERT INTO invoices (
			customer_id,
			invoice_number,
			billing_cycle,
			due_date,
			status,
			kwh_price_snapshot,
			fixed_fee_snapshot,
			previous_reading,
			current_reading,
			consumption,
			lost_units,
			consumption_value,
			arrears,
			total_amount,
			total_due,
			paid_amount,
			remaining_amount,
			approval_status,
			created_at,
			updated_at
		)
		SELECT 
			c.id,
			'INV-' || ? || '-' || LPAD(
				COALESCE(NULLIF(REGEXP_REPLACE(c.subscriber_number::text, '^0+', ''), ''), '0'),
				GREATEST(4, LENGTH(COALESCE(NULLIF(REGEXP_REPLACE(c.subscriber_number::text, '^0+', ''), ''), '0'))),
				'0'
			),
			?,
			CURRENT_DATE + INTERVAL '30 days',
			'Unpaid',
			COALESCE(p.kwh_price, 1400.0),
			COALESCE(p.fixed_fee, 1000.0),
			-- القراءة السابقة: آخر قراءة معتمدة، أو قراءة التأسيس للمشترك الجديد
			COALESCE(
				(SELECT mr.reading_value 
				 FROM meter_readings mr 
				 WHERE mr.customer_id = c.id AND mr.approval_status = 'APPROVED' 
				 ORDER BY mr.reading_date DESC, mr.id DESC LIMIT 1),
				c.initial_reading
			),
			-- القراءة الحالية تبدأ مساوية للسابقة حتى إدخال القراءة الجديدة
			COALESCE(
				(SELECT mr.reading_value 
				 FROM meter_readings mr 
				 WHERE mr.customer_id = c.id AND mr.approval_status = 'APPROVED' 
				 ORDER BY mr.reading_date DESC, mr.id DESC LIMIT 1),
				c.initial_reading
			),
			0, -- الاستهلاك المبدئي
			0, -- الفاقد المبدئي
			0, -- قيمة الاستهلاك المبدئي
			-- المتأخرات الحقيقية من الفواتير السابقة غير المسددة مع استبعاد الملغاة
			COALESCE((
				SELECT SUM(old_inv.remaining_amount) 
				FROM invoices old_inv 
				WHERE old_inv.customer_id = c.id 
				  AND old_inv.billing_cycle < ? 
				  AND LOWER(old_inv.status) NOT IN ('paid', 'void', 'cancelled')
			), 0.0),
			-- إجمالي مبيعات الفاتورة الحالية فقط (الرسوم الثابتة) لمنع تضخيم الأرباح
			COALESCE(p.fixed_fee, 1000.0),
			-- إجمالي المستحق الصافي الشامل للمتأخرات
			COALESCE(p.fixed_fee, 1000.0) + COALESCE((
				SELECT SUM(old_inv.remaining_amount) 
				FROM invoices old_inv 
				WHERE old_inv.customer_id = c.id 
				  AND old_inv.billing_cycle < ? 
				  AND LOWER(old_inv.status) NOT IN ('paid', 'void', 'cancelled')
			), 0.0),
			0, -- المبلغ المسدد
			-- المبلغ المتبقي المطلوب سداده
			COALESCE(p.fixed_fee, 1000.0) + COALESCE((
				SELECT SUM(old_inv.remaining_amount) 
				FROM invoices old_inv 
				WHERE old_inv.customer_id = c.id 
				  AND old_inv.billing_cycle < ? 
				  AND LOWER(old_inv.status) NOT IN ('paid', 'void', 'cancelled')
			), 0.0),
			'APPROVED',
			CURRENT_TIMESTAMP,
			CURRENT_TIMESTAMP
		FROM customers c
		LEFT JOIN subscription_plans p ON c.subscription_plan_id = p.id
		WHERE c.is_deleted = false 
		  AND LOWER(c.status) = 'active'
		  AND NOT EXISTS (
			  SELECT 1 FROM invoices inv 
			  WHERE inv.customer_id = c.id 
				AND inv.billing_cycle = ?
		  );
	`
	if err := tx.Exec(insertInvoicesSQL, latestCycle, latestCycle, latestCycle, latestCycle, latestCycle, latestCycle).Error; err != nil {
		tx.Rollback()
		log.Printf("⚠️ Warning inserting cycle active invoices: %v", err)
		return err
	}

	return tx.Commit().Error
}

func (s *CustomerService) UpdateCustomer(id int64, updates map[string]interface{}, auditCtx models.AuditContext) (*models.Customer, error) {
	var customer models.Customer
	if err := s.db.First(&customer, id).Error; err != nil {
		return nil, err
	}

	delete(updates, "id")

	if subNoVal, ok := updates["subscriber_number"].(string); ok {
		trimmedSubNo := strings.TrimSpace(subNoVal)
		if trimmedSubNo != "" {
			cleanSub := NormalizeSubscriberNumber(trimmedSubNo)
			currentClean := NormalizeSubscriberNumber(customer.SubscriberNumber)
			if cleanSub != currentClean {
				var existing models.Customer
				if err := s.db.Where("COALESCE(NULLIF(REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', ''), ''), '0') = ? AND id != ? AND is_deleted = false", cleanSub, id).First(&existing).Error; err == nil && existing.ID > 0 {
					return nil, fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع تكرار رقم المشترك.", trimmedSubNo, existing.FullName)
				}
			}
			updates["subscriber_number"] = trimmedSubNo
		}
	}

	if phone, ok := updates["phone_number"].(string); ok {
		updates["phone_number"] = NormalizeCustomerPhone(phone)
	}

	if err := s.db.Model(&customer).Updates(updates).Error; err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "uq_customers_subscriber_number") {
			return nil, fmt.Errorf("رقم المشترك مسجل مسبقاً لمشترك آخر في قاعدة البيانات!")
		}
		return nil, err
	}

	var ipPtr *string
	if auditCtx.IPAddress != "" {
		ipPtr = &auditCtx.IPAddress
	}
	diffBytes, _ := json.Marshal(updates)
	diffStr := string(diffBytes)
	_ = s.db.Create(&models.AuditLog{
		UserID:    auditCtx.UserID,
		Action:    "CUSTOMER_UPDATE",
		Entity:    "CUSTOMER",
		EntityID:  strPtr(fmt.Sprintf("%d", id)),
		IPAddress: ipPtr,
		Details:   &diffStr,
	})

	return s.GetCustomer(id)
}

// UpdateGridCell performs real-time cell modification with financial and reading recalculation
func (s *CustomerService) UpdateGridCell(id int64, payload map[string]interface{}, auditCtx models.AuditContext) (*models.Customer, error) {
	if id <= 0 && payload["customer_id"] == nil {
		return nil, errors.New("invalid customer id")
	}

	var resolvedCustomerID int64

	err := s.db.Transaction(func(tx *gorm.DB) error {
		var customer models.Customer
		var targetInvoice models.Invoice
		hasTargetInvoice := false

		// 1. Check if ID is directly an Invoice ID
		if err := tx.First(&targetInvoice, id).Error; err == nil && targetInvoice.ID > 0 {
			hasTargetInvoice = true
			if targetInvoice.CustomerID != nil {
				_ = tx.Clauses(clause.Locking{Strength: "UPDATE"}).
					Preload("SubscriptionPlan").
					First(&customer, *targetInvoice.CustomerID)
			}
		}

		// 2. If not found by invoice ID, resolve by customer ID
		if customer.ID == 0 {
			custID := id
			if cidVal, ok := payload["customer_id"]; ok {
				cid := int64(toFloat64(cidVal))
				if cid > 0 {
					custID = cid
				}
			}

			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Preload("SubscriptionPlan").
				First(&customer, custID).Error; err != nil {
				return fmt.Errorf("customer not found: %w", err)
			}

			if !hasTargetInvoice {
				hasTargetInvoice = tx.Where("customer_id = ?", customer.ID).
					Order("id DESC").First(&targetInvoice).Error == nil
			}
		}

		resolvedCustomerID = customer.ID

		// 3. Update customer metadata if present
		customerUpdates := make(map[string]interface{})

		if name, ok := payload["full_name"].(string); ok && name != "" {
			customerUpdates["full_name"] = strings.TrimSpace(name)
		} else if name, ok := payload["name"].(string); ok && name != "" {
			customerUpdates["full_name"] = strings.TrimSpace(name)
		}

		if phone, ok := payload["phone_number"].(string); ok && phone != "" {
			customerUpdates["phone_number"] = NormalizeCustomerPhone(phone)
		} else if phone, ok := payload["phone"].(string); ok && phone != "" {
			customerUpdates["phone_number"] = NormalizeCustomerPhone(phone)
		}

		if addr, ok := payload["address"].(string); ok {
			customerUpdates["address"] = strings.TrimSpace(addr)
		}

		if meter, ok := payload["meter_number"].(string); ok {
			customerUpdates["meter_number"] = strings.TrimSpace(meter)
		} else if meter, ok := payload["meterNumber"].(string); ok {
			customerUpdates["meter_number"] = strings.TrimSpace(meter)
		}

		var newSubNum string
		if subNum, ok := payload["subscriber_number"].(string); ok && subNum != "" {
			newSubNum = strings.TrimSpace(subNum)
		} else if subNum, ok := payload["subNumber"].(string); ok && subNum != "" {
			newSubNum = strings.TrimSpace(subNum)
		}
		if newSubNum != "" {
			cleanSub := NormalizeSubscriberNumber(newSubNum)
			currentClean := NormalizeSubscriberNumber(customer.SubscriberNumber)
			if cleanSub != currentClean {
				var existing models.Customer
				if err := tx.Where("COALESCE(NULLIF(REGEXP_REPLACE(TRIM(LOWER(subscriber_number)), '^0+', ''), ''), '0') = ? AND id != ? AND is_deleted = false", cleanSub, customer.ID).First(&existing).Error; err == nil && existing.ID > 0 {
					return fmt.Errorf("رقم المشترك [%s] مسجل مسبقاً للمشترك [%s]! يمنع تكرار رقم المشترك.", newSubNum, existing.FullName)
				}
			}
			customerUpdates["subscriber_number"] = newSubNum
		}

		if route, ok := payload["route_number"].(string); ok {
			customerUpdates["route_number"] = strings.TrimSpace(route)
		} else if route, ok := payload["route"].(string); ok {
			customerUpdates["route_number"] = strings.TrimSpace(route)
		}

		if status, ok := payload["status"].(string); ok && status != "" {
			customerUpdates["status"] = status
		}

		if len(customerUpdates) > 0 {
			if err := tx.Model(&customer).Updates(customerUpdates).Error; err != nil {
				return err
			}
		}

		// 4. Update reading and financial values
		hasCurrReading := payload["current_reading"] != nil || payload["currReading"] != nil
		hasPrevReading := payload["previous_reading"] != nil || payload["prevReading"] != nil
		hasUnitPrice := payload["kwh_price"] != nil || payload["unit_price"] != nil || payload["unitPrice"] != nil
		hasServiceFee := payload["fixed_fee"] != nil || payload["service_fee"] != nil || payload["serviceFee"] != nil
		hasArrears := payload["arrears"] != nil
		hasPaidAmount := payload["paid_amount"] != nil || payload["paidAmount"] != nil

		if hasCurrReading || hasPrevReading || hasUnitPrice || hasServiceFee || hasArrears || hasPaidAmount {
			currReading := 0.0
			prevReading := customer.InitialReading
			kwhPrice := 1400.0
			fixedFee := 1000.0
			arrears := 0.0
			paidAmount := 0.0

			if customer.SubscriptionPlan != nil {
				if customer.SubscriptionPlan.KwhPrice > 0 {
					kwhPrice = customer.SubscriptionPlan.KwhPrice
				}
				if customer.SubscriptionPlan.FixedFee >= 0 {
					fixedFee = customer.SubscriptionPlan.FixedFee
				}
			}

			if hasTargetInvoice {
				currReading = targetInvoice.CurrentReading
				prevReading = targetInvoice.PreviousReading
				if targetInvoice.KwhPriceSnapshot > 0 {
					kwhPrice = targetInvoice.KwhPriceSnapshot
				}
				if targetInvoice.FixedFeeSnapshot >= 0 {
					fixedFee = targetInvoice.FixedFeeSnapshot
				}
				arrears = targetInvoice.Arrears
				paidAmount = targetInvoice.PaidAmount
			}

			if hasCurrReading {
				if payload["current_reading"] != nil {
					currReading = toFloat64(payload["current_reading"])
				} else {
					currReading = toFloat64(payload["currReading"])
				}
			}
			if hasPrevReading {
				if payload["previous_reading"] != nil {
					prevReading = toFloat64(payload["previous_reading"])
				} else {
					prevReading = toFloat64(payload["prevReading"])
				}
			}
			if hasUnitPrice {
				if payload["kwh_price"] != nil {
					kwhPrice = toFloat64(payload["kwh_price"])
				} else if payload["unit_price"] != nil {
					kwhPrice = toFloat64(payload["unit_price"])
				} else {
					kwhPrice = toFloat64(payload["unitPrice"])
				}
			}
			if hasServiceFee {
				if payload["fixed_fee"] != nil {
					fixedFee = toFloat64(payload["fixed_fee"])
				} else if payload["service_fee"] != nil {
					fixedFee = toFloat64(payload["service_fee"])
				} else {
					fixedFee = toFloat64(payload["serviceFee"])
				}
			}
			if hasArrears {
				arrears = toFloat64(payload["arrears"])
			}
			if hasPaidAmount {
				if payload["paid_amount"] != nil {
					paidAmount = toFloat64(payload["paid_amount"])
				} else {
					paidAmount = toFloat64(payload["paidAmount"])
				}
			}

			// Financial calculation
			consumption := 0.0
			if currReading > 0 && currReading >= prevReading {
				consumption = math.Max(0, currReading-prevReading)
			}
			consumptionValue := math.Round(consumption*kwhPrice*100) / 100
			totalAmount := math.Round((consumptionValue+fixedFee)*100) / 100
			totalDue := math.Round((totalAmount+arrears)*100) / 100
			remainingAmount := math.Round((totalDue-paidAmount)*100) / 100

			status := "Unpaid"
			if remainingAmount <= 0 && paidAmount > 0 {
				status = "Paid"
			} else if paidAmount > 0 {
				status = "Partially_Paid"
			}

			if hasTargetInvoice {
				targetInvoice.CurrentReading = currReading
				targetInvoice.PreviousReading = prevReading
				targetInvoice.Consumption = consumption
				targetInvoice.ConsumptionValue = consumptionValue
				targetInvoice.KwhPriceSnapshot = kwhPrice
				targetInvoice.FixedFeeSnapshot = fixedFee
				targetInvoice.Arrears = arrears
				targetInvoice.TotalAmount = totalAmount
				targetInvoice.TotalDue = totalDue
				targetInvoice.PaidAmount = paidAmount
				targetInvoice.RemainingAmount = remainingAmount
				targetInvoice.Status = status
				if err := tx.Save(&targetInvoice).Error; err != nil {
					return fmt.Errorf("failed to save invoice: %w", err)
				}

				// Cascade updates to downstream invoices for this customer ordered strictly by cycle chronology
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

					cascadePrev := currReading
					if cascadePrev == 0 {
						cascadePrev = prevReading
					}
					cascadeArr := remainingAmount

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
			}

			if currReading > 0 {
				tx.Model(&customer).Update("last_reading", currReading)
			}
		}

		// 5. In-Transaction Atomic Audit Log with structured JSON Diff
		var ipPtr *string
		if auditCtx.IPAddress != "" {
			ipPtr = &auditCtx.IPAddress
		}

		diffObj := map[string]interface{}{
			"target_id":   id,
			"customer_id": resolvedCustomerID,
			"payload":     payload,
		}
		diffBytes, _ := json.Marshal(diffObj)
		diffStr := string(diffBytes)

		entityType := "CUSTOMER"
		if hasTargetInvoice && id == targetInvoice.ID {
			entityType = "INVOICE"
		}

		_ = tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "GRID_CELL_UPDATE",
			Entity:    entityType,
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &diffStr,
		})

		return nil
	})

	if err != nil {
		return nil, err
	}

	return s.GetCustomer(resolvedCustomerID)
}

func toFloat64(val interface{}) float64 {
	switch v := val.(type) {
	case float64:
		return v
	case float32:
		return float64(v)
	case int:
		return float64(v)
	case int64:
		return float64(v)
	case string:
		var f float64
		fmt.Sscanf(ToEnglishDigits(v), "%f", &f)
		return f
	default:
		return 0
	}
}

func (s *CustomerService) DeleteCustomer(id int64, auditCtx models.AuditContext) error {
	var ipPtr *string
	if auditCtx.IPAddress != "" {
		ipPtr = &auditCtx.IPAddress
	}
	details := fmt.Sprintf("تم حذف المشترك رقم [%d]", id)

	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&models.Customer{}).Where("id = ?", id).Update("is_deleted", true).Error; err != nil {
			return err
		}
		return tx.Create(&models.AuditLog{
			UserID:    auditCtx.UserID,
			Action:    "CUSTOMER_DELETE",
			Entity:    "CUSTOMER",
			EntityID:  strPtr(fmt.Sprintf("%d", id)),
			IPAddress: ipPtr,
			Details:   &details,
		}).Error
	})
}

func (s *CustomerService) enrichCustomersBatch(customers []models.Customer) {
	if len(customers) == 0 {
		return
	}

	customerIDs := make([]int64, len(customers))
	for i, c := range customers {
		customerIDs[i] = c.ID
	}

	// 1. Batch fetch latest reading per customer
	type LastReadingRow struct {
		CustomerID   int64   `gorm:"column:customer_id"`
		ReadingValue float64 `gorm:"column:reading_value"`
	}
	var lastReadings []LastReadingRow
	s.db.Raw(`
		SELECT DISTINCT ON (customer_id) customer_id, reading_value
		FROM meter_readings
		WHERE customer_id IN (?)
		ORDER BY customer_id, id DESC
	`, customerIDs).Scan(&lastReadings)

	lastReadingMap := make(map[int64]float64, len(lastReadings))
	for _, r := range lastReadings {
		lastReadingMap[r.CustomerID] = r.ReadingValue
	}

	// 2. Batch fetch latest invoice per customer
	var latestInvoices []models.Invoice
	s.db.Raw(`
		SELECT DISTINCT ON (customer_id) *
		FROM invoices
		WHERE customer_id IN (?)
		ORDER BY customer_id, id DESC
	`, customerIDs).Scan(&latestInvoices)

	latestInvoiceMap := make(map[int64]models.Invoice, len(latestInvoices))
	for _, inv := range latestInvoices {
		if inv.CustomerID != nil {
			latestInvoiceMap[*inv.CustomerID] = inv
		}
	}

	// 3. Batch fetch remaining arrears from unpaid/partially paid invoices
	type ArrearsRow struct {
		CustomerID     int64   `gorm:"column:customer_id"`
		RemainingTotal float64 `gorm:"column:remaining_total"`
	}
	var arrearsRows []ArrearsRow
	s.db.Model(&models.Invoice{}).
		Select("customer_id, COALESCE(SUM(remaining_amount), 0) as remaining_total").
		Where("customer_id IN (?) AND status IN ('Unpaid', 'Partially_Paid')", customerIDs).
		Group("customer_id").
		Scan(&arrearsRows)

	arrearsMap := make(map[int64]float64, len(arrearsRows))
	for _, a := range arrearsRows {
		arrearsMap[a.CustomerID] = a.RemainingTotal
	}

	// 4. Batch fetch available credits
	type CreditRow struct {
		CustomerID     int64   `gorm:"column:customer_id"`
		AvailableTotal float64 `gorm:"column:available_total"`
	}
	var creditRows []CreditRow
	s.db.Model(&models.CustomerCredit{}).
		Select("customer_id, COALESCE(SUM(remaining_amount), 0) as available_total").
		Where("customer_id IN (?) AND status = 'AVAILABLE'", customerIDs).
		Group("customer_id").
		Scan(&creditRows)

	creditsMap := make(map[int64]float64, len(creditRows))
	for _, cr := range creditRows {
		creditsMap[cr.CustomerID] = cr.AvailableTotal
	}

	for i := range customers {
		c := &customers[i]
		hasInv := false
		var inv models.Invoice
		if foundInv, ok := latestInvoiceMap[c.ID]; ok {
			hasInv = true
			inv = foundInv
			invCopy := foundInv
			c.LatestInvoice = &invCopy
		}

		if lr, ok := lastReadingMap[c.ID]; ok {
			c.LastReading = lr
			c.CurrentReading = lr
		} else if hasInv {
			c.LastReading = inv.CurrentReading
			c.CurrentReading = inv.CurrentReading
		} else {
			c.LastReading = c.InitialReading
			c.CurrentReading = c.InitialReading
		}

		if hasInv {
			c.PreviousReading = inv.PreviousReading
			c.PaidAmount = inv.PaidAmount
		} else {
			c.PreviousReading = c.InitialReading
			c.PaidAmount = 0
		}

		c.Arrears = arrearsMap[c.ID]
		c.TotalDue = arrearsMap[c.ID]
		c.AvailableCredits = creditsMap[c.ID]
		c.Balance = c.Arrears - c.AvailableCredits
	}
}

func (s *CustomerService) enrichCustomerCalculations(c *models.Customer) {
	var latestInvoice models.Invoice
	hasInv := s.db.Where("customer_id = ?", c.ID).Order("id DESC").First(&latestInvoice).Error == nil
	if hasInv {
		invCopy := latestInvoice
		c.LatestInvoice = &invCopy
		c.PreviousReading = latestInvoice.PreviousReading
		c.PaidAmount = latestInvoice.PaidAmount
	} else {
		c.PreviousReading = c.InitialReading
		c.PaidAmount = 0
	}

	var lastReading models.MeterReading
	if err := s.db.Where("customer_id = ?", c.ID).
		Order("id DESC").First(&lastReading).Error; err == nil {
		c.LastReading = lastReading.ReadingValue
		c.CurrentReading = lastReading.ReadingValue
	} else if hasInv {
		c.LastReading = latestInvoice.CurrentReading
		c.CurrentReading = latestInvoice.CurrentReading
	} else {
		c.LastReading = c.InitialReading
		c.CurrentReading = c.InitialReading
	}

	var invoiceSummary struct {
		RemainingTotal float64
	}
	s.db.Model(&models.Invoice{}).
		Select("COALESCE(SUM(remaining_amount), 0) as remaining_total").
		Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid')", c.ID).
		Scan(&invoiceSummary)

	var creditSummary struct {
		AvailableTotal float64
	}
	s.db.Model(&models.CustomerCredit{}).
		Select("COALESCE(SUM(remaining_amount), 0) as available_total").
		Where("customer_id = ? AND status = 'AVAILABLE'", c.ID).
		Scan(&creditSummary)

	c.Arrears = invoiceSummary.RemainingTotal
	c.TotalDue = invoiceSummary.RemainingTotal
	c.AvailableCredits = creditSummary.AvailableTotal
	c.Balance = invoiceSummary.RemainingTotal - creditSummary.AvailableTotal
}

func (s *CustomerService) GetRoutes() ([]string, error) {
	var routes []string
	err := s.db.Model(&models.Customer{}).
		Where("is_deleted = false AND route_number IS NOT NULL AND route_number != ''").
		Distinct("route_number").
		Order("route_number ASC").
		Pluck("route_number", &routes).Error
	return routes, err
}

func (s *CustomerService) GetRegions() ([]string, error) {
	var regions []string
	err := s.db.Model(&models.Customer{}).
		Where("is_deleted = false AND address IS NOT NULL AND address != ''").
		Distinct("address").
		Order("address ASC").
		Pluck("address", &regions).Error
	return regions, err
}