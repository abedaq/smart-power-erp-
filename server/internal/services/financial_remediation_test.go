package services

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"
)

// TestDoubleFixedFeePrevention: يثبت أن تسجيل أو تعديل القراءة لدورة قائمة لا يضاعف الرسوم الثابتة
func TestDoubleFixedFeePrevention(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	// 1. إنشاء خطة اشتراك ومشترك تجريبي
	plan := models.SubscriptionPlan{
		PlanName: "خطة تجريبية",
		KwhPrice: 300.0,
		FixedFee: 1000.0,
	}
	if err := tx.Create(&plan).Error; err != nil {
		t.Fatalf("failed to create plan: %v", err)
	}

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	meterNo := fmt.Sprintf("MTR_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &meterNo,
		FullName:           "مشترك فحص مضاعفة الرسوم",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     100.0,
		Status:             "Active",
	}
	if err := tx.Create(&cust).Error; err != nil {
		t.Fatalf("failed to create customer: %v", err)
	}

	cycle := "أغسطس 2"
	// 2. محاكاة وجود فاتورة تأسيسية مسبقة بالرسوم الثابتة فقط (1000 ريال) للدورة الحالية
	invNumber := fmt.Sprintf("INV-%s-%s", strings.ReplaceAll(cycle, " ", "-"), cust.SubscriberNumber)
	dueDate := now.AddDate(0, 0, 10)
	existingInv := models.Invoice{
		CustomerID:       &cust.ID,
		InvoiceNumber:    &invNumber,
		BillingCycle:     &cycle,
		DueDate:          dueDate,
		PreviousReading:  100.0,
		CurrentReading:   100.0,
		Consumption:      0.0,
		ConsumptionValue: 0.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 300.0,
		Arrears:          0.0,
		TotalAmount:      1000.0,
		TotalDue:         1000.0,
		PaidAmount:       0.0,
		RemainingAmount:  1000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
		CreatedAt:        &now,
	}
	if err := tx.Create(&existingInv).Error; err != nil {
		t.Fatalf("failed to create existing invoice: %v", err)
	}

	// 3. تسجيل قراءة فعلية للدورة الحالية (استهلاك 50 كيلو وات: 150 - 100)
	readingSvc := &ReadingService{db: tx}
	req := CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   150.0,
		BillingCycle:   cycle,
		ApprovalStatus: "APPROVED",
	}

	res, err := readingSvc.CreateReading(req)
	if err != nil {
		t.Fatalf("CreateReading failed: %v", err)
	}

	// 4. التحقق المحاسبي الصارم:
	// قيمة الاستهلاك = 50 * 300 = 15,000 ريال
	// الرسوم الثابتة = 1,000 ريال
	// totalAmount = 16,000 ريال
	// المتأخرات يجب أن تكون 0 ريال (وليس 1000 ريال من الفاتورة القائمة)
	// totalDue يجب أن يكون 16,000 ريال (وليس 17,000 ريال)
	if res.Invoice.Arrears != 0.0 {
		t.Errorf("Double Fixed Fee detected! Arrears expected 0.0, got %.2f", res.Invoice.Arrears)
	}
	if res.Invoice.TotalAmount != 16000.0 {
		t.Errorf("TotalAmount expected 16000.0, got %.2f", res.Invoice.TotalAmount)
	}
	if res.Invoice.TotalDue != 16000.0 {
		t.Errorf("TotalDue expected 16000.0, got %.2f", res.Invoice.TotalDue)
	}
	if res.Invoice.RemainingAmount != 16000.0 {
		t.Errorf("RemainingAmount expected 16000.0, got %.2f", res.Invoice.RemainingAmount)
	}
}

// TestDownstreamCascadePaidStatus: يثبت أن الفاتورة المغطاة برصيد دائن تصبح Paid حتى مع PaidAmount == 0
func TestDownstreamCascadePaidStatus(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 300.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص حالة الكاسكيد",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "2026-07-2"
	c2 := "2026-08-1"

	// فاتورة 1: فائض دائن سالب (-3000 ريال)
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     2000.0,
		Arrears:         0.0,
		TotalDue:        2000.0,
		PaidAmount:      5000.0,
		RemainingAmount: -3000.0,
		Status:          "Paid",
		ApprovalStatus:  "APPROVED",
		CurrentReading:  50.0,
	}
	_ = tx.Create(&inv1)

	// فاتورة 2: دورة لاحقة بإجمالي 2000 ريال، تغطيها متأخرات سالبة (-3000)
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  50.0,
		CurrentReading:   50.0,
		Consumption:      0.0,
		ConsumptionValue: 0.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 300.0,
		Arrears:          -3000.0,
		TotalAmount:      1000.0,
		TotalDue:         -2000.0,
		PaidAmount:       0.0, // لم يُسدد أي نقد في هذه الفاتورة
		RemainingAmount:  -2000.0,
		Status:           "Unpaid", // تبدأ كـ Unpaid لاختبار التصحيح
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// سداد إضافي على الفاتورة 1 لتفعيل الـ cascade
	paySvc := &PaymentService{db: tx}
	req := CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv1.ID,
		AmountPaid: 500.0,
	}
	_, err = paySvc.CreatePayment(req)
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// إعادة قراءة الفاتورة 2 بعد التتالي
	var reloadedInv2 models.Invoice
	_ = tx.First(&reloadedInv2, inv2.ID)

	if reloadedInv2.RemainingAmount > 0 {
		t.Fatalf("expected negative or zero remaining, got %.2f", reloadedInv2.RemainingAmount)
	}
	if reloadedInv2.Status != "Paid" {
		t.Errorf("Downstream cascade status bug! Expected 'Paid' on negative remaining with 0 paid amount, got '%s'", reloadedInv2.Status)
	}
}

// TestArabicCycleArrearsOrdering: يثبت أن مقارنة الدورات تعتمد على الترتيب الزمني وليس الأبجدي
func TestArabicCycleArrearsOrdering(t *testing.T) {
	// 1. اختبار مؤشر الترتيب الزمني الفعلي
	idxAug1 := GetCycleSortIndex("أغسطس 1")
	idxAug2 := GetCycleSortIndex("أغسطس 2")
	idxSep1 := GetCycleSortIndex("سبتمبر 1")
	idxOct1 := GetCycleSortIndex("أكتوبر 1")

	if idxAug1 >= idxAug2 {
		t.Fatalf("expected أغسطس 1 (%d) < أغسطس 2 (%d)", idxAug1, idxAug2)
	}
	if idxAug2 >= idxSep1 {
		t.Fatalf("expected أغسطس 2 (%d) < سبتمبر 1 (%d)", idxAug2, idxSep1)
	}
	if idxSep1 >= idxOct1 {
		t.Fatalf("expected سبتمبر 1 (%d) < أكتوبر 1 (%d)", idxSep1, idxOct1)
	}

	t.Logf("Cycles indexed correctly: Aug1=%d, Aug2=%d, Sep1=%d, Oct1=%d", idxAug1, idxAug2, idxSep1, idxOct1)
}

// TestCreditRollForwardNoCompounding: يثبت تصفير الفاتورة السابقة المستوعبة ومنع تضخم الرصيد الدائن
func TestCreditRollForwardNoCompounding(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 300.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص عدم تضاعف الفائض",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "2026-07-1"
	c2 := "2026-07-2"
	c3 := "2026-08-1"

	// 1. دورة 1: المشترك دفع زيادة وله رصيد سالب (-5,000 ريال)
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     1000.0,
		TotalDue:        1000.0,
		PaidAmount:      6000.0,
		RemainingAmount: -5000.0,
		Status:          "Paid",
		ApprovalStatus:  "APPROVED",
		CurrentReading:  0.0,
	}
	_ = tx.Create(&inv1)

	// 2. دورة 2: استهلاك 1,000 ريال، تستوعب الـ -5,000 ريال
	readingSvc := &ReadingService{db: tx}
	res2, err := readingSvc.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   0.0, // لا استهلاك، فقط رسوم ثابتة 1000
		BillingCycle:   c2,
		ApprovalStatus: "APPROVED",
	})
	if err != nil {
		t.Fatalf("CreateReading C2 failed: %v", err)
	}

	// إجمالي دورة 2 = 1,000 + (-5,000 متأخرات) = -4,000 ريال
	if res2.Invoice.TotalDue != -4000.0 {
		t.Fatalf("expected C2 TotalDue -4000, got %.2f", res2.Invoice.TotalDue)
	}

	// التحقق من تصفير رصيد دورة 1
	var reloadedInv1 models.Invoice
	_ = tx.First(&reloadedInv1, inv1.ID)
	if reloadedInv1.RemainingAmount != 0.0 {
		t.Errorf("Credit roll forward failed: Inv1 remaining should be 0.00, got %.2f", reloadedInv1.RemainingAmount)
	}
	if reloadedInv1.Status != "Paid" {
		t.Errorf("Inv1 status should be Paid, got %s", reloadedInv1.Status)
	}

	// 3. دورة 3: قراءة جديدة باستهلاك (قراءة 10، سعر 300 = 3000 + 1000 رسوم = 4000)
	res3, err := readingSvc.CreateReading(CreateReadingRequest{
		CustomerID:     cust.ID,
		ReadingValue:   10.0,
		BillingCycle:   c3,
		ApprovalStatus: "APPROVED",
	})
	if err != nil {
		t.Fatalf("CreateReading C3 failed: %v", err)
	}

	// المتأخرات في دورة 3 يجب أن تكون حصراً -4,000 ريال (رصيد دورة 2 فقط، وليس -5000 + -4000 = -9000!)
	if res3.Invoice.Arrears != -4000.0 {
		t.Errorf("Compounding credit bug detected! C3 Arrears expected -4000, got %.2f", res3.Invoice.Arrears)
	}
	// TotalAmount = 10*300 + 1000 = 4000. TotalDue = 4000 + (-4000) = 0.
	if res3.Invoice.TotalDue != 0.0 {
		t.Errorf("C3 TotalDue expected 0.0, got %.2f", res3.Invoice.TotalDue)
	}
	if res3.Invoice.Status != "Paid" {
		t.Errorf("C3 with 0 TotalDue should be Paid, got %s", res3.Invoice.Status)
	}
}

// TestCumulativePaymentAndArrearsSettlement: يثبت أن السداد التراكمي يسجل كامل المبلغ على الفاتورة الحالية ويغلق الفواتير السابقة آلياً (R1, R2, R3)
func TestCumulativePaymentAndArrearsSettlement(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 300.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص السداد التراكمي وتصفية الفواتير",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "2026-07-1"
	c2 := "2026-07-2"

	// فاتورة قديمة 1: متبقي عليها 15,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     15000.0,
		TotalDue:        15000.0,
		PaidAmount:      0.0,
		RemainingAmount: 15000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
		CurrentReading:  50.0,
	}
	_ = tx.Create(&inv1)

	// فاتورة حديثة 2: إجمالي الدورة 5,000 + متأخرات 15,000 = إجمالي المستحق 20,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  50.0,
		CurrentReading:   60.0,
		Consumption:      10.0,
		ConsumptionValue: 3000.0,
		FixedFeeSnapshot: 2000.0,
		KwhPriceSnapshot: 300.0,
		TotalAmount:      5000.0,
		Arrears:          15000.0,
		TotalDue:         20000.0,
		PaidAmount:       0.0,
		RemainingAmount:  20000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// دفع 20,000 ريال موجهاً للفاتورة 2 الحديثة مباشرة
	paySvc := &PaymentService{db: tx}
	req := CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 20000.0,
	}

	paymentRes, err := paySvc.CreatePayment(req)
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// 1. التحقق من تسجيل كامل المبلغ على سند القبض وتخصيصه للفاتورة الحالية
	if paymentRes.Payment.AmountPaid != 20000.0 {
		t.Errorf("Expected payment amount 20000, got %.2f", paymentRes.Payment.AmountPaid)
	}
	var allocs []models.PaymentAllocation
	_ = tx.Where("payment_id = ?", paymentRes.Payment.ID).Find(&allocs)
	totalAlloc := 0.0
	for _, a := range allocs {
		totalAlloc += a.AmountAllocated
	}
	if totalAlloc != 20000.0 || len(allocs) == 0 {
		t.Errorf("Expected allocations totaling 20000 across Inv1 and Inv2, got %+v", allocs)
	}

	// 2. التحقق من تصفير الفاتورة الحالية وأن المتبقي 0 ريال والحالة Paid
	var reloadedInv2 models.Invoice
	_ = tx.First(&reloadedInv2, inv2.ID)
	if reloadedInv2.RemainingAmount != 0.0 || reloadedInv2.Status != "Paid" {
		t.Errorf("Inv2 should be Paid with 0 remaining, got Status=%s, Remaining=%.2f", reloadedInv2.Status, reloadedInv2.RemainingAmount)
	}

	// 3. التحقق من إغلاق الفاتورة القديمة آلياً وتصفير متبقيها وحالتها Paid
	var reloadedInv1 models.Invoice
	_ = tx.First(&reloadedInv1, inv1.ID)
	if reloadedInv1.RemainingAmount != 0.0 || reloadedInv1.Status != "Paid" {
		t.Errorf("Inv1 should be Paid with 0 remaining, got Status=%s, Remaining=%.2f", reloadedInv1.Status, reloadedInv1.RemainingAmount)
	}

	// 4. التحقق من مزامنة رصيد المشترك ليصبح 0 ريال بالضبط
	var reloadedCust models.Customer
	_ = tx.First(&reloadedCust, cust.ID)
	if reloadedCust.TotalDue != 0.0 {
		t.Errorf("Customer TotalDue expected 0.0, got %.2f", reloadedCust.TotalDue)
	}
}

// TestCumulative21000PaymentAndSettlement: يثبت سداد 21,000 ريال (14,000 دورة حالية + 7,000 متأخرات سابقة) بدقة تامة
func TestCumulative21000PaymentAndSettlement(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص 21000",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة: 7,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     7000.0,
		TotalDue:        7000.0,
		PaidAmount:      0.0,
		RemainingAmount: 7000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية: استهلاك 13,000 + اشتراك 1,000 = 14,000 + متأخرات 7,000 = إجمالي 21,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   23.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          7000.0,
		TotalDue:         21000.0,
		PaidAmount:       0.0,
		RemainingAmount:  21000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// دفع 21,000 ريال
	paySvc := &PaymentService{db: tx}
	res, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 21000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// تحقق من الفاتورة الحالية
	var curInv models.Invoice
	_ = tx.First(&curInv, inv2.ID)
	if curInv.RemainingAmount != 0.0 || curInv.Status != "Paid" {
		t.Fatalf("Inv2 expected Paid with Remaining=0, got Paid=%.2f, Rem=%.2f, Status=%s",
			curInv.PaidAmount, curInv.RemainingAmount, curInv.Status)
	}

	// تحقق من الفاتورة السابقة
	var prevInv models.Invoice
	_ = tx.First(&prevInv, inv1.ID)
	if prevInv.RemainingAmount != 0.0 || prevInv.Status != "Paid" {
		t.Fatalf("Inv1 expected Paid with Remaining=0, got Rem=%.2f, Status=%s",
			prevInv.RemainingAmount, prevInv.Status)
	}

	// تحقق من سند القبض
	renderSvc := NewInvoiceRenderService(cfg)
	renderSvc.db = tx
	settings := models.SystemSettings{StationName: "محطة الضياء", DefaultKwhPrice: 1000, DefaultFixedFee: 1000}
	html := renderSvc.generateReceiptHTML(&res.Payment, &curInv, &settings, 0)
	if !strings.Contains(html, "0 ر.ي (خالص)") {
		t.Errorf("Receipt HTML must show 0 YER خالص, got: %s", html)
	}
	if strings.Contains(html, "+7,000") || strings.Contains(html, "+1,000") {
		t.Errorf("Receipt HTML must not contain phantom 7000 or 1000 balance")
	}
}

// TestAccountClearanceNoPhantom1000: يثبت تصفية 14,000 ريال وعدم ظهور متبقي 1,000 ريال حتى بوجود دورة مستقبلية فارغة
func TestAccountClearanceNoPhantom1000(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك تصفية 14000",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 2"
	c2 := "سبتمبر 1"

	// دورة حالية: استهلاك 13,000 + اشتراك 1,000 = 14,000
	inv1 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c1,
		PreviousReading:  0.0,
		CurrentReading:   13.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          0.0,
		TotalDue:         14000.0,
		PaidAmount:       0.0,
		RemainingAmount:  14000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv1)

	// دورة مستقبلية فارغة وغير معتمدة مع رسم اشتراك 1000
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  13.0,
		CurrentReading:   13.0,
		Consumption:      0.0,
		ConsumptionValue: 0.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      1000.0,
		Arrears:          14000.0,
		TotalDue:         15000.0,
		PaidAmount:       0.0,
		RemainingAmount:  15000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "PENDING",
	}
	_ = tx.Create(&inv2)

	// سداد 14,000 وتصفية حساب المشترك
	paySvc := &PaymentService{db: tx}
	res, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv1.ID,
		AmountPaid: 14000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// 1. الفاتورة الحالية مسددة بالكامل
	var reloadedInv1 models.Invoice
	_ = tx.First(&reloadedInv1, inv1.ID)
	if reloadedInv1.PaidAmount != 14000.0 || reloadedInv1.RemainingAmount != 0.0 || reloadedInv1.Status != "Paid" {
		t.Fatalf("Inv1 must be Paid with Remaining 0, got Paid=%.2f, Rem=%.2f, Status=%s",
			reloadedInv1.PaidAmount, reloadedInv1.RemainingAmount, reloadedInv1.Status)
	}

	// 2. رصيد المشترك الإجمالي بعد التصفية = 0 ريال تماماً (لا يظهر 1000 ريال)
	var reloadedCust models.Customer
	_ = tx.First(&reloadedCust, cust.ID)
	if reloadedCust.TotalDue != 0.0 {
		t.Fatalf("Customer TotalDue must be 0.0, got %.2f", reloadedCust.TotalDue)
	}

	// 3. سند القبض يعكس الرصيد المتبقي بدقة 0 ريال (خالص)
	renderSvc := NewInvoiceRenderService(cfg)
	renderSvc.db = tx
	settings := models.SystemSettings{StationName: "محطة الضياء", DefaultKwhPrice: 1000, DefaultFixedFee: 1000}
	html := renderSvc.generateReceiptHTML(&res.Payment, &reloadedInv1, &settings, 0)
	if !strings.Contains(html, "0 ر.ي (خالص)") {
		t.Errorf("Receipt HTML must show 0 YER خالص, got: %s", html)
	}
	if strings.Contains(html, "+1,000") {
		t.Errorf("Receipt HTML must not contain phantom 1,000 YER remaining")
	}
}

// TestReversePayment: يثبت أن إلغاء السند يعيد أرصدة الفواتير والمتأخرات كما كانت قبل السداد بدقة تامة
func TestReversePayment(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{
		PlanName: "خطة فحص الإلغاء",
		KwhPrice: 1000.0,
		FixedFee: 1000.0,
	}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("REV_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		FullName:           "مشترك فحص إلغاء السند",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	cycle1 := "أغسطس 1"
	inv1 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &cycle1,
		DueDate:          now.AddDate(0, 0, 10),
		Consumption:      10.0,
		ConsumptionValue: 10000.0,
		FixedFeeSnapshot: 1000.0,
		TotalAmount:      11000.0,
		TotalDue:         11000.0,
		PaidAmount:       0.0,
		RemainingAmount:  11000.0,
		Status:           "Unpaid",
	}
	_ = tx.Create(&inv1)

	paySvc := &PaymentService{db: tx}

	// 1. سداد الفاتورة بـ 11,000 ريال
	payReq := CreatePaymentRequest{
		CustomerID:    cust.ID,
		InvoiceID:     &inv1.ID,
		AmountPaid:    11000.0,
		PaymentMethod: "CASH",
	}
	payRes, err := paySvc.CreatePayment(payReq)
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التحقق من السداد
	var paidInv models.Invoice
	_ = tx.First(&paidInv, inv1.ID)
	if paidInv.RemainingAmount != 0 || paidInv.Status != "Paid" {
		t.Fatalf("Invoice should be Paid with 0 remaining, got Status=%s, Remaining=%.2f", paidInv.Status, paidInv.RemainingAmount)
	}

	// 2. تنفيذ عملية إلغاء السند (Reverse Payment)
	auditCtx := models.AuditContext{
		FullName: "مدير النظام",
		Role:     "ADMIN",
	}
	err = paySvc.ReversePayment(payRes.Payment.ID, "سداد بالخطأ", auditCtx)
	if err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	// 3. التحقق من عودة الفاتورة لحالتها غير المسددة مع كامل المبلغ المتبقي (11,000 ريال)
	var reversedInv models.Invoice
	_ = tx.First(&reversedInv, inv1.ID)
	if reversedInv.PaidAmount != 0.0 || reversedInv.RemainingAmount != 11000.0 || reversedInv.Status != "Unpaid" {
		t.Errorf("Reversed invoice should be Unpaid with 11000 remaining, got Status=%s, Paid=%.2f, Remaining=%.2f",
			reversedInv.Status, reversedInv.PaidAmount, reversedInv.RemainingAmount)
	}

	// 4. التحقق من تغيير حالة السند إلى REVERSED
	var reversedPayment models.Payment
	_ = tx.First(&reversedPayment, payRes.Payment.ID)
	if reversedPayment.ApprovalStatus != "REVERSED" {
		t.Errorf("Payment should have approval_status REVERSED, got %s", reversedPayment.ApprovalStatus)
	}

	// 5. التحقق من منع إلغاء السند الملغي مرة أخرى
	errTwice := paySvc.ReversePayment(payRes.Payment.ID, "محاولة ثانية", auditCtx)
	if errTwice == nil {
		t.Errorf("Expected error when reversing an already reversed payment, got nil")
	}
}

// TestZeroArrearsPaymentMustNotWipePriorDebt: يثبت أن سداد فاتورة بدون متأخرات (Arrears = 0) لا يغلق أو يصفر ديون الفواتير السابقة
func TestZeroArrearsPaymentMustNotWipePriorDebt(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص تصفير الديون غير المدمجة",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة غير مسددة بمبلغ 8000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     8000.0,
		TotalDue:        8000.0,
		PaidAmount:      0.0,
		RemainingAmount: 8000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية ليس بها متأخرات (Arrears = 0) بمبلغ 2000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   12.0,
		Consumption:      2.0,
		ConsumptionValue: 2000.0,
		FixedFeeSnapshot: 0.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      2000.0,
		Arrears:          0.0,
		TotalDue:         2000.0,
		PaidAmount:       0.0,
		RemainingAmount:  2000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// دفع 2000 ريال لسداد الفاتورة الحالية فقط
	paySvc := &PaymentService{db: tx}
	_, err = paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 2000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التحقق من الفاتورة الحالية: مسددة
	var cur models.Invoice
	_ = tx.First(&cur, inv2.ID)
	if cur.RemainingAmount != 0 || cur.Status != "Paid" {
		t.Fatalf("Current invoice should be Paid, got %s, rem=%.2f", cur.Status, cur.RemainingAmount)
	}

	// الفاتورة السابقة يجب أن تبقى كما هي (8000 ريال غير مسددة) لأن متأخراتها لم تكن مدمجة
	var prev models.Invoice
	_ = tx.First(&prev, inv1.ID)
	if prev.RemainingAmount != 8000.0 || prev.Status != "Unpaid" {
		t.Errorf("FATAL BUG: Prior invoice with unmerged arrears was wiped! Expected Unpaid with Rem=8000, got Status=%s, Rem=%.2f",
			prev.Status, prev.RemainingAmount)
	}
}

// TestPartialArrearsPaymentMustNotWipeUnmergedLargeDebt: يثبت أن وجود متأخرات جزئية (1000 ريال) وسدادها لا يصفر فاتورة سابقة غير مدمجة بمبلغ كبير (50,000 ريال)
func TestPartialArrearsPaymentMustNotWipeUnmergedLargeDebt(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص عدم مسح الديون الكبيرة غير المدمجة",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة غير مسددة بمبلغ 50,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     50000.0,
		TotalDue:        50000.0,
		PaidAmount:      0.0,
		RemainingAmount: 50000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية بها متأخرات 1000 ريال فقط واستهلاك 2000 ريال (إجمالي 3000 ريال)
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   12.0,
		Consumption:      2.0,
		ConsumptionValue: 2000.0,
		FixedFeeSnapshot: 0.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      2000.0,
		Arrears:          1000.0,
		TotalDue:         3000.0,
		PaidAmount:       0.0,
		RemainingAmount:  3000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// دفع 3000 ريال لسداد الفاتورة الحالية بالكامل
	paySvc := &PaymentService{db: tx}
	_, err = paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 3000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التحقق من الفاتورة السابقة: يجب ألا تُصفر لأن قيمتها (50,000) أكبر بكثير من المتأخرات المدمجة (1,000)
	var prev models.Invoice
	_ = tx.First(&prev, inv1.ID)
	if prev.RemainingAmount != 50000.0 || prev.Status != "Unpaid" {
		t.Errorf("Unmerged large invoice must remain Unpaid with 50000 remaining, got Status=%s, Rem=%.2f",
			prev.Status, prev.RemainingAmount)
	}
}

// TestMultiStageCumulativePaymentAndSettlement: يختبر سيناريو سداد مجزأ (3000 ثم 4000 ثم 14000)
// لفاتورة 21,000 ريال (14,000 حالية + 7,000 متأخرات) وتدرج إغلاق الفواتير السابقة وتصفير الرصيد بدقة
func TestMultiStageCumulativePaymentAndSettlement(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك سداد مجزأ تراكمي",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة: 7,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     7000.0,
		TotalDue:        7000.0,
		PaidAmount:      0.0,
		RemainingAmount: 7000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية: استهلاك 13,000 + اشتراك 1,000 = 14,000 + متأخرات 7,000 = إجمالي 21,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   23.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          7000.0,
		TotalDue:         21000.0,
		PaidAmount:       0.0,
		RemainingAmount:  21000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	paySvc := &PaymentService{db: tx}
	renderSvc := NewInvoiceRenderService(cfg)
	renderSvc.db = tx
	settings := models.SystemSettings{StationName: "محطة الضياء", DefaultKwhPrice: 1000, DefaultFixedFee: 1000}

	// المرحلة 1: دفع 3,000 ريال فقط (لا تكفي لتغطية المتأخرات 7,000)
	res1, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 3000.0,
	})
	if err != nil {
		t.Fatalf("Payment 1 failed: %v", err)
	}

	var curAfterPay1 models.Invoice
	_ = tx.First(&curAfterPay1, inv2.ID)
	if curAfterPay1.PaidAmount != 3000.0 || curAfterPay1.RemainingAmount != 18000.0 || curAfterPay1.Status != "Partially_Paid" {
		t.Fatalf("Stage 1 Inv2 mismatch: Paid=%.2f, Rem=%.2f, Status=%s", curAfterPay1.PaidAmount, curAfterPay1.RemainingAmount, curAfterPay1.Status)
	}

	var prevAfterPay1 models.Invoice
	_ = tx.First(&prevAfterPay1, inv1.ID)
	if prevAfterPay1.RemainingAmount != 7000.0 || prevAfterPay1.Status != "Unpaid" {
		t.Fatalf("Stage 1 Inv1 must stay Unpaid 7000, got Status=%s, Rem=%.2f", prevAfterPay1.Status, prevAfterPay1.RemainingAmount)
	}

	html1 := renderSvc.generateReceiptHTML(&res1.Payment, &curAfterPay1, &settings, 0)
	if !strings.Contains(html1, "18,000") {
		t.Errorf("Stage 1 receipt should show 18,000 remaining, got: %s", html1)
	}

	// المرحلة 2: دفع 4,000 ريال إضافية (المجموع المدفوع أصبح 7,000 = يغطي المتأخرات بالكامل)
	res2, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 4000.0,
	})
	if err != nil {
		t.Fatalf("Payment 2 failed: %v", err)
	}

	var curAfterPay2 models.Invoice
	_ = tx.First(&curAfterPay2, inv2.ID)
	if curAfterPay2.PaidAmount != 7000.0 || curAfterPay2.RemainingAmount != 14000.0 || curAfterPay2.Status != "Partially_Paid" {
		t.Fatalf("Stage 2 Inv2 mismatch: Paid=%.2f, Rem=%.2f, Status=%s", curAfterPay2.PaidAmount, curAfterPay2.RemainingAmount, curAfterPay2.Status)
	}

	// الفاتورة السابقة يجب أن تُغلق الآن لأن المبلغ المدفوع (7,000) غطى متأخراتها بالكامل!
	var prevAfterPay2 models.Invoice
	_ = tx.First(&prevAfterPay2, inv1.ID)
	if prevAfterPay2.RemainingAmount != 0.0 || prevAfterPay2.Status != "Paid" {
		t.Fatalf("Stage 2 Inv1 must be Paid with Remaining=0, got Status=%s, Rem=%.2f", prevAfterPay2.Status, prevAfterPay2.RemainingAmount)
	}

	html2 := renderSvc.generateReceiptHTML(&res2.Payment, &curAfterPay2, &settings, 0)
	if !strings.Contains(html2, "14,000") {
		t.Errorf("Stage 2 receipt should show 14,000 remaining, got: %s", html2)
	}

	// المرحلة 3: دفع 14,000 ريال المتبقية لسداد الحساب كاملاً (المجموع المدفوع 21,000)
	res3, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 14000.0,
	})
	if err != nil {
		t.Fatalf("Payment 3 failed: %v", err)
	}

	var curAfterPay3 models.Invoice
	_ = tx.First(&curAfterPay3, inv2.ID)
	if curAfterPay3.PaidAmount != 21000.0 || curAfterPay3.RemainingAmount != 0.0 || curAfterPay3.Status != "Paid" {
		t.Fatalf("Stage 3 Inv2 mismatch: Paid=%.2f, Rem=%.2f, Status=%s", curAfterPay3.PaidAmount, curAfterPay3.RemainingAmount, curAfterPay3.Status)
	}

	var custAfterPay3 models.Customer
	_ = tx.First(&custAfterPay3, cust.ID)
	if custAfterPay3.TotalDue != 0.0 {
		t.Fatalf("Stage 3 Customer TotalDue must be 0.0, got %.2f", custAfterPay3.TotalDue)
	}

	html3 := renderSvc.generateReceiptHTML(&res3.Payment, &curAfterPay3, &settings, 0)
	if !strings.Contains(html3, "0 ر.ي (خالص)") {
		t.Errorf("Stage 3 receipt should show 0 YER خالص, got: %s", html3)
	}
}

// TestResyncCustomerInvoicesChainAfterCumulativePayment: يختبر سلامة الفواتير بعد تشغيل ResyncCustomerInvoicesChain
// عند سداد فاتورة تراكمية، لمنع تصفير المتأخرات وظهور رصيد سالب مشوه
func TestResyncCustomerInvoicesChainAfterCumulativePayment(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص إعادة المزامنة بعد السداد",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة: 7,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     7000.0,
		TotalDue:        7000.0,
		PaidAmount:      0.0,
		RemainingAmount: 7000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية: 14,000 + متأخرات 7,000 = 21,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   23.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          7000.0,
		TotalDue:         21000.0,
		PaidAmount:       0.0,
		RemainingAmount:  21000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// دفع 21,000 ريال على الفاتورة الحالية
	paySvc := &PaymentService{db: tx}
	_, err = paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 21000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// استدعاء إعادة مزامنة سلسلة الفواتير للمشترك (كأن يتم إدخال قراءة أو فتح دورة جديدة)
	billingSvc := &BillingService{db: tx}
	if err := billingSvc.ResyncCustomerInvoicesChain(cust.ID); err != nil {
		t.Fatalf("ResyncCustomerInvoicesChain failed: %v", err)
	}

	var curAfterResync models.Invoice
	_ = tx.First(&curAfterResync, inv2.ID)

	if curAfterResync.RemainingAmount != 0.0 {
		t.Fatalf("Cumulative invoice remaining amount should be 0 after full 21000 payment, got %.2f", curAfterResync.RemainingAmount)
	}
	if curAfterResync.Status != "Paid" {
		t.Errorf("Inv2 status expected Paid, got %s", curAfterResync.Status)
	}
}

// TestReverseCumulativePaymentReopensPriorInvoices: يثبت أن إلغاء سداد فاتورة تراكمية يعيد فتح الفواتير السابقة غير المسددة
func TestReverseCumulativePaymentReopensPriorInvoices(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص إلغاء السداد التراكمي",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة: 7,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     7000.0,
		TotalDue:        7000.0,
		PaidAmount:      0.0,
		RemainingAmount: 7000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية: 14,000 + متأخرات 7,000 = 21,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   23.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          7000.0,
		TotalDue:         21000.0,
		PaidAmount:       0.0,
		RemainingAmount:  21000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// 1. دفع 21,000 ريال على الفاتورة الحالية
	paySvc := &PaymentService{db: tx}
	payRes, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 21000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التحقق من أن الفاتورة السابقة أغلقت
	var inv1Paid models.Invoice
	_ = tx.First(&inv1Paid, inv1.ID)
	if inv1Paid.Status != "Paid" || inv1Paid.RemainingAmount != 0 {
		t.Fatalf("Expected inv1 to be Paid with remaining 0, got %s, rem=%.2f", inv1Paid.Status, inv1Paid.RemainingAmount)
	}

	// 2. إلغاء السند (Reverse Payment)
	auditCtx := models.AuditContext{FullName: "مدير النظام", Role: "ADMIN"}
	if err := paySvc.ReversePayment(payRes.Payment.ID, "إلغاء تجريبي لفحص إعادة الفواتير", auditCtx); err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	// 3. التحقق من عودة الفاتورة الحالية إلى Unpaid بمبلغ 21,000 ريال
	var inv2Rev models.Invoice
	_ = tx.First(&inv2Rev, inv2.ID)
	if inv2Rev.Status != "Unpaid" || inv2Rev.PaidAmount != 0 || inv2Rev.RemainingAmount != 21000.0 {
		t.Errorf("Inv2 reversal mismatch: expected Unpaid, Paid=0, Rem=21000, got Status=%s, Paid=%.2f, Rem=%.2f",
			inv2Rev.Status, inv2Rev.PaidAmount, inv2Rev.RemainingAmount)
	}

	// 4. التحقق الحاسم: عودة الفاتورة السابقة إلى Unpaid بمبلغ 7,000 ريال كاملة
	var inv1Rev models.Invoice
	_ = tx.First(&inv1Rev, inv1.ID)
	if inv1Rev.Status != "Unpaid" || inv1Rev.PaidAmount != 0 || inv1Rev.RemainingAmount != 7000.0 {
		t.Errorf("CRITICAL BUG: Prior invoice was NOT reopened on payment reversal! Expected Unpaid, Paid=0, Rem=7000, got Status=%s, Paid=%.2f, Rem=%.2f",
			inv1Rev.Status, inv1Rev.PaidAmount, inv1Rev.RemainingAmount)
	}

	// 5. التحقق من رصيد المشترك الإجمالي
	var custRev models.Customer
	_ = tx.First(&custRev, cust.ID)
	if custRev.TotalDue != 21000.0 {
		t.Errorf("Customer TotalDue after reversal expected 21000, got %.2f", custRev.TotalDue)
	}
}

// TestResyncCustomerInvoicesChainWithPartiallyPaidCumulativeInvoice: يثبت عدم تآكل المتأخرات عند إعادة مزامنة فاتورة تراكمية مدفوعة جزئياً
func TestResyncCustomerInvoicesChainWithPartiallyPaidCumulativeInvoice(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص سداد جزئي تراكمي والمزامنة",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "أغسطس 1"
	c2 := "أغسطس 2"

	// فاتورة سابقة: 7,000 ريال
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     7000.0,
		TotalDue:        7000.0,
		PaidAmount:      0.0,
		RemainingAmount: 7000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// فاتورة حالية: 14,000 + متأخرات 7,000 = 21,000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  10.0,
		CurrentReading:   23.0,
		Consumption:      13.0,
		ConsumptionValue: 13000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      14000.0,
		Arrears:          7000.0,
		TotalDue:         21000.0,
		PaidAmount:       0.0,
		RemainingAmount:  21000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	// سداد جزئي 10,000 ريال (يغطي متأخرات 7000 + 3000 من الحالية)
	paySvc := &PaymentService{db: tx}
	_, err = paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 10000.0,
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// تشغيل إعادة مزامنة السلسلة
	billingSvc := &BillingService{db: tx}
	if err := billingSvc.ResyncCustomerInvoicesChain(cust.ID); err != nil {
		t.Fatalf("ResyncCustomerInvoicesChain failed: %v", err)
	}

	var curAfterResync models.Invoice
	_ = tx.First(&curAfterResync, inv2.ID)

	if curAfterResync.PaidAmount != 10000.0 {
		t.Errorf("Inv2 PaidAmount mismatch under FIFO: expected 10000, got %.2f", curAfterResync.PaidAmount)
	}
	if curAfterResync.RemainingAmount != 11000.0 {
		t.Errorf("Inv2 RemainingAmount corrupted! Expected 11000, got %.2f", curAfterResync.RemainingAmount)
	}
	if curAfterResync.Status != "Partially_Paid" {
		t.Errorf("Inv2 Status expected Partially_Paid, got %s", curAfterResync.Status)
	}
}

// TestReverseCumulativePayment_DoesNotReopenOlderSettledInvoices: يثبت أن إلغاء سداد فاتورة تراكمية حديثة
// لا يعيد فتح فواتير سابقة أغلقت بسداد تراكمي سابق منفصل وما زال سداده قائماً
func TestReverseCumulativePayment_DoesNotReopenOlderSettledInvoices(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	plan := models.SubscriptionPlan{PlanName: "خطة تجريبية", KwhPrice: 1000.0, FixedFee: 1000.0}
	_ = tx.Create(&plan)

	now := time.Now().UTC()
	subNo := fmt.Sprintf("TST_%d", now.UnixNano()%100000)
	cust := models.Customer{
		SubscriberNumber:   subNo,
		MeterNumber:        &subNo,
		FullName:           "مشترك فحص عدم فتح فواتير سابقة مسددة",
		SubscriptionPlanID: &plan.ID,
		InitialReading:     0.0,
		Status:             "Active",
	}
	_ = tx.Create(&cust)

	c1 := "يونيو 1"
	c2 := "يونيو 2"
	c3 := "يوليو 1"
	c4 := "يوليو 2"

	// 1. دورة يونيو 1: فاتورة بـ 5000 لم تُسدد في حينها
	inv1 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c1,
		TotalAmount:     5000.0,
		TotalDue:        5000.0,
		PaidAmount:      0.0,
		RemainingAmount: 5000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv1)

	// 2. دورة يونيو 2: فاتورة تراكمية بـ 5000 + 5000 متأخرات = 10000 ريال
	inv2 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c2,
		PreviousReading:  5.0,
		CurrentReading:   10.0,
		Consumption:      5.0,
		ConsumptionValue: 4000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      5000.0,
		Arrears:          5000.0,
		TotalDue:         10000.0,
		PaidAmount:       0.0,
		RemainingAmount:  10000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv2)

	paySvc := &PaymentService{db: tx}

	// المشترك سدد فاتورة يونيو 2 بالكامل (10,000 ريال) - هذا السداد أغلق inv1 و inv2
	payRes1, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv2.ID,
		AmountPaid: 10000.0,
	})
	if err != nil {
		t.Fatalf("Payment 1 failed: %v", err)
	}
	_ = payRes1

	// التحقق من أن inv1 أغلقت بنجاح (Paid)
	var inv1Check models.Invoice
	_ = tx.First(&inv1Check, inv1.ID)
	if inv1Check.Status != "Paid" || inv1Check.RemainingAmount != 0 {
		t.Fatalf("Inv1 must be Paid, got %s, rem=%.2f", inv1Check.Status, inv1Check.RemainingAmount)
	}

	// 3. دورة يوليو 1: فاتورة جديدة بـ 6000 لم تُسدد
	inv3 := models.Invoice{
		CustomerID:      &cust.ID,
		BillingCycle:    &c3,
		TotalAmount:     6000.0,
		TotalDue:        6000.0,
		PaidAmount:      0.0,
		RemainingAmount: 6000.0,
		Status:          "Unpaid",
		ApprovalStatus:  "APPROVED",
	}
	_ = tx.Create(&inv3)

	// 4. دورة يوليو 2: فاتورة تراكمية بـ 6000 + 6000 متأخرات = 12000 ريال
	inv4 := models.Invoice{
		CustomerID:       &cust.ID,
		BillingCycle:     &c4,
		PreviousReading:  10.0,
		CurrentReading:   15.0,
		Consumption:      5.0,
		ConsumptionValue: 5000.0,
		FixedFeeSnapshot: 1000.0,
		KwhPriceSnapshot: 1000.0,
		TotalAmount:      6000.0,
		Arrears:          6000.0,
		TotalDue:         12000.0,
		PaidAmount:       0.0,
		RemainingAmount:  12000.0,
		Status:           "Unpaid",
		ApprovalStatus:   "APPROVED",
	}
	_ = tx.Create(&inv4)

	// المشترك سدد فاتورة يوليو 2 بالكامل (12,000 ريال) - هذا السداد أغلق inv3 و inv4
	payRes2, err := paySvc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID,
		InvoiceID:  &inv4.ID,
		AmountPaid: 12000.0,
	})
	if err != nil {
		t.Fatalf("Payment 2 failed: %v", err)
	}

	// التحقق من إغلاق inv3
	var inv3Check models.Invoice
	_ = tx.First(&inv3Check, inv3.ID)
	if inv3Check.Status != "Paid" || inv3Check.RemainingAmount != 0 {
		t.Fatalf("Inv3 must be Paid, got %s, rem=%.2f", inv3Check.Status, inv3Check.RemainingAmount)
	}

	// الآن: المحاسب يقوم بإلغاء سداد فاتورة يوليو 2 (payRes2) فقط!
	auditCtx := models.AuditContext{FullName: "مدير النظام", Role: "ADMIN"}
	if err := paySvc.ReversePayment(payRes2.Payment.ID, "إلغاء سداد يوليو 2 فقط", auditCtx); err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	// النتيجة المتوقعة:
	// 1. inv4 تعود Unpaid بمبلغ 12000
	// 2. inv3 تعود Unpaid بمبلغ 6000 (لأنها كانت مدمجة في متأخرات inv4)
	// 3. inv2 تبقى Paid بمبلغ 0 (سدادها قائم ولم يُلغَ)
	// 4. inv1 تبقى Paid بمبلغ 0 (لأنها سُددت بواسطة inv2 ولم تكن جزءاً من متأخرات inv4!)

	var inv4After models.Invoice
	_ = tx.First(&inv4After, inv4.ID)
	if inv4After.Status != "Unpaid" || inv4After.RemainingAmount != 12000.0 {
		t.Errorf("Inv4 should be Unpaid 12000, got %s, rem=%.2f", inv4After.Status, inv4After.RemainingAmount)
	}

	var inv3After models.Invoice
	_ = tx.First(&inv3After, inv3.ID)
	if inv3After.Status != "Unpaid" || inv3After.RemainingAmount != 6000.0 {
		t.Errorf("Inv3 should be Unpaid 6000, got %s, rem=%.2f", inv3After.Status, inv3After.RemainingAmount)
	}

	var inv2After models.Invoice
	_ = tx.First(&inv2After, inv2.ID)
	if inv2After.Status != "Paid" || inv2After.RemainingAmount != 0 {
		t.Errorf("Inv2 should remain Paid 0, got %s, rem=%.2f", inv2After.Status, inv2After.RemainingAmount)
	}

	var inv1After models.Invoice
	_ = tx.First(&inv1After, inv1.ID)
	if inv1After.Status != "Paid" || inv1After.RemainingAmount != 0 {
		t.Errorf("CRITICAL ACCOUNTING BUG: Inv1 was erroneously reopened! Expected Paid with rem=0, got Status=%s, rem=%.2f, paid=%.2f",
			inv1After.Status, inv1After.RemainingAmount, inv1After.PaidAmount)
	}
}

