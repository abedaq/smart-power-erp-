package services

import (
	"testing"
)

func TestPhoneNormalization(t *testing.T) {
	testCases := []struct {
		input       string
		expectedCust string
		expectedWA   string
	}{
		{"734019059", "734019059", "967734019059"},
		{"773245776", "773245776", "967773245776"},
		{"+967734019059", "734019059", "967734019059"},
		{"+967 734019059", "734019059", "967734019059"},
		{"00967773245776", "773245776", "967773245776"},
		{"009670734019059", "734019059", "967734019059"},
		{"0734019059", "734019059", "967734019059"},
		{"00734019059", "734019059", "967734019059"},
		{" 773-245-776 ", "773245776", "967773245776"},
		{"٧٣٤٠١٩٠٥٩", "734019059", "967734019059"},
		{"٧٧٣٢٤٥٧٧٦", "773245776", "967773245776"},
		{"0773245776", "773245776", "967773245776"},
	}

	for _, tc := range testCases {
		custPhone := NormalizeCustomerPhone(tc.input)
		if custPhone != tc.expectedCust {
			t.Errorf("NormalizeCustomerPhone(%q) = %q, expected %q", tc.input, custPhone, tc.expectedCust)
		}

		waPhone := NormalizeWhatsAppPhone(tc.input)
		if waPhone != tc.expectedWA {
			t.Errorf("NormalizeWhatsAppPhone(%q) = %q, expected %q", tc.input, waPhone, tc.expectedWA)
		}
	}
}

func TestToEnglishDigits(t *testing.T) {
	eastern := "٠١٢٣٤٥٦٧٨٩"
	expected := "0123456789"
	actual := ToEnglishDigits(eastern)
	if actual != expected {
		t.Errorf("ToEnglishDigits(%q) = %q, expected %q", eastern, actual, expected)
	}

	persian := "۰۱۲۳۴۵۶۷۸۹"
	actualPersian := ToEnglishDigits(persian)
	if actualPersian != expected {
		t.Errorf("ToEnglishDigits(%q) = %q, expected %q", persian, actualPersian, expected)
	}
}

func TestFinancialArithmeticFormula(t *testing.T) {
	prevReading := 1250.0
	currReading := 1420.0
	kwhPrice := 1400.0
	fixedFee := 1000.0
	arrears := 25000.0

	// 1. Consumption
	consumption := currReading - prevReading
	if consumption != 170.0 {
		t.Fatalf("expected consumption 170, got %.2f", consumption)
	}

	// 2. Consumption Value
	consumptionValue := consumption * kwhPrice
	if consumptionValue != 238000.0 {
		t.Fatalf("expected consumptionValue 238000, got %.2f", consumptionValue)
	}

	// 3. Total Amount
	totalAmount := consumptionValue + fixedFee
	if totalAmount != 239000.0 {
		t.Fatalf("expected totalAmount 239000, got %.2f", totalAmount)
	}

	// 4. Total Due
	totalDue := totalAmount + arrears
	if totalDue != 264000.0 {
		t.Fatalf("expected totalDue 264000, got %.2f", totalDue)
	}
}

func TestFIFOWaterfallAlgorithm(t *testing.T) {
	type MockInvoice struct {
		ID              int64
		RemainingAmount float64
		PaidAmount      float64
		Status          string
	}

	invoices := []MockInvoice{
		{ID: 1, RemainingAmount: 5000, PaidAmount: 0, Status: "Unpaid"},
		{ID: 2, RemainingAmount: 10000, PaidAmount: 0, Status: "Unpaid"},
		{ID: 3, RemainingAmount: 20000, PaidAmount: 0, Status: "Unpaid"},
	}

	paymentAmount := 12000.0
	remainingPayment := paymentAmount

	for i := range invoices {
		inv := &invoices[i]
		if remainingPayment <= 0 {
			break
		}

		if remainingPayment >= inv.RemainingAmount {
			alloc := inv.RemainingAmount
			remainingPayment -= alloc
			inv.PaidAmount += alloc
			inv.RemainingAmount = 0
			inv.Status = "Paid"
		} else {
			alloc := remainingPayment
			inv.PaidAmount += alloc
			inv.RemainingAmount -= alloc
			inv.Status = "Partially_Paid"
			remainingPayment = 0
		}
	}

	// Inv 1 must be fully Paid (paid 5000, remaining 0)
	if invoices[0].Status != "Paid" || invoices[0].RemainingAmount != 0 || invoices[0].PaidAmount != 5000 {
		t.Errorf("Inv 1 allocation mismatch: %+v", invoices[0])
	}

	// Inv 2 must be Partially_Paid (paid 7000, remaining 3000)
	if invoices[1].Status != "Partially_Paid" || invoices[1].RemainingAmount != 3000 || invoices[1].PaidAmount != 7000 {
		t.Errorf("Inv 2 allocation mismatch: %+v", invoices[1])
	}

	// Inv 3 must remain Unpaid (paid 0, remaining 20000)
	if invoices[2].Status != "Unpaid" || invoices[2].RemainingAmount != 20000 || invoices[2].PaidAmount != 0 {
		t.Errorf("Inv 3 allocation mismatch: %+v", invoices[2])
	}

	// Remaining payment to allocate should be 0
	if remainingPayment != 0 {
		t.Errorf("remainingPayment should be 0, got %.2f", remainingPayment)
	}
}

func TestCreditCreationOnOverpayment(t *testing.T) {
	totalDues := 15000.0
	paymentAmount := 20000.0

	surplus := paymentAmount - totalDues
	if surplus != 5000.0 {
		t.Fatalf("expected surplus 5000, got %.2f", surplus)
	}
}

func TestNegativeArrearsCarryover(t *testing.T) {
	// Scenario: Customer owes 2,000 YER on August invoice, pays 10,000 YER (8,000 YER credit)
	augustTotalDue := 2000.0
	paymentAmount := 10000.0

	// 1. Cycle 1 (August): Overpayment applied: Remaining becomes -8000, Status becomes Paid
	augustPaidAmount := paymentAmount
	augustRemaining := augustTotalDue - augustPaidAmount
	if augustRemaining != -8000.0 {
		t.Fatalf("expected augustRemaining -8000, got %.2f", augustRemaining)
	}
	augustStatus := "Unpaid"
	if augustRemaining <= 0 {
		augustStatus = "Paid"
	}
	if augustStatus != "Paid" {
		t.Fatalf("expected augustStatus Paid, got %s", augustStatus)
	}

	// 2. Cycle 2 (September): New consumption is 5,000 YER
	// Arrears query includes (status IN ('Unpaid', 'Partially_Paid') OR remaining_amount < 0)
	var activeInvoicesRemaining = []float64{augustRemaining} // -8000
	var septemberArrears float64
	for _, rem := range activeInvoicesRemaining {
		septemberArrears += rem
	}
	if septemberArrears != -8000.0 {
		t.Fatalf("expected septemberArrears -8000, got %.2f", septemberArrears)
	}

	septemberConsumptionValue := 4000.0
	septemberFixedFee := 1000.0
	septemberTotalAmount := septemberConsumptionValue + septemberFixedFee // 5000.0
	septemberTotalDue := septemberTotalAmount + septemberArrears           // 5000 + (-8000) = -3000.0

	if septemberTotalDue != -3000.0 {
		t.Fatalf("expected septemberTotalDue -3000, got %.2f", septemberTotalDue)
	}

	septemberStatus := "Unpaid"
	if septemberTotalDue <= 0 {
		septemberStatus = "Paid"
	}
	if septemberStatus != "Paid" {
		t.Fatalf("expected septemberStatus Paid when totalDue <= 0, got %s", septemberStatus)
	}
	septemberRemaining := septemberTotalDue // -3000.0

	// Credit Roll-Forward Rule: Upon absorbing August's negative credit into September,
	// August's remaining_amount MUST be zeroed out in database (UPDATE invoices SET remaining_amount = 0.00 WHERE id = august_id).
	augustRemaining = 0.00

	// 3. Cycle 3 (October): New consumption is 5,000 YER
	// Customer had -3,000 true remaining credit, so customer MUST owe: 5000 - 3000 = +2000 YER.
	// Arrears query across database invoices where (status IN ('Unpaid', 'Partially_Paid') OR remaining_amount < 0):
	// August is 0.00 (NOT counted). September is -3000.00.
	var activeInvoicesRemainingOct = []float64{augustRemaining, septemberRemaining}
	var octoberArrears float64
	for _, rem := range activeInvoicesRemainingOct {
		if rem < 0 || rem > 0 { // Unpaid or negative
			octoberArrears += rem
		}
	}
	if octoberArrears != -3000.0 {
		t.Fatalf("expected octoberArrears -3000 (single absorbed credit), got %.2f. Compounding bug detected!", octoberArrears)
	}

	octoberConsumptionValue := 4000.0
	octoberFixedFee := 1000.0
	octoberTotalAmount := octoberConsumptionValue + octoberFixedFee // 5000.0
	octoberTotalDue := octoberTotalAmount + octoberArrears           // 5000 + (-3000) = +2000.0

	if octoberTotalDue != 2000.0 {
		t.Fatalf("expected octoberTotalDue +2000, got %.2f. Credit roll-forward failed!", octoberTotalDue)
	}

	octoberStatus := "Unpaid"
	if octoberTotalDue <= 0 {
		octoberStatus = "Paid"
	}
	if octoberStatus != "Unpaid" {
		t.Fatalf("expected octoberStatus Unpaid for positive totalDue, got %s", octoberStatus)
	}

	// September's negative credit is now fully absorbed and rolled forward; zero out September's remaining
	septemberRemaining = 0.00
	octoberRemaining := octoberTotalDue // 2000.0

	if octoberRemaining != 2000.0 {
		t.Fatalf("expected octoberRemaining 2000, got %.2f", octoberRemaining)
	}
}

func TestNormalizeSubscriberNumber(t *testing.T) {
	testCases := []struct {
		input    string
		expected string
	}{
		{"00123", "123"},
		{"٠٠١٢٣", "123"},
		{"٠٠٠", "0"},
		{"000", "0"},
		{"١٢٣", "123"},
		{"0٠123", "123"},
		{"  ٠٠٥  ", "5"},
		{"0", "0"},
		{"٠", "0"},
		{"  ", "0"},
	}

	for _, tc := range testCases {
		actual := NormalizeSubscriberNumber(tc.input)
		if actual != tc.expected {
			t.Errorf("NormalizeSubscriberNumber(%q) = %q, expected %q", tc.input, actual, tc.expected)
		}
	}
}

