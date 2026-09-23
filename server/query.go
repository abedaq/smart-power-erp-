package main

import (
	"fmt"
	"log"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type Customer struct {
	ID       uint
	FullName string
}

type Invoice struct {
	ID              uint
	CustomerID      uint
	BillingCycle    string
	Arrears         float64
	TotalDue        float64
	PaidAmount      float64
	RemainingAmount float64
	Status          string
}

func main() {
	dsn := "postgres://postgres:postgres@localhost:5432/smartpower_db?sslmode=disable"
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal(err)
	}

	var c Customer
	db.Where("full_name LIKE ?", "%أبو خالد%").First(&c)
	fmt.Printf("Customer: %+v\n", c)

	var invs []Invoice
	db.Where("customer_id = ?", c.ID).Order("id desc").Limit(5).Find(&invs)
	for _, inv := range invs {
		fmt.Printf("Invoice: ID=%d Cycle=%s Arrears=%.2f TotalDue=%.2f Paid=%.2f Rem=%.2f Status=%s\n", inv.ID, inv.BillingCycle, inv.Arrears, inv.TotalDue, inv.PaidAmount, inv.RemainingAmount, inv.Status)
	}
}
