package services

import (
	"fmt"
	"testing"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"
)

func setupTestDB(t *testing.T) *PaymentService {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	t.Cleanup(func() {
		tx.Rollback()
	})

	return &PaymentService{db: tx}
}

// TestReversePayment_CancelsAvailableCredit: يثبت أن إلغاء سند ولد رصيداً فائضاً يلغي الرصيد الدائن
func TestReversePayment_CancelsAvailableCredit(t *testing.T) {
	svc := setupTestDB(t)
	tx := svc.db

	plan := models.SubscriptionPlan{
		PlanName: "خطة تجريبية",
		KwhPrice: 1000,
		FixedFee: 500,
		IsActive: true,
	}
	if err := tx.Create(&plan).Error; err != nil {
		t.Fatalf("failed to create plan: %v", err)
	}

	cust := models.Customer{
		SubscriberNumber:   fmt.Sprintf("REV-CR-TEST-%d", time.Now().UnixNano()),
		FullName:           "مشترك اختبار إلغاء الرصيد",
		Status:             "Active",
		InitialReading:     0,
		SubscriptionPlanID: &plan.ID,
	}
	if err := tx.Create(&cust).Error; err != nil {
		t.Fatalf("failed to create customer: %v", err)
	}

	cycle := "2026-09"
	dueDate := time.Now().Add(7 * 24 * time.Hour)
	inv := models.Invoice{
		CustomerID:       &cust.ID,
		TotalAmount:      5000,
		TotalDue:         5000,
		PaidAmount:       0,
		RemainingAmount:  5000,
		BillingCycle:     &cycle,
		DueDate:          dueDate,
		ApprovalStatus:   "APPROVED",
		Status:           "Unpaid",
		KwhPriceSnapshot: 1000,
		FixedFeeSnapshot: 500,
	}
	if err := tx.Create(&inv).Error; err != nil {
		t.Fatalf("failed to create invoice: %v", err)
	}

	// سداد 7000 ريال (فاتورة 5000 + فائض 2000)
	payRes, err := svc.CreatePayment(CreatePaymentRequest{
		CustomerID:     cust.ID,
		AmountPaid:     7000,
		PaymentMethod:  "CASH",
		AccountantName: "محاسب تجريبي",
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التأكد من نشوء رصيد دائن
	var credit models.CustomerCredit
	if err := tx.Where("payment_id = ?", payRes.Payment.ID).First(&credit).Error; err != nil {
		t.Fatalf("expected credit to be created: %v", err)
	}
	if credit.Amount != 2000 || credit.Status != "AVAILABLE" {
		t.Fatalf("unexpected credit state: %+v", credit)
	}

	// تنفيذ إلغاء السند
	auditCtx := models.AuditContext{Username: "admin", Role: "ADMIN"}
	if err := svc.ReversePayment(payRes.Payment.ID, "سداد خاطئ ومبلغ زائد", auditCtx); err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	// فحص حالة الرصيد الدائن بعد الإلغاء
	var reloadedCredit models.CustomerCredit
	if err := tx.First(&reloadedCredit, credit.ID).Error; err != nil {
		t.Fatalf("failed to reload credit: %v", err)
	}

	if reloadedCredit.Status != "CANCELLED" {
		t.Fatalf("RED BUG: expected credit status CANCELLED, got %s (CustomerCredit leaked!)", reloadedCredit.Status)
	}
	if reloadedCredit.RemainingAmount != 0 {
		t.Fatalf("RED BUG: expected credit RemainingAmount 0, got %.2f", reloadedCredit.RemainingAmount)
	}
}

// TestReversePayment_MarksAllocationsReversed: يثبت تعليم سجلات التوزيع كملغاة
func TestReversePayment_MarksAllocationsReversed(t *testing.T) {
	svc := setupTestDB(t)
	tx := svc.db

	plan := models.SubscriptionPlan{
		PlanName: "خطة تجريبية 2",
		KwhPrice: 1000,
		FixedFee: 500,
		IsActive: true,
	}
	if err := tx.Create(&plan).Error; err != nil {
		t.Fatalf("failed to create plan: %v", err)
	}

	cust := models.Customer{
		SubscriberNumber:   fmt.Sprintf("REV-AL-TEST-%d", time.Now().UnixNano()),
		FullName:           "مشترك اختبار التوزيعات",
		Status:             "Active",
		InitialReading:     0,
		SubscriptionPlanID: &plan.ID,
	}
	if err := tx.Create(&cust).Error; err != nil {
		t.Fatalf("failed to create customer: %v", err)
	}

	cycle := "2026-09"
	dueDate := time.Now().Add(7 * 24 * time.Hour)
	inv := models.Invoice{
		CustomerID:       &cust.ID,
		TotalAmount:      4000,
		TotalDue:         4000,
		PaidAmount:       0,
		RemainingAmount:  4000,
		BillingCycle:     &cycle,
		DueDate:          dueDate,
		ApprovalStatus:   "APPROVED",
		Status:           "Unpaid",
		KwhPriceSnapshot: 1000,
		FixedFeeSnapshot: 500,
	}
	if err := tx.Create(&inv).Error; err != nil {
		t.Fatalf("failed to create invoice: %v", err)
	}

	payRes, err := svc.CreatePayment(CreatePaymentRequest{
		CustomerID:     cust.ID,
		AmountPaid:     4000,
		PaymentMethod:  "CASH",
		AccountantName: "محاسب تجريبي",
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	reason := "خطأ في التسجيل"
	auditCtx := models.AuditContext{Username: "admin", Role: "ADMIN"}
	if err := svc.ReversePayment(payRes.Payment.ID, reason, auditCtx); err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	var allocations []models.PaymentAllocation
	if err := tx.Where("payment_id = ?", payRes.Payment.ID).Find(&allocations).Error; err != nil {
		t.Fatalf("failed to fetch allocations: %v", err)
	}
	if len(allocations) == 0 {
		t.Fatalf("expected allocations, found 0")
	}

	for _, alloc := range allocations {
		if !alloc.IsReversed {
			t.Fatalf("RED BUG: expected alloc.IsReversed = true, got false (PaymentAllocation not marked reversed!)")
		}
		if alloc.ReversedAt == nil {
			t.Fatalf("RED BUG: expected alloc.ReversedAt to be set, got nil")
		}
		if alloc.ReversalReason == nil || *alloc.ReversalReason != reason {
			t.Fatalf("RED BUG: expected alloc.ReversalReason = %q, got %v", reason, alloc.ReversalReason)
		}
	}
}

// TestReversePayment_RejectsIfCreditUsed: يثبت رفض الإلغاء إذا استُهلك الرصيد الدائن
func TestReversePayment_RejectsIfCreditUsed(t *testing.T) {
	svc := setupTestDB(t)
	tx := svc.db

	plan := models.SubscriptionPlan{
		PlanName: "خطة تجريبية 3",
		KwhPrice: 1000,
		FixedFee: 500,
		IsActive: true,
	}
	if err := tx.Create(&plan).Error; err != nil {
		t.Fatalf("failed to create plan: %v", err)
	}

	cust := models.Customer{
		SubscriberNumber:   fmt.Sprintf("REV-USED-TEST-%d", time.Now().UnixNano()),
		FullName:           "مشترك رصيد مستهلك",
		Status:             "Active",
		InitialReading:     0,
		SubscriptionPlanID: &plan.ID,
	}
	if err := tx.Create(&cust).Error; err != nil {
		t.Fatalf("failed to create customer: %v", err)
	}

	cycle3 := "2026-09"
	inv := models.Invoice{
		CustomerID:       &cust.ID,
		TotalAmount:      3000,
		TotalDue:         3000,
		PaidAmount:       0,
		RemainingAmount:  3000,
		BillingCycle:     &cycle3,
		DueDate:          time.Now().Add(7 * 24 * time.Hour),
		ApprovalStatus:   "APPROVED",
		Status:           "Unpaid",
		KwhPriceSnapshot: 1000,
		FixedFeeSnapshot: 500,
	}
	if err := tx.Create(&inv).Error; err != nil {
		t.Fatalf("failed to create invoice: %v", err)
	}

	payRes, err := svc.CreatePayment(CreatePaymentRequest{
		CustomerID:     cust.ID,
		AmountPaid:     5000,
		PaymentMethod:  "CASH",
		AccountantName: "محاسب تجريبي",
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// محاكاة استهلاك جزء من الرصيد الدائن
	if err := tx.Model(&models.CustomerCredit{}).
		Where("payment_id = ?", payRes.Payment.ID).
		Updates(map[string]interface{}{
			"remaining_amount": 500, // استهلك 1500 من 2000
		}).Error; err != nil {
		t.Fatalf("failed to update credit: %v", err)
	}

	auditCtx := models.AuditContext{Username: "admin", Role: "ADMIN"}
	err = svc.ReversePayment(payRes.Payment.ID, "محاولة إلغاء بعد الاستهلاك", auditCtx)
	if err == nil {
		t.Fatalf("RED BUG: expected ReversePayment to fail because credit was partially used, but got nil!")
	}
}

// TestReversePayment_SyncsCustomerTotalDueInDB يثبت أن السداد والإلغاء يحدثان جدول customers الفعلي
func TestReversePayment_SyncsCustomerTotalDueInDB(t *testing.T) {
	svc := setupTestDB(t)
	tx := svc.db

	plan := models.SubscriptionPlan{PlanName: "خطة مزامنة", KwhPrice: 1000, FixedFee: 1000, IsActive: true}
	_ = tx.Create(&plan)

	cust := models.Customer{
		SubscriberNumber:   fmt.Sprintf("SYNC-%d", time.Now().UnixNano()),
		FullName:           "مشترك اختبار مزامنة الرصيد",
		Status:             "Active",
		SubscriptionPlanID: &plan.ID,
	}
	_ = tx.Create(&cust)

	cycle := "2026-09"
	inv := models.Invoice{
		CustomerID: &cust.ID, TotalAmount: 15000, TotalDue: 15000, RemainingAmount: 15000,
		BillingCycle: &cycle, DueDate: time.Now().Add(7 * 24 * time.Hour), ApprovalStatus: "APPROVED", Status: "Unpaid",
		KwhPriceSnapshot: 1000, FixedFeeSnapshot: 1000,
	}
	_ = tx.Create(&inv)

	// مزامنة أولية
	_ = SyncCustomerFinancials(tx, cust.ID)

	// 1. سداد كامل الفاتورة
	payRes, err := svc.CreatePayment(CreatePaymentRequest{
		CustomerID: cust.ID, InvoiceID: &inv.ID, AmountPaid: 15000, PaymentMethod: "CASH", AccountantName: "كاشير",
	})
	if err != nil {
		t.Fatalf("CreatePayment failed: %v", err)
	}

	// التحقق المباشر من جدول customers في الـ DB بعد السداد
	var custAfterPay models.Customer
	tx.First(&custAfterPay, cust.ID)
	if custAfterPay.TotalDue != 0 {
		t.Fatalf("Expected customer TotalDue in DB to be 0 after payment, got %.2f", custAfterPay.TotalDue)
	}

	// 2. إلغاء السند
	auditCtx := models.AuditContext{Username: "admin", Role: "ADMIN"}
	if err := svc.ReversePayment(payRes.Payment.ID, "سداد خاطئ", auditCtx); err != nil {
		t.Fatalf("ReversePayment failed: %v", err)
	}

	// 3. التحقق المباشر من جدول customers في الـ DB بعد الإلغاء
	var custAfterRev models.Customer
	tx.First(&custAfterRev, cust.ID)
	if custAfterRev.TotalDue != 15000.0 {
		t.Fatalf("Expected customer TotalDue in DB to be 15000.0 after reversal, got %.2f", custAfterRev.TotalDue)
	}
}

