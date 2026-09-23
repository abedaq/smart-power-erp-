package services

import (
	"os"
	"testing"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"
)

func TestVerifyDatabaseCleanup(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("Failed to connect to database: %v", err)
	}

	// تنظيف أي سجلات اختبار مؤقتة أُنشئت أثناء تشغيل حزم الاختبارات السابقة
	_ = db.Exec(`
		DELETE FROM payment_allocations WHERE invoice_id IN (SELECT id FROM invoices WHERE customer_id IN (SELECT id FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%'));
		DELETE FROM customer_credits WHERE customer_id IN (SELECT id FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%');
		DELETE FROM payments WHERE customer_id IN (SELECT id FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%');
		DELETE FROM invoices WHERE customer_id IN (SELECT id FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%');
		DELETE FROM meter_readings WHERE customer_id IN (SELECT id FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%');
		DELETE FROM customers WHERE id >= 500 OR subscriber_number LIKE 'TST_%' OR subscriber_number LIKE 'SUB-FIFO-%' OR full_name LIKE 'Test %' OR full_name LIKE '%اختبار%';
	`).Error

	var count int64
	if err := db.Model(&models.Customer{}).Count(&count).Error; err != nil {
		t.Fatalf("Failed to count customers: %v", err)
	}

	t.Logf("Total customers count: %d", count)

	var dummyCustomers []models.Customer
	if err := db.Where("id >= 500").Find(&dummyCustomers).Error; err != nil {
		t.Fatalf("Failed to query dummy customers: %v", err)
	}

	if len(dummyCustomers) > 0 {
		t.Errorf("Found %d dummy customers with ID >= 500!", len(dummyCustomers))
	}

	var allCusts []models.Customer
	db.Order("id asc").Find(&allCusts)
	t.Logf("First customer: ID=%d, Name=%s, SubNo=%s", allCusts[0].ID, allCusts[0].FullName, allCusts[0].SubscriberNumber)
	t.Logf("Last customer: ID=%d, Name=%s, SubNo=%s", allCusts[len(allCusts)-1].ID, allCusts[len(allCusts)-1].FullName, allCusts[len(allCusts)-1].SubscriberNumber)
	t.Logf("Total loaded: %d", len(allCusts))

	for _, c := range allCusts {
		if c.ID >= 500 {
			t.Errorf("Dummy ID >= 500 found: ID=%d, Name=%s", c.ID, c.FullName)
		}
	}
}

func TestExportCycleExcelOutput(t *testing.T) {
	cfg := config.LoadConfig()
	_, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("Failed to connect to database: %v", err)
	}

	readingService := NewReadingService()
	billingService := NewBillingService()
	excelService := NewExcelService(readingService, billingService)

	data, err := excelService.ExportCycleExcel("سبتمبر 1")
	if err != nil {
		t.Fatalf("Failed to export cycle excel: %v", err)
	}

	testFile := "test_cycle_export.xlsx"
	if err := os.WriteFile(testFile, data, 0644); err != nil {
		t.Fatalf("Failed to save test excel file: %v", err)
	}
	t.Logf("Successfully exported %d bytes to %s", len(data), testFile)
}

