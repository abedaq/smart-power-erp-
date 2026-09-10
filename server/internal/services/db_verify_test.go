package services

import (
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

	// Check if there are any dummy names like مشترك 9...
	for _, c := range allCusts {
		if c.ID >= 500 {
			t.Errorf("Dummy ID >= 500 found: ID=%d, Name=%s", c.ID, c.FullName)
		}
	}
}
