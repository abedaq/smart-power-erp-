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

// TestFIFOEnforcementOnDirectPayment: يثبت أولوية سداد الفاتورة القديمة أولاً وفصل التخصيصات
func TestFIFOEnforcementOnDirectPayment(t *testing.T) {
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
		FullName:           "مشترك فحص أسبقية السداد FIFO",
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

	// 1. التحقق من إنشاء تخصيصين منفصلين (PaymentAllocations) بشفافية كاملة
	var allocs []models.PaymentAllocation
	_ = tx.Where("payment_id = ?", paymentRes.Payment.ID).Order("id asc").Find(&allocs)

	if len(allocs) != 2 {
		t.Fatalf("expected exactly 2 payment allocations, got %d", len(allocs))
	}
	// التخصيص الأول: 15,000 ريال للفاتورة القديمة
	if allocs[0].InvoiceID != inv1.ID || allocs[0].AmountAllocated != 15000.0 {
		t.Errorf("Alloc 1 expected Inv1 with 15000, got Inv %d with %.2f", allocs[0].InvoiceID, allocs[0].AmountAllocated)
	}
	// التخصيص الثاني: 5,000 ريال للفاتورة المستهدفة
	if allocs[1].InvoiceID != inv2.ID || allocs[1].AmountAllocated != 5000.0 {
		t.Errorf("Alloc 2 expected Inv2 with 5000, got Inv %d with %.2f", allocs[1].InvoiceID, allocs[1].AmountAllocated)
	}

	// 2. التحقق من سداد الفاتورة القديمة بالكامل
	var reloadedInv1 models.Invoice
	_ = tx.First(&reloadedInv1, inv1.ID)
	if reloadedInv1.RemainingAmount != 0.0 || reloadedInv1.Status != "Paid" {
		t.Errorf("Inv1 should be Paid with 0 remaining, got Status=%s, Remaining=%.2f", reloadedInv1.Status, reloadedInv1.RemainingAmount)
	}

	// 3. التحقق من التتالي الزمني على الفاتورة الحديثة
	var reloadedInv2 models.Invoice
	_ = tx.First(&reloadedInv2, inv2.ID)
	// المتأخرات انخفضت إلى 0 (لسداد inv1)
	if reloadedInv2.Arrears != 0.0 {
		t.Errorf("Inv2 arrears should cascade to 0, got %.2f", reloadedInv2.Arrears)
	}
	// إجمالي المستحق أصبح 5,000 فقط
	if reloadedInv2.TotalDue != 5000.0 {
		t.Errorf("Inv2 TotalDue should be 5000, got %.2f", reloadedInv2.TotalDue)
	}
	// سُدد منها 5,000 والمتبقي 0 والحالة Paid
	if reloadedInv2.RemainingAmount != 0.0 || reloadedInv2.Status != "Paid" {
		t.Errorf("Inv2 should be Paid with 0 remaining, got Status=%s, Remaining=%.2f", reloadedInv2.Status, reloadedInv2.RemainingAmount)
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

