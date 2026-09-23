package services

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"
)

// cleanupCustomerTestData deletes all records related to a test customer in reverse foreign key order.
// This is critical to guarantee that no dummy customers (ID >= 500) remain in smartpower_db,
// ensuring TestVerifyDatabaseCleanup passes cleanly.
func cleanupCustomerTestData(t *testing.T, db *gorm.DB, custID int64, planID int64) {
	if custID <= 0 {
		return
	}
	db.Exec("DELETE FROM payment_allocations WHERE invoice_id IN (SELECT id FROM invoices WHERE customer_id = ?) OR payment_id IN (SELECT id FROM payments WHERE customer_id = ?)", custID, custID)
	db.Exec("DELETE FROM customer_credits WHERE customer_id = ?", custID)
	db.Exec("DELETE FROM payments WHERE customer_id = ?", custID)
	db.Exec("DELETE FROM invoices WHERE customer_id = ?", custID)
	db.Exec("DELETE FROM meter_readings WHERE customer_id = ?", custID)
	db.Exec("DELETE FROM customers WHERE id = ?", custID)
	if planID > 0 {
		db.Exec("DELETE FROM subscription_plans WHERE id = ?", planID)
	}
}

// createTestCustomerHelper creates a dedicated test plan and customer with a unique subscriber number.
func createTestCustomerHelper(t *testing.T, db *gorm.DB, name string, initialReading float64, kwhPrice float64, fixedFee float64) (*models.Customer, *models.SubscriptionPlan) {
	plan := models.SubscriptionPlan{
		PlanName: fmt.Sprintf("Plan_%s_%d", name, time.Now().UnixNano()%100000),
		KwhPrice: kwhPrice,
		FixedFee: fixedFee,
	}
	if err := db.Create(&plan).Error; err != nil {
		t.Fatalf("failed to create test plan: %v", err)
	}

	subNo := fmt.Sprintf("TST_%d", time.Now().UnixNano()%1000000)
	meterNo := fmt.Sprintf("MTR_%d", time.Now().UnixNano()%1000000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &meterNo,
		FullName:           fmt.Sprintf("Test Cust %s", name),
		SubscriptionPlanID: &plan.ID,
		InitialReading:     initialReading,
		Status:             "Active",
	}
	if err := db.Create(&cust).Error; err != nil {
		db.Exec("DELETE FROM subscription_plans WHERE id = ?", plan.ID)
		t.Fatalf("failed to create test customer: %v", err)
	}

	t.Cleanup(func() {
		cleanupCustomerTestData(t, db, cust.ID, plan.ID)
	})

	return &cust, &plan
}

// -----------------------------------------------------------------------------
// 1. Concurrency & Idempotency Tests (Race Conditions)
// -----------------------------------------------------------------------------

// TestConcurrency_DuplicatePaymentIdempotency simulates multiple concurrent payment requests
// with the exact same ClientMutationID targeting the same customer and invoice.
// It verifies that exactly 1 request succeeds, while all other concurrent requests are strictly
// rejected by the database unique constraint (payments_client_mutation_id_key) or idempotency checks,
// preventing duplicate records or double-counting in the ledger.
func TestConcurrency_DuplicatePaymentIdempotency(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, plan := createTestCustomerHelper(t, db, "Idempotency", 100.0, 300.0, 1000.0)

	// Create an initial invoice with 5,000 YER total due
	cycle := "2026-09-1"
	invNum := fmt.Sprintf("INV-%s-%s", cycle, cust.SubscriberNumber)
	now := time.Now().UTC()
	dueDate := now.AddDate(0, 0, 10)
	inv := models.Invoice{
		CustomerID:       &cust.ID,
		InvoiceNumber:    &invNum,
		BillingCycle:     &cycle,
		DueDate:          dueDate,
		PreviousReading:  100.0,
		CurrentReading:   110.0,
		Consumption:      10.0,
		ConsumptionValue: 3000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 300.0,
		Arrears:          1000.0,
		TotalAmount:      4000.0,
		TotalDue:         5000.0,
		PaidAmount:       0.0,
		RemainingAmount:  5000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
		CreatedAt:        &now,
	}
	if err := db.Create(&inv).Error; err != nil {
		t.Fatalf("failed to create test invoice: %v", err)
	}

	paymentService := NewPaymentService()

	// Shared idempotency key for concurrent requests
	sharedMutationID := uuid.New().String()
	numGoroutines := 5
	amountToPay := 1000.0

	var wg sync.WaitGroup
	type paymentResult struct {
		res *PaymentResult
		err error
	}
	results := make([]paymentResult, numGoroutines)

	// Launch concurrent payment requests
	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			mutationCopy := sharedMutationID
			req := CreatePaymentRequest{
				CustomerID:       cust.ID,
				InvoiceID:        &inv.ID,
				AmountPaid:       amountToPay,
				PaymentMethod:    "CASH",
				AccountantName:   "Admin",
				ClientMutationID: &mutationCopy,
			}
			res, err := paymentService.CreatePayment(req)
			results[idx] = paymentResult{res: res, err: err}
		}(i)
	}
	wg.Wait()

	// Verify that exactly 1 succeeds and 4 fail due to unique constraint / idempotency
	successCount := 0
	failCount := 0
	for _, r := range results {
		if r.err == nil {
			successCount++
		} else {
			failCount++
			errStr := strings.ToLower(r.err.Error())
			if !strings.Contains(errStr, "unique") &&
				!strings.Contains(errStr, "duplicate") &&
				!strings.Contains(errStr, "mutation") &&
				!strings.Contains(errStr, "payments_client_mutation_id_key") {
				t.Errorf("unexpected error message for duplicate mutation: %v", r.err)
			}
		}
	}

	if successCount != 1 {
		t.Fatalf("expected exactly 1 successful payment, got %d (failures: %d)", successCount, failCount)
	}
	if failCount != numGoroutines-1 {
		t.Fatalf("expected %d failed payments due to duplicate mutation, got %d", numGoroutines-1, failCount)
	}

	// Verify database state: exactly 1 payment record exists for this mutation ID
	var paymentsCount int64
	db.Model(&models.Payment{}).Where("client_mutation_id = ?", sharedMutationID).Count(&paymentsCount)
	if paymentsCount != 1 {
		t.Errorf("expected 1 payment in database, got %d", paymentsCount)
	}

	// Verify invoice: PaidAmount should be exactly 1,000 YER (not 5,000 YER), RemainingAmount should be 4,000 YER
	var updatedInv models.Invoice
	if err := db.First(&updatedInv, inv.ID).Error; err != nil {
		t.Fatalf("failed to reload invoice: %v", err)
	}
	if updatedInv.PaidAmount != 1000.0 {
		t.Errorf("double-counting detected! Expected PaidAmount=1000, got %.2f", updatedInv.PaidAmount)
	}
	if updatedInv.RemainingAmount != 4000.0 {
		t.Errorf("expected RemainingAmount=4000, got %.2f", updatedInv.RemainingAmount)
	}

	_ = plan
}

// TestConcurrency_ConcurrentPaymentsPessimisticLocking verifies that multiple concurrent payments
// with distinct mutation IDs targeting the same customer are safely serialized by PostgreSQL
// pessimistic row-level locking (SELECT ... FOR UPDATE).
// It verifies that no race condition or ledger balance corruption occurs and all voucher numbers are unique.
func TestConcurrency_ConcurrentPaymentsPessimisticLocking(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "Pessimistic", 100.0, 300.0, 1000.0)

	// Create invoice for 10,000 YER
	cycle := "2026-09-1"
	invNum := fmt.Sprintf("INV-%s-%s", cycle, cust.SubscriberNumber)
	now := time.Now().UTC()
	dueDate := now.AddDate(0, 0, 10)
	inv := models.Invoice{
		CustomerID:       &cust.ID,
		InvoiceNumber:    &invNum,
		BillingCycle:     &cycle,
		DueDate:          dueDate,
		PreviousReading:  100.0,
		CurrentReading:   130.0,
		Consumption:      30.0,
		ConsumptionValue: 9000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 300.0,
		Arrears:          0.0,
		TotalAmount:      10000.0,
		TotalDue:         10000.0,
		PaidAmount:       0.0,
		RemainingAmount:  10000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
		CreatedAt:        &now,
	}
	if err := db.Create(&inv).Error; err != nil {
		t.Fatalf("failed to create test invoice: %v", err)
	}

	paymentService := NewPaymentService()
	numGoroutines := 5
	amountPerPayment := 1000.0

	var wg sync.WaitGroup
	type payOutcome struct {
		receipt string
		err     error
	}
	outcomes := make([]payOutcome, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			uniqueMutation := uuid.New().String()
			req := CreatePaymentRequest{
				CustomerID:       cust.ID,
				InvoiceID:        &inv.ID,
				AmountPaid:       amountPerPayment,
				PaymentMethod:    "CASH",
				AccountantName:   "Admin",
				ClientMutationID: &uniqueMutation,
			}
			res, err := paymentService.CreatePayment(req)
			if err != nil {
				outcomes[idx] = payOutcome{err: err}
			} else {
				receipt := ""
				if res.Payment.ReceiptNumber != nil {
					receipt = *res.Payment.ReceiptNumber
				}
				outcomes[idx] = payOutcome{receipt: receipt, err: nil}
			}
		}(i)
	}
	wg.Wait()

	// Verify all 5 payments succeeded without deadlocks or row-lock collisions
	receiptMap := make(map[string]bool)
	for i, o := range outcomes {
		if o.err != nil {
			t.Fatalf("payment %d failed unexpectedly: %v", i, o.err)
		}
		if o.receipt == "" {
			t.Errorf("payment %d received empty receipt number", i)
		}
		if receiptMap[o.receipt] {
			t.Errorf("duplicate receipt voucher number collision detected: %s", o.receipt)
		}
		receiptMap[o.receipt] = true
	}

	// Verify ledger consistency:
	// Total paid should be exactly 5,000 YER (5 * 1000)
	// Remaining balance should be exactly 5,000 YER (10000 - 5000)
	var updatedInv models.Invoice
	if err := db.First(&updatedInv, inv.ID).Error; err != nil {
		t.Fatalf("failed to query updated invoice: %v", err)
	}
	if updatedInv.PaidAmount != 5000.0 {
		t.Errorf("expected PaidAmount=5000.0, got %.2f", updatedInv.PaidAmount)
	}
	if updatedInv.RemainingAmount != 5000.0 {
		t.Errorf("expected RemainingAmount=5000.0, got %.2f", updatedInv.RemainingAmount)
	}

	var totalPaymentsCount int64
	db.Model(&models.Payment{}).Where("customer_id = ?", cust.ID).Count(&totalPaymentsCount)
	if totalPaymentsCount != int64(numGoroutines) {
		t.Errorf("expected %d payment records, got %d", numGoroutines, totalPaymentsCount)
	}
}

// TestConcurrency_InvoiceGenerationDeduplication verifies that when multiple concurrent goroutines
// trigger invoice generation (via EnsureCycleInvoices or concurrent CreateReading) for the same cycle,
// only 1 invoice is created and database unique constraints/conflict clauses prevent collisions.
func TestConcurrency_InvoiceGenerationDeduplication(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "Dedup", 200.0, 300.0, 1500.0)

	// Set StartCycle to future cycle "2027-02-1"
	targetCycle := "2027-02-1"
	canonicalCycle := FormatCanonicalCycle(targetCycle)
	db.Model(cust).Update("start_cycle", targetCycle)

	billingService := NewBillingService()
	numGoroutines := 5

	var wg sync.WaitGroup
	errs := make([]error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			errs[idx] = billingService.EnsureCycleInvoices(targetCycle)
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("goroutine %d failed in EnsureCycleInvoices: %v", i, err)
		}
	}

	// Verify only 1 invoice was generated for this customer in targetCycle
	var invoices []models.Invoice
	db.Where("customer_id = ? AND (billing_cycle = ? OR billing_cycle = ?)", cust.ID, targetCycle, canonicalCycle).Find(&invoices)
	if len(invoices) != 1 {
		t.Fatalf("expected exactly 1 invoice for customer %d in cycle %s (%s), found %d", cust.ID, targetCycle, canonicalCycle, len(invoices))
	}
}

// -----------------------------------------------------------------------------
// 2. Chronological Sequence Lock Tests
// -----------------------------------------------------------------------------

// TestChronologicalLock_PastCycleRejection verifies that attempts to insert or modify a reading/invoice
// for a past billing cycle when a newer cycle already exists for the customer are strictly rejected.
func TestChronologicalLock_PastCycleRejection(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "Chrono", 100.0, 300.0, 1000.0)
	readingService := NewReadingService()

	// 1. Record reading for newer cycle "2026-09-1" (SortIndex: 48641)
	newerCycle := "2026-09-1"
	res1, err := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   120.0,
		BillingCycle:   newerCycle,
		ApprovalStatus: "APPROVED",
	})
	if err != nil {
		t.Fatalf("failed to create reading for cycle %s: %v", newerCycle, err)
	}
	if res1.Invoice.ID == 0 {
		t.Fatalf("expected valid invoice created for %s", newerCycle)
	}

	// 2. Attempt to record reading for a past cycle "2026-08-2" (SortIndex: 48640 < 48641)
	pastCycle := "2026-08-2"
	_, errPast := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   130.0,
		BillingCycle:   pastCycle,
		ApprovalStatus: "APPROVED",
	})

	if errPast == nil {
		t.Fatalf("expected chronological sequence violation error when inserting for past cycle %s, but got nil!", pastCycle)
	}

	errPastStr := strings.ToLower(errPast.Error())
	if !strings.Contains(errPastStr, "chronological") &&
		!strings.Contains(errPastStr, "past cycle") &&
		!strings.Contains(errPastStr, "violation") {
		t.Errorf("expected chronological error message, got: %v", errPast)
	}

	// Verify no invoice or reading was created for the past cycle
	var pastInvoicesCount int64
	db.Model(&models.Invoice{}).Where("customer_id = ? AND billing_cycle = ?", cust.ID, pastCycle).Count(&pastInvoicesCount)
	if pastInvoicesCount > 0 {
		t.Errorf("expected 0 invoices for past cycle %s, found %d", pastCycle, pastInvoicesCount)
	}

	// 3. Attempt another past cycle "2026-08-1" with a reading lower than latest (110 < 120)
	olderPastCycle := "2026-08-1"
	_, errOlderPast := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   110.0,
		BillingCycle:   olderPastCycle,
		ApprovalStatus: "APPROVED",
	})
	if errOlderPast == nil {
		t.Fatalf("expected error when inserting past cycle with lower reading, got nil")
	}

	// 4. Verify that forward chronological insertion for next cycle "2026-09-2" (SortIndex: 48642) succeeds cleanly
	forwardCycle := "2026-09-2"
	resForward, errForward := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   140.0,
		BillingCycle:   forwardCycle,
		ApprovalStatus: "APPROVED",
	})
	if errForward != nil {
		t.Fatalf("expected forward cycle %s to succeed, got error: %v", forwardCycle, errForward)
	}
	if resForward.Invoice.CurrentReading != 140.0 {
		t.Errorf("expected CurrentReading=140.0, got %.2f", resForward.Invoice.CurrentReading)
	}
}

// -----------------------------------------------------------------------------
// 3. Mathematical Boundaries & Overflow Tests
// -----------------------------------------------------------------------------

// TestMathematicalBoundaries_ZeroKwhSubscriptionInvoice verifies that 0 kWh consumption
// (CurrentReading == PreviousReading) generates a valid subscription-only invoice with
// FixedFeeSnapshot applied and 0 consumption value.
func TestMathematicalBoundaries_ZeroKwhSubscriptionInvoice(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "ZeroKwh", 500.0, 350.0, 1500.0)
	readingService := NewReadingService()

	// Current reading is exactly equal to Previous reading (500.0 == 500.0) -> 0 kWh consumption
	cycle := "2026-10-1"
	res, err := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   500.0,
		BillingCycle:   cycle,
		ApprovalStatus: "APPROVED",
	})
	if err != nil {
		t.Fatalf("CreateReading failed for 0 kWh: %v", err)
	}

	// Verify mathematical boundaries
	inv := res.Invoice
	if inv.Consumption != 0.0 {
		t.Errorf("expected Consumption=0.0, got %.2f", inv.Consumption)
	}
	if inv.ConsumptionValue != 0.0 {
		t.Errorf("expected ConsumptionValue=0.0, got %.2f", inv.ConsumptionValue)
	}
	if inv.FixedFeeSnapshot != 1500.0 {
		t.Errorf("expected FixedFeeSnapshot=1500.0, got %.2f", inv.FixedFeeSnapshot)
	}
	if inv.TotalAmount != 1500.0 {
		t.Errorf("expected TotalAmount=1500.0 (subscription fee only), got %.2f", inv.TotalAmount)
	}
	if inv.TotalDue != 1500.0 {
		t.Errorf("expected TotalDue=1500.0, got %.2f", inv.TotalDue)
	}
	if inv.RemainingAmount != 1500.0 {
		t.Errorf("expected RemainingAmount=1500.0, got %.2f", inv.RemainingAmount)
	}
	if inv.Status != "Unpaid" {
		t.Errorf("expected Status='Unpaid', got '%s'", inv.Status)
	}
}

// TestMathematicalBoundaries_NegativeConsumptionRejection verifies that negative consumption
// (CurrentReading < PreviousReading) is strictly rejected by both Go service validation and
// PostgreSQL database check constraints (chk_invoices_monotonic, chk_meter_readings_amounts).
func TestMathematicalBoundaries_NegativeConsumptionRejection(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "Negative", 300.0, 300.0, 1000.0)
	readingService := NewReadingService()

	// 1. Attempt negative consumption via ReadingService (Current 280.0 < Previous 300.0)
	_, errReading := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   280.0,
		BillingCycle:   "2026-10-1",
		ApprovalStatus: "APPROVED",
	})
	if errReading == nil {
		t.Fatalf("expected error for negative consumption (280 < 300), but got nil")
	}
	if !strings.Contains(errReading.Error(), "cannot be less than previous reading") &&
		!strings.Contains(errReading.Error(), "invalid reading") {
		t.Errorf("unexpected error message: %v", errReading)
	}

	// 2. Direct DB verification: Attempt inserting raw MeterReading with negative consumption
	rawReading := models.MeterReading{
		CustomerID:      &cust.ID,
		ReadingValue:    280.0,
		CollectorName:   "TestCollector",
		ApprovalStatus:  "APPROVED",
	}
	// Try raw insert into meter_readings with negative consumption value
	errRawReading := db.Exec("INSERT INTO meter_readings (customer_id, reading_value, previous_reading, consumption, collector_name) VALUES (?, 280.0, 300.0, -20.0, 'Test')", cust.ID).Error
	if errRawReading == nil {
		t.Errorf("expected DB constraint error on negative consumption in meter_readings, got nil")
	}

	// 3. Direct DB verification: Attempt inserting raw Invoice with negative consumption
	cycle := "2026-10-1"
	errRawInvoice := db.Exec("INSERT INTO invoices (customer_id, billing_cycle, previous_reading, current_reading, consumption, kwh_price_snapshot, fixed_fee_snapshot, total_amount, due_date) VALUES (?, ?, 300.0, 280.0, -20.0, 300.0, 1000.0, 1000.0, NOW())", cust.ID, cycle).Error
	if errRawInvoice == nil {
		t.Errorf("expected DB constraint error on negative consumption in invoices, got nil")
	}

	_ = rawReading
}

// TestMathematicalBoundaries_ExtremeOverflowHandling verifies that massive consumption
// (e.g. 999,999 kWh) computes accurately within NUMERIC(12,2) limits without overflow or panic,
// and values exceeding database capacity are caught safely without server crashes.
func TestMathematicalBoundaries_ExtremeOverflowHandling(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	cust, _ := createTestCustomerHelper(t, db, "Extreme", 100.0, 1400.0, 1000.0)
	readingService := NewReadingService()

	// 1. Extreme 999,999 kWh consumption test:
	// ReadingValue = 1,000,099.0 -> Consumption = 999,999.0 kWh
	// ConsumptionValue = 999,999.0 * 1,400.0 = 1,399,998,600.0 YER (~1.4 Billion YER)
	// TotalAmount = 1,399,998,600.0 + 1,000.0 = 1,399,999,600.0 YER
	extremeReading := 1000099.0
	res, err := readingService.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   extremeReading,
		BillingCycle:   "2026-10-1",
		ApprovalStatus: "APPROVED",
	})
	if err != nil {
		t.Fatalf("CreateReading failed on 999,999 kWh extreme input: %v", err)
	}

	expectedConsumption := 999999.0
	expectedValue := 999999.0 * 1400.0
	expectedTotal := expectedValue + 1000.0

	inv := res.Invoice
	if inv.Consumption != expectedConsumption {
		t.Errorf("expected Consumption=%.2f, got %.2f", expectedConsumption, inv.Consumption)
	}
	if inv.ConsumptionValue != expectedValue {
		t.Errorf("expected ConsumptionValue=%.2f, got %.2f", expectedValue, inv.ConsumptionValue)
	}
	if inv.TotalAmount != expectedTotal {
		t.Errorf("expected TotalAmount=%.2f, got %.2f", expectedTotal, inv.TotalAmount)
	}

	// Verify the invoice stored in PostgreSQL accurately holds the ~1.4 Billion YER value without precision loss
	var reloadedInv models.Invoice
	if err := db.First(&reloadedInv, inv.ID).Error; err != nil {
		t.Fatalf("failed to reload extreme invoice: %v", err)
	}
	if reloadedInv.TotalAmount != expectedTotal {
		t.Errorf("reloaded invoice total mismatch: expected %.2f, got %.2f", expectedTotal, reloadedInv.TotalAmount)
	}

	// 2. Beyond NUMERIC(12,2) overflow ceiling test:
	// NUMERIC(12,2) max value is 9,999,999,999.99 (under 10 Billion).
	// Attempting to insert 999,999,999,999.00 directly should trigger a PostgreSQL numeric field overflow error
	// and must be handled cleanly without unhandled panic.
	cycle := "2026-10-2"
	errOverflow := db.Exec("INSERT INTO invoices (customer_id, billing_cycle, previous_reading, current_reading, consumption, kwh_price_snapshot, fixed_fee_snapshot, total_amount, due_date) VALUES (?, ?, 0, 0, 0, 300, 1000, 999999999999.00, NOW())", cust.ID, cycle).Error
	if errOverflow == nil {
		t.Errorf("expected numeric field overflow error from PostgreSQL for value > NUMERIC(12,2), but insert succeeded")
	} else {
		errStr := strings.ToLower(errOverflow.Error())
		if !strings.Contains(errStr, "overflow") && !strings.Contains(errStr, "22003") {
			t.Logf("caught expected DB boundary error: %v", errOverflow)
		}
	}
}
