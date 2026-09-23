package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/models"

	"gorm.io/gorm"
)

type SyncStatus struct {
	IsOnline        bool      `json:"is_online"`
	LastSyncTime    time.Time `json:"last_sync_time"`
	PendingCount    int64     `json:"pending_count"`
	TotalSyncedRows int64     `json:"total_synced_rows"`
	LastError       string    `json:"last_error,omitempty"`
	IsSyncing       bool      `json:"is_syncing"`
}

type CloudSyncService struct {
	db          *gorm.DB
	cfg         *config.Config
	supabaseURL string
	anonKey     string
	httpClient  *http.Client
	triggerChan chan struct{}
	stopChan    chan struct{}
	mu          sync.RWMutex
	status      SyncStatus
}

func NewCloudSyncService(db *gorm.DB, cfg *config.Config) *CloudSyncService {
	supaURL := ""
	anonKey := ""
	if cfg != nil {
		supaURL = cfg.SupabaseURL
		anonKey = cfg.SupabaseAnonKey
	}
	if supaURL == "" {
		supaURL = os.Getenv("SUPABASE_URL")
	}
	if supaURL == "" {
		supaURL = "https://pkuoytiickgbtfeffmxq.supabase.co"
	}
	if anonKey == "" {
		anonKey = os.Getenv("SUPABASE_ANON_KEY")
	}
	if anonKey == "" {
		anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
	}

	s := &CloudSyncService{
		db:          db,
		cfg:         cfg,
		supabaseURL: supaURL,
		anonKey:     anonKey,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		triggerChan: make(chan struct{}, 10),
		stopChan:    make(chan struct{}),
		status: SyncStatus{
			IsOnline: false,
		},
	}

	s.initSyncTables()
	return s
}

func (s *CloudSyncService) initSyncTables() {
	if s.db == nil {
		return
	}
	// Create Outbox Table for granular event captures
	createOutboxSQL := `
		CREATE TABLE IF NOT EXISTS sync_outbox (
			id BIGSERIAL PRIMARY KEY,
			table_name VARCHAR(50) NOT NULL,
			record_id BIGINT NOT NULL,
			operation VARCHAR(10) NOT NULL,
			payload JSONB NOT NULL,
			status VARCHAR(20) DEFAULT 'PENDING',
			attempts INT DEFAULT 0,
			last_error TEXT,
			created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
			synced_at TIMESTAMPTZ
		);
		CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(status, id);

		CREATE TABLE IF NOT EXISTS sync_checkpoints (
			table_name VARCHAR(50) PRIMARY KEY,
			last_synced_id BIGINT DEFAULT 0,
			last_synced_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
		);
	`
	_ = s.db.Exec(createOutboxSQL)
}

func (s *CloudSyncService) Start() {
	go s.workerLoop()
	log.Println("☁️ Cloud Sync Engine initialized (Store-and-Forward Row Replication)")
}

func (s *CloudSyncService) Stop() {
	close(s.stopChan)
	log.Println("🛑 Cloud Sync Engine stopped gracefully")
}

func (s *CloudSyncService) TriggerSync() {
	select {
	case s.triggerChan <- struct{}{}:
	default:
	}
}

func (s *CloudSyncService) GetStatus() SyncStatus {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.status
}

func (s *CloudSyncService) checkOnline() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("%s/rest/v1/", s.supabaseURL), nil)
	if err != nil {
		return false
	}
	req.Header.Set("apikey", s.anonKey)
	req.Header.Set("Authorization", "Bearer "+s.anonKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode < 500
}

func (s *CloudSyncService) workerLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	// Initial sync on startup after 3 seconds
	time.Sleep(3 * time.Second)
	s.runFullSyncCycle()

	for {
		select {
		case <-s.stopChan:
			return
		case <-s.triggerChan:
			s.runFullSyncCycle()
		case <-ticker.C:
			s.runFullSyncCycle()
		}
	}
}

func (s *CloudSyncService) runFullSyncCycle() {
	s.mu.Lock()
	if s.status.IsSyncing {
		s.mu.Unlock()
		return
	}
	s.status.IsSyncing = true
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		s.status.IsSyncing = false
		s.mu.Unlock()
	}()

	isOnline := s.checkOnline()
	s.mu.Lock()
	s.status.IsOnline = isOnline
	s.mu.Unlock()

	if !isOnline {
		return
	}

	totalSynced := 0

	// Sync in strict Foreign-Key Dependency Order:
	// 1. Subscription Plans
	if n, err := s.syncSubscriptionPlans(); err != nil {
		log.Printf("⚠️ [CloudSync] Error syncing subscription plans: %v", err)
	} else {
		totalSynced += n
	}
	// 2. Customers
	if n, err := s.syncCustomers(); err != nil {
		log.Printf("⚠️ [CloudSync] Error syncing customers: %v", err)
	} else {
		totalSynced += n
	}
	// 3. Meter Readings
	if n, err := s.syncMeterReadings(); err != nil {
		log.Printf("⚠️ [CloudSync] Error syncing meter readings: %v", err)
	} else {
		totalSynced += n
	}
	// 4. Invoices
	if n, err := s.syncInvoices(); err != nil {
		log.Printf("⚠️ [CloudSync] Error syncing invoices: %v", err)
	} else {
		totalSynced += n
	}
	// 5. Payments
	if n, err := s.syncPayments(); err != nil {
		log.Printf("⚠️ [CloudSync] Error syncing payments: %v", err)
	} else {
		totalSynced += n
	}

	// 6. Process custom outbox events
	if n, err := s.processOutboxEvents(); err != nil {
		log.Printf("⚠️ [CloudSync] Error processing outbox events: %v", err)
	} else {
		totalSynced += n
	}

	s.mu.Lock()
	if totalSynced > 0 {
		s.status.TotalSyncedRows += int64(totalSynced)
		s.status.LastSyncTime = time.Now()
		s.status.LastError = ""
		log.Printf("☁️ [CloudSync] Successfully synced %d SQL rows to Supabase", totalSynced)
	}
	s.mu.Unlock()
}

func (s *CloudSyncService) getLastSyncedID(table string) int64 {
	var lastID int64
	_ = s.db.Table("sync_checkpoints").Where("table_name = ?", table).Pluck("last_synced_id", &lastID)
	return lastID
}

func (s *CloudSyncService) setLastSyncedID(table string, lastID int64) {
	sql := `
		INSERT INTO sync_checkpoints (table_name, last_synced_id, last_synced_at)
		VALUES (?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT (table_name) DO UPDATE 
		SET last_synced_id = GREATEST(sync_checkpoints.last_synced_id, EXCLUDED.last_synced_id),
		    last_synced_at = CURRENT_TIMESTAMP;
	`
	_ = s.db.Exec(sql, table, lastID)
}

func (s *CloudSyncService) postgrestUpsert(table string, payload interface{}) error {
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal error: %w", err)
	}

	url := fmt.Sprintf("%s/rest/v1/%s?on_conflict=id", s.supabaseURL, table)
	req, err := http.NewRequest("POST", url, bytes.NewReader(bodyBytes))
	if err != nil {
		return fmt.Errorf("create request error: %w", err)
	}

	req.Header.Set("apikey", s.anonKey)
	req.Header.Set("Authorization", "Bearer "+s.anonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "resolution=merge-duplicates,return=minimal")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("http execute error: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("supabase returned %d: %s", resp.StatusCode, string(respBody))
	}

	return nil
}

// 1. Sync Subscription Plans
func (s *CloudSyncService) syncSubscriptionPlans() (int, error) {
	var plans []models.SubscriptionPlan
	if err := s.db.Find(&plans).Error; err != nil || len(plans) == 0 {
		return 0, err
	}

	type planDTO struct {
		ID              int64     `json:"id"`
		PlanName        string    `json:"plan_name"`
		KwhPrice        float64   `json:"kwh_price"`
		FixedFee        float64   `json:"fixed_fee"`
		GracePeriodDays int       `json:"grace_period_days"`
		CreatedAt       time.Time `json:"created_at"`
	}

	var dtos []planDTO
	for _, p := range plans {
		createdAt := time.Now()
		if p.CreatedAt != nil {
			createdAt = *p.CreatedAt
		}
		dtos = append(dtos, planDTO{
			ID:              p.ID,
			PlanName:        p.PlanName,
			KwhPrice:        p.KwhPrice,
			FixedFee:        p.FixedFee,
			GracePeriodDays: p.GracePeriodDays,
			CreatedAt:       createdAt,
		})
	}

	if err := s.postgrestUpsert("subscription_plans", dtos); err != nil {
		return 0, err
	}
	return len(dtos), nil
}

// 2. Sync Customers
func (s *CloudSyncService) syncCustomers() (int, error) {
	lastID := s.getLastSyncedID("customers")
	var customers []models.Customer
	if err := s.db.Where("id > ?", lastID).Order("id ASC").Limit(100).Find(&customers).Error; err != nil || len(customers) == 0 {
		return 0, err
	}

	type customerDTO struct {
		ID                 int64     `json:"id"`
		SubscriberNumber   string    `json:"subscriber_number"`
		FullName           string    `json:"full_name"`
		PhoneNumber        string    `json:"phone_number"`
		IdCardURL          *string   `json:"id_card_url,omitempty"`
		Address            *string   `json:"address,omitempty"`
		MeterNumber        *string   `json:"meter_number,omitempty"`
		RouteNumber        *string   `json:"route_number,omitempty"`
		SubscriptionPlanID *int64    `json:"subscription_plan_id,omitempty"`
		InitialReading     float64   `json:"initial_reading"`
		Status             string    `json:"status"`
		IsDeleted          bool      `json:"is_deleted"`
		CreatedAt          time.Time `json:"created_at"`
	}

	var dtos []customerDTO
	var maxID int64
	for _, c := range customers {
		if c.ID > maxID {
			maxID = c.ID
		}
		createdAt := time.Now()
		if c.CreatedAt != nil {
			createdAt = *c.CreatedAt
		}
		dtos = append(dtos, customerDTO{
			ID:                 c.ID,
			SubscriberNumber:   c.SubscriberNumber,
			FullName:           c.FullName,
			PhoneNumber:        c.PhoneNumber,
			IdCardURL:          c.IdCardURL,
			Address:            c.Address,
			MeterNumber:        c.MeterNumber,
			RouteNumber:        c.RouteNumber,
			SubscriptionPlanID: c.SubscriptionPlanID,
			InitialReading:     c.InitialReading,
			Status:             c.Status,
			IsDeleted:          c.IsDeleted,
			CreatedAt:          createdAt,
		})
	}

	if err := s.postgrestUpsert("customers", dtos); err != nil {
		return 0, err
	}
	s.setLastSyncedID("customers", maxID)
	return len(dtos), nil
}

// 3. Sync Meter Readings
func (s *CloudSyncService) syncMeterReadings() (int, error) {
	lastID := s.getLastSyncedID("meter_readings")
	var readings []models.MeterReading
	if err := s.db.Where("id > ?", lastID).Order("id ASC").Limit(100).Find(&readings).Error; err != nil || len(readings) == 0 {
		return 0, err
	}

	type readingDTO struct {
		ID               int64     `json:"id"`
		CustomerID       *int64    `json:"customer_id,omitempty"`
		ReadingValue     float64   `json:"reading_value"`
		ReadingDate      time.Time `json:"reading_date"`
		CollectorName    string    `json:"collector_name"`
		ApprovalStatus   string    `json:"approval_status"`
		ClientMutationID *string   `json:"client_mutation_id,omitempty"`
		WhatsAppSent     bool      `json:"whatsapp_sent"`
	}

	var dtos []readingDTO
	var maxID int64
	for _, r := range readings {
		if r.ID > maxID {
			maxID = r.ID
		}
		readingDate := time.Now()
		if r.ReadingDate != nil {
			readingDate = *r.ReadingDate
		}
		dtos = append(dtos, readingDTO{
			ID:               r.ID,
			CustomerID:       r.CustomerID,
			ReadingValue:     r.ReadingValue,
			ReadingDate:      readingDate,
			CollectorName:    r.CollectorName,
			ApprovalStatus:   r.ApprovalStatus,
			ClientMutationID: r.ClientMutationID,
			WhatsAppSent:     r.WhatsAppSent,
		})
	}

	if err := s.postgrestUpsert("meter_readings", dtos); err != nil {
		return 0, err
	}
	s.setLastSyncedID("meter_readings", maxID)
	return len(dtos), nil
}

// 4. Sync Invoices
func (s *CloudSyncService) syncInvoices() (int, error) {
	lastID := s.getLastSyncedID("invoices")
	var invoices []models.Invoice
	if err := s.db.Where("id > ?", lastID).Order("id ASC").Limit(100).Find(&invoices).Error; err != nil || len(invoices) == 0 {
		return 0, err
	}

	type invoiceDTO struct {
		ID               int64     `json:"id"`
		CustomerID       *int64    `json:"customer_id,omitempty"`
		ReadingID        *int64    `json:"reading_id,omitempty"`
		PreviousReading  float64   `json:"previous_reading"`
		CurrentReading   float64   `json:"current_reading"`
		Consumption      float64   `json:"consumption"`
		ConsumptionValue float64   `json:"consumption_value"`
		KwhPriceSnapshot float64   `json:"kwh_price_snapshot"`
		FixedFeeSnapshot float64   `json:"fixed_fee_snapshot"`
		Arrears          float64   `json:"arrears"`
		TotalDue         float64   `json:"total_due"`
		PaidAmount       float64   `json:"paid_amount"`
		RemainingAmount  float64   `json:"remaining_amount"`
		BillingCycle     *string   `json:"billing_cycle,omitempty"`
		TotalAmount      float64   `json:"total_amount"`
		DueDate          string    `json:"due_date"`
		ApprovalStatus   string    `json:"approval_status"`
		Status           string    `json:"status"`
		CreatedAt        time.Time `json:"created_at"`
	}

	var dtos []invoiceDTO
	var maxID int64
	for _, inv := range invoices {
		if inv.ID > maxID {
			maxID = inv.ID
		}
		createdAt := time.Now()
		if inv.CreatedAt != nil {
			createdAt = *inv.CreatedAt
		}
		dtos = append(dtos, invoiceDTO{
			ID:               inv.ID,
			CustomerID:       inv.CustomerID,
			ReadingID:        inv.ReadingID,
			PreviousReading:  inv.PreviousReading,
			CurrentReading:   inv.CurrentReading,
			Consumption:      inv.Consumption,
			ConsumptionValue: inv.ConsumptionValue,
			KwhPriceSnapshot: inv.KwhPriceSnapshot,
			FixedFeeSnapshot: inv.FixedFeeSnapshot,
			Arrears:          inv.Arrears,
			TotalDue:         inv.TotalDue,
			PaidAmount:       inv.PaidAmount,
			RemainingAmount:  inv.RemainingAmount,
			BillingCycle:     inv.BillingCycle,
			TotalAmount:      inv.TotalAmount,
			DueDate:          inv.DueDate.Format("2006-01-02"),
			ApprovalStatus:   inv.ApprovalStatus,
			Status:           inv.Status,
			CreatedAt:        createdAt,
		})
	}

	if err := s.postgrestUpsert("invoices", dtos); err != nil {
		return 0, err
	}
	s.setLastSyncedID("invoices", maxID)
	return len(dtos), nil
}

// 5. Sync Payments
func (s *CloudSyncService) syncPayments() (int, error) {
	lastID := s.getLastSyncedID("payments")
	var payments []models.Payment
	if err := s.db.Where("id > ?", lastID).Order("id ASC").Limit(100).Find(&payments).Error; err != nil || len(payments) == 0 {
		return 0, err
	}

	type paymentDTO struct {
		ID               int64     `json:"id"`
		InvoiceID        *int64    `json:"invoice_id,omitempty"`
		CustomerID       *int64    `json:"customer_id,omitempty"`
		ReceiptNumber    *string   `json:"receipt_number,omitempty"`
		PaymentMethod    string    `json:"payment_method"`
		AmountPaid       float64   `json:"amount_paid"`
		PaymentDate      time.Time `json:"payment_date"`
		AccountantName   string    `json:"accountant_name"`
		ApprovalStatus   string    `json:"approval_status"`
		Notes            *string   `json:"notes,omitempty"`
		ClientMutationID *string   `json:"client_mutation_id,omitempty"`
		WhatsAppSent     bool      `json:"whatsapp_sent"`
	}

	var dtos []paymentDTO
	var maxID int64
	for _, p := range payments {
		if p.ID > maxID {
			maxID = p.ID
		}
		paymentDate := time.Now()
		if p.PaymentDate != nil {
			paymentDate = *p.PaymentDate
		}
		dtos = append(dtos, paymentDTO{
			ID:               p.ID,
			InvoiceID:        p.InvoiceID,
			CustomerID:       p.CustomerID,
			ReceiptNumber:    p.ReceiptNumber,
			PaymentMethod:    p.PaymentMethod,
			AmountPaid:       p.AmountPaid,
			PaymentDate:      paymentDate,
			AccountantName:   p.AccountantName,
			ApprovalStatus:   p.ApprovalStatus,
			Notes:            p.Notes,
			ClientMutationID: p.ClientMutationID,
			WhatsAppSent:     p.WhatsAppSent,
		})
	}

	if err := s.postgrestUpsert("payments", dtos); err != nil {
		return 0, err
	}
	s.setLastSyncedID("payments", maxID)
	return len(dtos), nil
}

// 6. Process custom outbox events
func (s *CloudSyncService) processOutboxEvents() (int, error) {
	type outboxRecord struct {
		ID        int64           `gorm:"column:id"`
		TableName string          `gorm:"column:table_name"`
		RecordID  int64           `gorm:"column:record_id"`
		Operation string          `gorm:"column:operation"`
		Payload   json.RawMessage `gorm:"column:payload"`
	}

	var pending []outboxRecord
	if err := s.db.Table("sync_outbox").Where("status = 'PENDING'").Order("id ASC").Limit(50).Find(&pending).Error; err != nil || len(pending) == 0 {
		return 0, nil
	}

	count := 0
	for _, r := range pending {
		if err := s.postgrestUpsert(r.TableName, r.Payload); err != nil {
			_ = s.db.Table("sync_outbox").Where("id = ?", r.ID).Updates(map[string]interface{}{
				"attempts":   gorm.Expr("attempts + 1"),
				"last_error": err.Error(),
			})
		} else {
			_ = s.db.Table("sync_outbox").Where("id = ?", r.ID).Updates(map[string]interface{}{
				"status":    "SYNCED",
				"synced_at": time.Now(),
			})
			count++
		}
	}
	return count, nil
}
