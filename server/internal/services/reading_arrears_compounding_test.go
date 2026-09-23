package services

import (
	"math"
	"testing"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"
)

// TestNoArrearsDoubleCounting: يثبت أن توالي 3 دورات غير مسددة لا يضاعف الديون بشكل تراكمي مضاعف
func TestNoArrearsDoubleCounting(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	readSvc := &ReadingService{db: tx}

	plan := models.SubscriptionPlan{
		PlanName: "سكني تجريبي",
		KwhPrice: 1000.0,
		FixedFee: 500.0,
		IsActive: true,
	}
	_ = tx.Create(&plan)

	cust := models.Customer{
		SubscriberNumber:   "SUB-ARR-TEST-1",
		FullName:           "مشترك اختبار المتأخرات",
		Status:             "Active",
		InitialReading:     100.0,
		SubscriptionPlanID: &plan.ID,
	}
	_ = tx.Create(&cust)

	// الدورة 1: استهلاك 10 كيلو (10 * 1000 + 500 = 10,500 ريال)
	res1, err := readSvc.CreateReading(CreateReadingRequest{
		CustomerID:   cust.ID,
		ReadingValue: 110.0,
		BillingCycle: "أكتوبر 1",
	})
	if err != nil {
		t.Fatalf("Cycle 1 failed: %v", err)
	}
	if res1.Invoice.TotalDue != 10500.0 || res1.Invoice.Arrears != 0.0 {
		t.Fatalf("Cycle 1 expected TotalDue=10500, Arrears=0, got TotalDue=%.2f, Arrears=%.2f", res1.Invoice.TotalDue, res1.Invoice.Arrears)
	}

	// الدورة 2: استهلاك 10 كيلو (10 * 1000 + 500 = 10,500 + متأخرات 10,500 = 21,000 ريال)
	res2, err := readSvc.CreateReading(CreateReadingRequest{
		CustomerID:   cust.ID,
		ReadingValue: 120.0,
		BillingCycle: "أكتوبر 2",
	})
	if err != nil {
		t.Fatalf("Cycle 2 failed: %v", err)
	}
	if res2.Invoice.Arrears != 10500.0 || res2.Invoice.TotalDue != 21000.0 {
		t.Fatalf("Cycle 2 expected Arrears=10500, TotalDue=21000, got Arrears=%.2f, TotalDue=%.2f", res2.Invoice.Arrears, res2.Invoice.TotalDue)
	}

	// الدورة 3: استهلاك 10 كيلو (10 * 1000 + 500 = 10,500)
	// يجب أن تكون المتأخرات = 21,000 فقط، والإجمالي = 31,500 ريال
	// الخلل القديم كان يجمع (10,500 + 21,000 = 31,500 كمتأخرات، فيصبح الإجمالي 42,000!)
	res3, err := readSvc.CreateReading(CreateReadingRequest{
		CustomerID:   cust.ID,
		ReadingValue: 130.0,
		BillingCycle: "نوفمبر 1",
	})
	if err != nil {
		t.Fatalf("Cycle 3 failed: %v", err)
	}

	if res3.Invoice.Arrears != 21000.0 {
		t.Errorf("CRITICAL DOUBLE COUNTING BUG DETECTED! Expected Arrears=21000.0, got %.2f", res3.Invoice.Arrears)
	}
	expectedTotalDue := 31500.0
	if math.Abs(res3.Invoice.TotalDue-expectedTotalDue) > 0.01 {
		t.Errorf("Expected TotalDue=%.2f, got %.2f", expectedTotalDue, res3.Invoice.TotalDue)
	}
}

// TestPaymentAllocationWaterfallToSubsequentInvoices: يثبت أنه لو سدد العميل على فاتورة قديمة بالخطأ، المبلغ يسدد الفواتير اللاحقة
func TestPaymentAllocationWaterfallToSubsequentInvoices(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	paySvc := &PaymentService{db: tx}

	cust := models.Customer{
		SubscriberNumber: "SUB-FIFO-TEST-1",
		FullName:         "مشترك اختبار التحصيل المتتالي",
		Status:           "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أكتوبر 1"
	c2 := "أكتوبر 2"

	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     1000.0,
		TotalDue:        1000.0,
		PaidAmount:      1000.0,
		RemainingAmount: 0.0,
		Status:          "Paid",
	}
	_ = tx.Create(&inv1)

	inv2 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c2,
		TotalAmount:     2000.0,
		TotalDue:        2000.0,
		PaidAmount:      0.0,
		RemainingAmount: 2000.0,
		Status:          "Unpaid",
	}
	_ = tx.Create(&inv2)

	// دفع 2000 ريال مع الإشارة إلى الفاتورة 1 المسددة مسبقاً
	res, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv1.ID,
		AmountPaid: 2000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	if res == nil {
		t.Fatalf("Expected non-nil result")
	}

	var reloadedInv2 models.Invoice
	_ = tx.First(&reloadedInv2, inv2.ID)

	if reloadedInv2.RemainingAmount != 0.0 || reloadedInv2.Status != "Paid" {
		t.Errorf("Payment should have flowed to inv2! Expected Remaining=0, Status=Paid, got Remaining=%.2f, Status=%s",
			reloadedInv2.RemainingAmount, reloadedInv2.Status)
	}

	var reloadedInv1 models.Invoice
	_ = tx.First(&reloadedInv1, inv1.ID)
	if reloadedInv1.RemainingAmount < 0.0 {
		t.Errorf("Inv1 should not have been overpaid with negative balance when inv2 was unpaid! Got Remaining=%.2f",
			reloadedInv1.RemainingAmount)
	}
}
