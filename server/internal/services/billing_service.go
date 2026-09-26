package services

import (
	"fmt"
	"log"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"smartpower/internal/database"
	"smartpower/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type BillingService struct {
	db *gorm.DB
}

func NewBillingService() *BillingService {
	return &BillingService{
		db: database.DB,
	}
}

type InvoiceFilter struct {
	CustomerID   int64
	BillingCycle string
	Status       string
	RouteNumber  string
	Region       string
	Search       string
	Page         int
	Limit        int
}

// getCycleAliases returns all possible alias strings for a given cycle name.
func getCycleAliases(cycle string) []string {
	trimmed := strings.TrimSpace(cycle)
	if trimmed == "" || strings.EqualFold(trimmed, "ALL") {
		return nil
	}

	norm := strings.ReplaceAll(trimmed, "أ", "ا")
	norm = strings.ReplaceAll(norm, "إ", "ا")
	norm = strings.ReplaceAll(norm, "آ", "ا")
	norm = strings.TrimPrefix(norm, "شهر ")
	norm = strings.TrimSpace(norm)

	year := 2026
	if match := yearRegex.FindString(norm); match != "" {
		if y, err := strconv.Atoi(match); err == nil && y >= 2000 && y <= 2100 {
			year = y
		}
	}
	normWithoutYear := yearRegex.ReplaceAllString(norm, "")

	months := []struct {
		name   string
		numStr string
	}{
		{"يناير", "01"}, {"فبراير", "02"}, {"مارس", "03"}, {"ابريل", "04"},
		{"مايو", "05"}, {"يونيو", "06"}, {"يوليو", "07"}, {"اغسطس", "08"},
		{"سبتمبر", "09"}, {"اكتوبر", "10"}, {"نوفمبر", "11"}, {"ديسمبر", "12"},
	}

	for _, m := range months {
		if strings.Contains(norm, m.name) || strings.Contains(norm, m.numStr) {
			cycleNum := "1"
			if strings.Contains(normWithoutYear, "2") || strings.Contains(normWithoutYear, "30") || strings.Contains(normWithoutYear, "B") {
				cycleNum = "2"
			}

			arabicName := m.name
			if m.name == "اغسطس" {
				arabicName = "أغسطس"
			} else if m.name == "ابريل" {
				arabicName = "أبريل"
			} else if m.name == "اكتوبر" {
				arabicName = "أكتوبر"
			}

			var primaryName string
			if year == 2026 {
				primaryName = fmt.Sprintf("%s %s", arabicName, cycleNum)
			} else {
				primaryName = fmt.Sprintf("%s %s - %d", arabicName, cycleNum, year)
			}

			aliases := []string{
				primaryName,
				fmt.Sprintf("%s %s %d", arabicName, cycleNum, year),
				fmt.Sprintf("%s %s - %d", arabicName, cycleNum, year),
				fmt.Sprintf("%s %s", arabicName, cycleNum),
				fmt.Sprintf("%s %s %d", m.name, cycleNum, year),
				fmt.Sprintf("%s %s - %d", m.name, cycleNum, year),
				fmt.Sprintf("%s %s", m.name, cycleNum),
				fmt.Sprintf("شهر %s %s", arabicName, cycleNum),
				fmt.Sprintf("شهر %s %s %d", arabicName, cycleNum, year),
				fmt.Sprintf("شهر %s %s - %d", arabicName, cycleNum, year),
				fmt.Sprintf("شهر %s %s", m.name, cycleNum),
				fmt.Sprintf("%d-%s-%s", year, m.numStr, cycleNum),
			}
			if cycleNum == "1" {
				aliases = append(aliases, fmt.Sprintf("%d-%s", year, m.numStr))
			}
			return aliases
		}
	}

	return []string{trimmed}
}

// EnsureCycleInvoices guarantees that every active customer has an invoice in the target cycle,
// rolling over the previous reading and remaining balance (arrears or credit).
func (s *BillingService) EnsureCycleInvoices(cycle string) error {
	trimmedCycle := strings.TrimSpace(cycle)
	if trimmedCycle == "" || strings.EqualFold(trimmedCycle, "ALL") {
		return nil
	}

	primaryCycleName := FormatCanonicalCycle(trimmedCycle)
	if primaryCycleName == "" {
		primaryCycleName = trimmedCycle
	}
	aliases := getCycleAliases(primaryCycleName)

	// تمديد المهلة الزمنية للفوترة المجمعة لضمان إتمام كافة المشتركين دون انقطاع
	_ = s.db.Exec("SET LOCAL statement_timeout = '300s'").Error

	var activeCustomers []models.Customer
	if err := s.db.Preload("SubscriptionPlan").
		Where("is_deleted = false AND status = 'Active'").
		Order("sort_order ASC, id ASC").
		Find(&activeCustomers).Error; err != nil {
		return err
	}

	now := time.Now().UTC()
	dueDate := now.AddDate(0, 0, 10)

	for _, cust := range activeCustomers {
		custStartCycle := cust.StartCycle
		if custStartCycle == "" {
			custStartCycle = "أغسطس 1"
		}
		targetCycleIdx := GetCycleSortIndex(primaryCycleName)
		if targetCycleIdx < GetCycleSortIndex(custStartCycle) {
			continue // Do not create or show invoices for cycles prior to customer's start cycle
		}

		var existingCount int64
		s.db.Model(&models.Invoice{}).
			Where("customer_id = ? AND (billing_cycle = ? OR billing_cycle IN ?)", cust.ID, primaryCycleName, aliases).
			Count(&existingCount)

		if existingCount == 0 {
			// Find immediately preceding invoice for this customer based on chronological cycle index
			var allInvoices []models.Invoice
			s.db.Where("customer_id = ? AND approval_status != 'REJECTED'", cust.ID).
				Find(&allInvoices)

			var prevInvoice *models.Invoice
			maxPrevIdx := -1
			for i := range allInvoices {
				inv := &allInvoices[i]
				if inv.BillingCycle == nil {
					continue
				}
				idx := GetCycleSortIndex(*inv.BillingCycle)
				if idx < targetCycleIdx && idx > maxPrevIdx {
					maxPrevIdx = idx
					prevInvoice = inv
				}
			}

			var prevReading float64 = cust.InitialReading
			var arrears float64 = 0.0

			if prevInvoice != nil {
				if prevInvoice.CurrentReading > 0 {
					prevReading = prevInvoice.CurrentReading
				} else if prevInvoice.PreviousReading > 0 {
					prevReading = prevInvoice.PreviousReading
				}
				arrears = prevInvoice.RemainingAmount
			} else {
				// Fallback: check latest meter reading
				var lastReading models.MeterReading
				if err := s.db.Where("customer_id = ? AND approval_status = 'APPROVED'", cust.ID).
					Order("id DESC").First(&lastReading).Error; err == nil {
					prevReading = lastReading.ReadingValue
				}
				arrears = cust.TotalDue
			}

			kwhPrice := 1400.0
			fixedFee := 1000.0
			if cust.SubscriptionPlan != nil {
				if cust.SubscriptionPlan.KwhPrice > 0 {
					kwhPrice = cust.SubscriptionPlan.KwhPrice
				}
				if cust.SubscriptionPlan.FixedFee >= 0 {
					fixedFee = cust.SubscriptionPlan.FixedFee
				}
				if cust.SubscriptionPlan.GracePeriodDays > 0 {
					dueDate = now.AddDate(0, 0, cust.SubscriptionPlan.GracePeriodDays)
				}
			}

			totalAmount := fixedFee
			totalDue := totalAmount + arrears
			invNumber := fmt.Sprintf("INV-%s-%s", strings.ReplaceAll(primaryCycleName, " ", "-"), cust.SubscriberNumber)

			newInvoice := models.Invoice{
				CustomerID:       &cust.ID,
				InvoiceNumber:    &invNumber,
				BillingCycle:     &primaryCycleName,
				PreviousReading:  prevReading,
				CurrentReading:   0,
				Consumption:      0,
				ConsumptionValue: 0,
				KwhPriceSnapshot: kwhPrice,
				FixedFeeSnapshot: fixedFee,
				Arrears:          arrears,
				TotalAmount:      totalAmount,
				TotalDue:         totalDue,
				PaidAmount:       0,
				RemainingAmount:  totalDue,
				DueDate:          dueDate,
				ApprovalStatus:   "PENDING",
				Status:           "Unpaid",
				CreatedAt:        &now,
			}

			_ = s.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&newInvoice)
		}

		// Resync customer invoice chain to guarantee continuity across all cycles
		_ = s.ResyncCustomerInvoicesChain(cust.ID)
	}

	return nil
}

// ResyncCustomerInvoicesChain performs a strict chronological cascade across all invoices of a customer,
// rolling over readings and remaining balances through every billing cycle (August -> September -> October -> November -> December -> January 2027...).
func (s *BillingService) ResyncCustomerInvoicesChain(customerID int64) error {
	var invoices []models.Invoice
	if err := s.db.Where("customer_id = ? AND approval_status != 'REJECTED'", customerID).
		Find(&invoices).Error; err != nil {
		return err
	}

	if len(invoices) <= 1 {
		return nil
	}

	// Sort invoices in strict chronological cycle order
	sort.Slice(invoices, func(i, j int) bool {
		cI := ""
		if invoices[i].BillingCycle != nil {
			cI = *invoices[i].BillingCycle
		}
		cJ := ""
		if invoices[j].BillingCycle != nil {
			cJ = *invoices[j].BillingCycle
		}
		return GetCycleSortIndex(cI) < GetCycleSortIndex(cJ)
	})

	var cascadePrev float64 = 0
	var cascadeArr float64 = 0

	for i := range invoices {
		inv := &invoices[i]

		if i == 0 {
			// First cycle in the series: baseline
			cascadePrev = inv.PreviousReading
			if inv.CurrentReading > 0 {
				cascadePrev = inv.CurrentReading
			}
			cascadeArr = inv.RemainingAmount
			continue
		}

		// Rollover previous reading
		if cascadePrev > 0 {
			inv.PreviousReading = cascadePrev
			if inv.CurrentReading > 0 && inv.CurrentReading < inv.PreviousReading {
				inv.CurrentReading = inv.PreviousReading
			}
		}
		inv.Arrears = cascadeArr

		// Recalculate consumption & financials
		downCons := 0.0
		if inv.CurrentReading > 0 && inv.CurrentReading >= inv.PreviousReading {
			downCons = inv.CurrentReading - inv.PreviousReading
		}
		inv.Consumption = downCons
		inv.ConsumptionValue = math.Round(downCons*inv.KwhPriceSnapshot*100) / 100
		inv.TotalAmount = math.Round((inv.ConsumptionValue+inv.FixedFeeSnapshot)*100) / 100
		inv.TotalDue = math.Round((inv.TotalAmount+inv.Arrears)*100) / 100
		inv.RemainingAmount = math.Round((inv.TotalDue-inv.PaidAmount)*100) / 100

		if inv.RemainingAmount <= 0 {
			inv.Status = "Paid"
		} else if inv.PaidAmount > 0 {
			inv.Status = "Partially_Paid"
		} else {
			inv.Status = "Unpaid"
		}

		_ = s.db.Save(inv)

		if inv.CurrentReading > 0 {
			cascadePrev = inv.CurrentReading
		}
		cascadeArr = inv.RemainingAmount
	}

	return nil
}

func (s *BillingService) ListInvoices(filter InvoiceFilter) ([]models.Invoice, int64, error) {
	var invoices []models.Invoice
	var total int64

	query := s.db.Model(&models.Invoice{}).
		Joins("JOIN customers ON customers.id = invoices.customer_id")

	if filter.CustomerID > 0 {
		query = query.Where("invoices.customer_id = ?", filter.CustomerID)
	}

	if filter.BillingCycle != "" && !strings.EqualFold(filter.BillingCycle, "ALL") {
		aliases := getCycleAliases(filter.BillingCycle)
		query = query.Where("invoices.billing_cycle IN ?", aliases)
	}

	if filter.RouteNumber != "" && !strings.EqualFold(filter.RouteNumber, "ALL") {
		query = query.Where("customers.route_number = ?", filter.RouteNumber)
	}

	if filter.Region != "" && !strings.EqualFold(filter.Region, "ALL") {
		query = query.Where("customers.address ILIKE ?", "%"+filter.Region+"%")
	}

	if filter.Search != "" {
		searchTerm := "%" + filter.Search + "%"
		query = query.Where("customers.full_name ILIKE ? OR customers.subscriber_number ILIKE ? OR customers.phone_number ILIKE ? OR customers.meter_number ILIKE ?",
			searchTerm, searchTerm, searchTerm, searchTerm)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	limit := filter.Limit
	if limit <= 0 {
		limit = 1000
	}
	offset := 0
	if filter.Page > 1 {
		offset = (filter.Page - 1) * limit
	}

	err := query.Preload("Customer").
		Preload("Customer.SubscriptionPlan").
		Preload("MeterReading").
		Preload("Allocations").
		Order("customers.sort_order ASC, customers.id ASC, invoices.id ASC").
		Limit(limit).
		Offset(offset).
		Find(&invoices).Error

	return invoices, total, err
}

func (s *BillingService) GetInvoice(id int64) (*models.Invoice, error) {
	var invoice models.Invoice
	err := s.db.Preload("Customer").
		Preload("Customer.SubscriptionPlan").
		Preload("MeterReading").
		Preload("Allocations").
		Preload("Allocations.Payment").
		First(&invoice, id).Error
	if err != nil {
		return nil, err
	}
	return &invoice, nil
}

func (s *BillingService) GetBillingCycles() ([]string, error) {
	var rawCycles []string
	err := s.db.Model(&models.Invoice{}).
		Where("billing_cycle IS NOT NULL AND billing_cycle != '' AND approval_status != 'REJECTED'").
		Distinct("billing_cycle").
		Pluck("billing_cycle", &rawCycles).Error
	if err != nil {
		return nil, err
	}

	seen := make(map[string]bool)
	var cycles []string
	for _, c := range rawCycles {
		canonical := FormatCanonicalCycle(c)
		if canonical == "" {
			canonical = strings.TrimSpace(c)
		}
		if canonical != "" && !seen[canonical] {
			seen[canonical] = true
			cycles = append(cycles, canonical)
		}
	}

	sort.Slice(cycles, func(i, j int) bool {
		return GetCycleSortIndex(cycles[i]) > GetCycleSortIndex(cycles[j])
	})

	return cycles, nil
}

// DeduplicateInvoices scans and merges all duplicate invoices for the same customer within the same canonical billing cycle.
func (s *BillingService) DeduplicateInvoices() error {
	_ = s.db.Exec("DROP INDEX IF EXISTS uq_invoices_customer_cycle;").Error

	var allInvoices []models.Invoice
	if err := s.db.Where("approval_status != 'REJECTED'").Order("id ASC").Find(&allInvoices).Error; err != nil {
		return err
	}

	type cycleGroupKey struct {
		CustomerID     int64
		CanonicalCycle string
	}

	groups := make(map[cycleGroupKey][]models.Invoice)
	for _, inv := range allInvoices {
		if inv.CustomerID == nil {
			continue
		}
		cycle := ""
		if inv.BillingCycle != nil {
			cycle = *inv.BillingCycle
		}
		canonical := FormatCanonicalCycle(cycle)
		if canonical == "" {
			canonical = strings.TrimSpace(cycle)
		}
		key := cycleGroupKey{
			CustomerID:     *inv.CustomerID,
			CanonicalCycle: canonical,
		}
		groups[key] = append(groups[key], inv)
	}

	mergedGroups := 0
	for key, invs := range groups {
		if len(invs) == 1 {
			inv := invs[0]
			if inv.BillingCycle == nil || *inv.BillingCycle != key.CanonicalCycle {
				s.db.Model(&models.Invoice{}).Where("id = ?", inv.ID).Update("billing_cycle", key.CanonicalCycle)
			}
			continue
		}

		// Multiple invoices found for this customer and cycle!
		// Sort to find the best keeper:
		sort.SliceStable(invs, func(i, j int) bool {
			// 1. Paid amount > 0
			pi := invs[i].PaidAmount > 0
			pj := invs[j].PaidAmount > 0
			if pi != pj {
				return pi
			}
			// 2. Has meter reading link
			ri := invs[i].ReadingID != nil
			rj := invs[j].ReadingID != nil
			if ri != rj {
				return ri
			}
			// 3. Has positive current reading
			ci := invs[i].CurrentReading > 0
			cj := invs[j].CurrentReading > 0
			if ci != cj {
				return ci
			}
			// 4. Already has canonical cycle string
			cycI := invs[i].BillingCycle != nil && *invs[i].BillingCycle == key.CanonicalCycle
			cycJ := invs[j].BillingCycle != nil && *invs[j].BillingCycle == key.CanonicalCycle
			if cycI != cycJ {
				return cycI
			}
			// 5. Lowest ID
			return invs[i].ID < invs[j].ID
		})

		keeper := invs[0]
		duplicates := invs[1:]

		totalPaid := 0.0
		for _, inv := range invs {
			totalPaid += inv.PaidAmount
		}

		var dupIDs []int64
		for _, dup := range duplicates {
			dupIDs = append(dupIDs, dup.ID)
		}

		err := s.db.Transaction(func(tx *gorm.DB) error {
			if len(dupIDs) > 0 {
				// Re-link payments
				if err := tx.Model(&models.Payment{}).Where("invoice_id IN ?", dupIDs).Update("invoice_id", keeper.ID).Error; err != nil {
					return err
				}
				// Re-link payment allocations
				if err := tx.Model(&models.PaymentAllocation{}).Where("invoice_id IN ?", dupIDs).Update("invoice_id", keeper.ID).Error; err != nil {
					return err
				}

				// Delete duplicate invoices
				if err := tx.Where("id IN ?", dupIDs).Delete(&models.Invoice{}).Error; err != nil {
					return err
				}
			}

			// Calculate remaining amount and status
			rem := math.Round((keeper.TotalDue-totalPaid)*100) / 100
			status := "Unpaid"
			if rem <= 0 && totalPaid > 0 {
				status = "Paid"
			} else if totalPaid > 0 {
				status = "Partially_Paid"
			}

			if err := tx.Model(&models.Invoice{}).Where("id = ?", keeper.ID).Updates(map[string]interface{}{
				"billing_cycle":    key.CanonicalCycle,
				"paid_amount":      totalPaid,
				"remaining_amount": rem,
				"status":           status,
			}).Error; err != nil {
				return err
			}
			return nil
		})

		if err != nil {
			log.Printf("⚠️ [DeduplicateInvoices] Error merging customer %d in cycle %s: %v", key.CustomerID, key.CanonicalCycle, err)
		} else {
			mergedGroups++
		}
	}

	// Create unique constraint to prevent duplicate invoices forever
	if err := s.db.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_customer_cycle 
		ON public.invoices (customer_id, billing_cycle) 
		WHERE (approval_status != 'REJECTED');
	`).Error; err != nil {
		log.Printf("⚠️ [DeduplicateInvoices] Unique index warning: %v", err)
	}

	log.Printf("✅ [DeduplicateInvoices] Deduplicated invoices: merged %d duplicate groups across %d total groups", mergedGroups, len(groups))
	return nil
}

// GenerateNextCycle rolls over the specified cycle (e.g. "سبتمبر 1") into the subsequent cycle (e.g. "سبتمبر 2").
// It creates fresh invoices for all active customers with:
// - previous_reading = current_reading from the previous cycle
// - current_reading = previous_reading (consumption = 0 until recorded)
// - arrears = remaining_amount from the previous cycle invoice
// - total_due = fixed_fee_snapshot + arrears
// - paid_amount = 0, remaining_amount = total_due
func (s *BillingService) GenerateNextCycle(fromCycle string) (string, int, error) {
	fromCanonical := FormatCanonicalCycle(fromCycle)
	if fromCanonical == "" {
		fromCanonical = "سبتمبر 1"
	}
	targetCycle := GetNextCycleName(fromCanonical)

	// 1. Fetch all active customers with their subscription plan
	var customers []models.Customer
	if err := s.db.Preload("SubscriptionPlan").Where("is_deleted = false").Order("sort_order ASC, id ASC").Find(&customers).Error; err != nil {
		return "", 0, fmt.Errorf("فشل في استرجاع بيانات المشتركين: %w", err)
	}

	if len(customers) == 0 {
		return "", 0, fmt.Errorf("لا يوجد مشتركين نشطين في النظام")
	}

	// 2. Fetch existing invoices for the previous cycle
	aliases := getCycleAliases(fromCanonical)
	var prevInvoices []models.Invoice
	if len(aliases) > 0 {
		s.db.Where("billing_cycle IN ?", aliases).Find(&prevInvoices)
	} else {
		s.db.Where("billing_cycle = ?", fromCanonical).Find(&prevInvoices)
	}

	prevInvMap := make(map[int64]models.Invoice)
	for _, inv := range prevInvoices {
		if inv.CustomerID != nil {
			prevInvMap[*inv.CustomerID] = inv
		}
	}

	// 3. Fetch existing invoices for target cycle to avoid duplication
	targetAliases := getCycleAliases(targetCycle)
	var existingTargetInvoices []models.Invoice
	if len(targetAliases) > 0 {
		s.db.Where("billing_cycle IN ?", targetAliases).Find(&existingTargetInvoices)
	} else {
		s.db.Where("billing_cycle = ?", targetCycle).Find(&existingTargetInvoices)
	}

	existingTargetMap := make(map[int64]models.Invoice)
	for _, inv := range existingTargetInvoices {
		if inv.CustomerID != nil {
			existingTargetMap[*inv.CustomerID] = inv
		}
	}

	// 4. Perform atomic batch creation / update
	createdCount := 0
	err := s.db.Transaction(func(tx *gorm.DB) error {
		for _, cust := range customers {
			// Check if target invoice already exists
			if _, exists := existingTargetMap[cust.ID]; exists {
				continue
			}

			prevInv, hasPrev := prevInvMap[cust.ID]
			var prevReading float64 = 0
			var arrears float64 = 0

			if hasPrev {
				if prevInv.CurrentReading > 0 {
					prevReading = prevInv.CurrentReading
				} else if prevInv.PreviousReading > 0 {
					prevReading = prevInv.PreviousReading
				} else {
					prevReading = cust.InitialReading
				}
				arrears = prevInv.RemainingAmount
			} else {
				prevReading = cust.InitialReading
				arrears = cust.Balance
			}

			// Plan details
			rate := 1500.0
			fee := 1000.0
			if cust.SubscriptionPlan != nil {
				if cust.SubscriptionPlan.KwhPrice > 0 {
					rate = cust.SubscriptionPlan.KwhPrice
				}
				if cust.SubscriptionPlan.FixedFee > 0 {
					fee = cust.SubscriptionPlan.FixedFee
				}
			}

			// Financial fields
			totalAmount := fee
			totalDue := math.Round((fee+arrears)*100) / 100
			remainingAmount := totalDue

			invNum := fmt.Sprintf("INV-%s-%s", strings.ReplaceAll(targetCycle, " ", "-"), cust.SubscriberNumber)

			custID := cust.ID
			billingCycleStr := targetCycle
			now := time.Now()
			dueDate := now.AddDate(0, 0, 15)

			newInvoice := models.Invoice{
				CustomerID:       &custID,
				InvoiceNumber:    &invNum,
				BillingCycle:     &billingCycleStr,
				PreviousReading:  prevReading,
				CurrentReading:   prevReading,
				Consumption:      0,
				ConsumptionValue: 0,
				KwhPriceSnapshot: rate,
				FixedFeeSnapshot: fee,
				Arrears:          arrears,
				TotalAmount:      totalAmount,
				TotalDue:         totalDue,
				PaidAmount:       0,
				RemainingAmount:  remainingAmount,
				DueDate:          dueDate,
				ApprovalStatus:   "PENDING",
				Status:           "Unpaid",
				CreatedAt:        &now,
				UpdatedAt:        &now,
			}

			if err := tx.Create(&newInvoice).Error; err != nil {
				return fmt.Errorf("فشل في إنشاء فاتورة للمشترك %s: %w", cust.SubscriberNumber, err)
			}
			createdCount++
		}

		// Ensure target billing cycle exists in billing_cycles table
		var bcCount int64
		tx.Table("billing_cycles").Where("code = ?", targetCycle).Count(&bcCount)
		if bcCount == 0 {
			now := time.Now()
			newBC := map[string]interface{}{
				"code":       targetCycle,
				"name":       fmt.Sprintf("دورة %s", targetCycle),
				"start_date": now.Format("2006-01-02"),
				"end_date":   now.AddDate(0, 0, 15).Format("2006-01-02"),
				"due_date":   now.AddDate(0, 0, 20).Format("2006-01-02"),
				"status":     "OPEN",
				"created_at": now,
				"updated_at": now,
			}
			_ = tx.Table("billing_cycles").Create(&newBC).Error
		}

		return nil
	})

	if err != nil {
		return "", 0, err
	}

	log.Printf("🎉 [GenerateNextCycle] Generated next cycle %s with %d invoices (from %s)", targetCycle, createdCount, fromCanonical)
	return targetCycle, createdCount, nil
}