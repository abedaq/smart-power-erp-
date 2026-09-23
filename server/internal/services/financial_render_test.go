package services

import (
	"strings"
	"testing"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/models"
)

func TestFinancialRenderInvariants(t *testing.T) {
	renderService := NewInvoiceRenderService(&config.Config{})
	settings := &models.SystemSettings{
		StationName:     "محطة الضياء لتوليد الطاقة الكهربائية",
		DefaultKwhPrice: 1400,
		DefaultFixedFee: 1000,
	}

	t.Run("Case 1: Direct full payment must show 0 YER (خالص)", func(t *testing.T) {
		custName := "حسين فواد محمد الجلال"
		cycle := "دورة سبتمبر 1"
		inv := &models.Invoice{
			ID:               73,
			BillingCycle:     &cycle,
			PreviousReading:  33,
			CurrentReading:   37,
			Consumption:      4,
			KwhPriceSnapshot: 1500,
			FixedFeeSnapshot: 1000,
			ConsumptionValue: 6000,
			Arrears:          0,
			TotalDue:         7000,
			PaidAmount:       7000,
			RemainingAmount:  0,
			Customer: &models.Customer{
				FullName:         custName,
				SubscriberNumber: "910534",
			},
		}
		payment := &models.Payment{
			ID:          300,
			AmountPaid:  7000,
			Customer:    inv.Customer,
			Invoice:     inv,
			PaymentDate: &time.Time{},
		}

		html := renderService.generateReceiptHTML(payment, inv, settings, 0)

		// Verification 1: Must show 0 ر.ي (خالص) and not +6600
		if !strings.Contains(html, "0 ر.ي (خالص)") {
			t.Errorf("Expected html to contain '0 ر.ي (خالص)' for full payment, got html:\n%s", html)
		}
		if strings.Contains(html, "+6,600 ر.ي (متبقي عليك)") {
			t.Errorf("Html erroneously contains phantom remaining balance '+6,600 ر.ي (متبقي عليك)'")
		}

		// Verification 2: Must show dynamic rate 1,500 in policy note
		if !strings.Contains(html, "سعر الكيلوواط / ساعة 1,500 ريال") {
			t.Errorf("Expected html to contain dynamic price 1,500 in policy note")
		}

		// Verification 3: Coupon header must have الاجمالي
		if !strings.Contains(html, "<th rowspan=\"2\">الاجمالي</th>") {
			t.Errorf("Expected coupon table header to have 'الاجمالي'")
		}
	})

	t.Run("Case 2: Payment with previous arrears must show arrears and 0 YER remaining", func(t *testing.T) {
		custName := "ياسر عبدة محمد غالب"
		cycle := "دورة سبتمبر 1"
		inv := &models.Invoice{
			ID:               609,
			BillingCycle:     &cycle,
			PreviousReading:  98,
			CurrentReading:   106,
			Consumption:      8,
			KwhPriceSnapshot: 1500,
			FixedFeeSnapshot: 1000,
			ConsumptionValue: 12000,
			Arrears:          17800,
			TotalDue:         30800,
			PaidAmount:       30800,
			RemainingAmount:  0,
			Customer: &models.Customer{
				FullName:         custName,
				SubscriberNumber: "910491",
			},
		}
		payment := &models.Payment{
			ID:          292,
			AmountPaid:  30800,
			Customer:    inv.Customer,
			Invoice:     inv,
			PaymentDate: &time.Time{},
		}

		html := renderService.generateReceiptHTML(payment, inv, settings, 0)

		if !strings.Contains(html, "17,800") {
			t.Errorf("Expected html to display arrears of 17,800")
		}
		if !strings.Contains(html, "30,800") {
			t.Errorf("Expected html to display total due / paid of 30,800")
		}
		if !strings.Contains(html, "0 ر.ي (خالص)") {
			t.Errorf("Expected html to show '0 ر.ي (خالص)' after full settlement")
		}
	})

	t.Run("Case 3: Partial payment must display remaining balance with red warning", func(t *testing.T) {
		cycle := "دورة سبتمبر 1"
		inv := &models.Invoice{
			ID:               101,
			BillingCycle:     &cycle,
			PreviousReading:  100,
			CurrentReading:   110,
			Consumption:      10,
			KwhPriceSnapshot: 1400,
			FixedFeeSnapshot: 1000,
			ConsumptionValue: 14000,
			Arrears:          0,
			TotalDue:         15000,
			PaidAmount:       10000,
			RemainingAmount:  5000,
			Customer: &models.Customer{
				FullName:         "مشترك تجريبي",
				SubscriberNumber: "999001",
			},
		}
		payment := &models.Payment{
			ID:          301,
			AmountPaid:  10000,
			Customer:    inv.Customer,
			Invoice:     inv,
			PaymentDate: &time.Time{},
		}

		html := renderService.generateReceiptHTML(payment, inv, settings, 5000)

		if !strings.Contains(html, "+5,000 ر.ي (متبقي عليك)") {
			t.Errorf("Expected html to show '+5,000 ر.ي (متبقي عليك)', got:\n%s", html)
		}
	})

	t.Run("Case 4: Overpayment must display credit balance", func(t *testing.T) {
		cycle := "دورة سبتمبر 1"
		inv := &models.Invoice{
			ID:               102,
			BillingCycle:     &cycle,
			PreviousReading:  100,
			CurrentReading:   110,
			Consumption:      10,
			KwhPriceSnapshot: 1400,
			FixedFeeSnapshot: 1000,
			ConsumptionValue: 14000,
			Arrears:          0,
			TotalDue:         15000,
			PaidAmount:       20000,
			RemainingAmount:  0,
			Customer: &models.Customer{
				FullName:         "مشترك دائن",
				SubscriberNumber: "999002",
			},
		}
		payment := &models.Payment{
			ID:          302,
			AmountPaid:  20000,
			Customer:    inv.Customer,
			Invoice:     inv,
			PaymentDate: &time.Time{},
		}

		html := renderService.generateReceiptHTML(payment, inv, settings, 0)

		if !strings.Contains(html, "-5,000 ر.ي (دائن لك)") {
			t.Errorf("Expected html to show credit '-5,000 ر.ي (دائن لك)', got:\n%s", html)
		}
	})

	t.Run("Case 5: Fallback when snapshot is 0 must not show 0 YER", func(t *testing.T) {
		cycle := "دورة سابقة"
		inv := &models.Invoice{
			ID:               103,
			BillingCycle:     &cycle,
			PreviousReading:  50,
			CurrentReading:   60,
			Consumption:      10,
			KwhPriceSnapshot: 0, // Old invoice with no snapshot
			FixedFeeSnapshot: 1000,
			ConsumptionValue: 14000,
			Arrears:          0,
			TotalDue:         15000,
			PaidAmount:       15000,
			RemainingAmount:  0,
			Customer: &models.Customer{
				FullName:         "مشترك قديم",
				SubscriberNumber: "999003",
			},
		}

		htmlInv := renderService.generateInvoiceHTML(inv, settings)

		// Must fallback to system default 1400 and not print 0
		if !strings.Contains(htmlInv, "سعر الكيلوواط / ساعة 1,400 ريال") {
			t.Errorf("Expected html to fallback to default 1,400 rate, got:\n%s", htmlInv)
		}
	})
}
