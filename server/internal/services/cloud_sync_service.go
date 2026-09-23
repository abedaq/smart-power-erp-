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

// Data Transfer Objects for Atomic RPC Payload
type PlanDTO struct {
	PlanName        string    `json:"plan_name"`
	KwhPrice        float64   `json:"kwh_price"`
	FixedFee        float64   `json:"fixed_fee"`
	GracePeriodDays int       `json:"grace_period_days"`
	Description     *string   `json:"description,omitempty"`
	IsActive        bool      `json:"is_active"`
	CreatedAt       time.Time `json:"created_at"`
}

type CustomerDTO struct {
	SubscriberNumber string    `json:"subscriber_number"`
	FullName         string    `json:"full_name"`
	PhoneNumber      string    `json:"phone_number"`
	IdCardURL        *string   `json:"id_card_url,omitempty"`
	Address          *string   `json:"address,omitempty"`
	MeterNumber      *string   `json:"meter_number,omitempty"`
	RouteNumber      *string   `json:"route_number,omitempty"`
	PlanName         *string   `json:"plan_name,omitempty"`
	InitialReading   float64   `json:"initial_reading"`
	StartCycle       string    `json:"start_cycle"`
	Status           string    `json:"status"`
	SortOrder        int       `json:"sort_order"`
	IsDeleted        bool      `json:"is_deleted"`
	CreatedAt        time.Time `json:"created_at"`
}

type ReadingDTO struct {
	SubscriberNumber string    `json:"subscriber_number"`
	ReadingValue     float64   `json:"reading_value"`
	ReadingDate      time.Time `json:"reading_date"`
	CollectorName    string    `json:"collector_name"`
	ApprovalStatus   string    `json:"approval_status"`
	ClientMutationID *string   `json:"client_mutation_id,omitempty"`
	WhatsAppSent     bool      `json:"whatsapp_sent"`
	CreatedAt        time.Time `json:"created_at"`
}

type InvoiceDTO struct {
	SubscriberNumber string    `json:"subscriber_number"`
	InvoiceNumber    string    `json:"invoice_number"`
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

type PaymentDTO struct {
	SubscriberNumber string    `json:"subscriber_number"`
	InvoiceNumber    *string   `json:"invoice_number,omitempty"`
	ReceiptNumber    string    `json:"receipt_number"`
	PaymentMethod    string    `json:"payment_method"`
	AmountPaid       float64   `json:"amount_paid"`
	PaymentDate      time.Time `json:"payment_date"`
	AccountantName   string    `json:"accountant_name"`
	ApprovalStatus   string    `json:"approval_status"`
	Notes            *string   `json:"notes,omitempty"`
	ClientMutationID *string   `json:"client_mutation_id,omitempty"`
	WhatsAppSent     bool      `json:"whatsapp_sent"`
	CreatedAt        time.Time `json:"created_at"`
}

type AllocationDTO struct {
	ReceiptNumber   string    `json:"receipt_number"`
	InvoiceNumber   string    `json:"invoice_number"`
	AmountAllocated float64   `json:"amount_allocated"`
	IsReversed      bool      `json:"is_reversed"`
	ReversedAt      *time.Time `json:"reversed_at,omitempty"`
	ReversalReason  *string   `json:"reversal_reason,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

type SyncStationPayload struct {
	SubscriptionPlans []PlanDTO       `json:"subscription_plans"`
	Customers         []CustomerDTO   `json:"customers"`
	MeterReadings     []ReadingDTO    `json:"meter_readings"`
	Invoices          []InvoiceDTO    `json:"invoices"`
	Payments          []PaymentDTO    `json:"payments"`
	Allocations       []AllocationDTO `json:"payment_allocations"`
}

type OutboxRow struct {
	ID         int64           `gorm:"column:id;primaryKey"`
	Table      string          `gorm:"column:table_name"`
	RecordID   int64           `gorm:"column:record_id"`
	NaturalKey *string         `gorm:"column:natural_key"`
	Operation  string          `gorm:"column:operation"`
	Payload    json.RawMessage `gorm:"column:payload"`
	Status     string          `gorm:"column:status"`
	Attempts   int             `gorm:"column:attempts"`
	LastError  *string         `gorm:"column:last_error"`
	CreatedAt  time.Time       `gorm:"column:created_at"`
	SyncedAt   *time.Time      `gorm:"column:synced_at"`
}

func (OutboxRow) TableName() string {
	return "sync_outbox"
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
			Timeout: 20 * time.Second,
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

	createOutboxSQL := `
		CREATE TABLE IF NOT EXISTS public.sync_outbox (
			id BIGSERIAL PRIMARY KEY,
			table_name VARCHAR(50) NOT NULL,
			record_id BIGINT NOT NULL,
			natural_key VARCHAR(100),
			operation VARCHAR(10) NOT NULL,
			payload JSONB NOT NULL,
			status VARCHAR(20) DEFAULT 'PENDING',
			attempts INT DEFAULT 0,
			last_error TEXT,
			created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
			synced_at TIMESTAMPTZ
		);
		CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending_v2 ON public.sync_outbox(status, id ASC);
		CREATE INDEX IF NOT EXISTS idx_sync_outbox_table_rec ON public.sync_outbox(table_name, record_id);

		CREATE OR REPLACE FUNCTION public.fn_capture_sync_outbox()
		RETURNS TRIGGER
		LANGUAGE plpgsql
		AS $$
		DECLARE
			v_table_name VARCHAR(50);
			v_record_id BIGINT;
			v_natural_key VARCHAR(100) := NULL;
			v_operation VARCHAR(10);
			v_payload JSONB;
		BEGIN
			v_table_name := TG_TABLE_NAME;
			v_operation := TG_OP;

			IF TG_OP = 'DELETE' THEN
				v_record_id := OLD.id;
				v_payload := to_jsonb(OLD);
				
				IF v_table_name = 'customers' THEN
					v_natural_key := OLD.subscriber_number;
				ELSIF v_table_name = 'invoices' THEN
					v_natural_key := OLD.invoice_number;
				ELSIF v_table_name = 'payments' THEN
					v_natural_key := OLD.receipt_number;
				ELSIF v_table_name = 'meter_readings' THEN
					v_natural_key := COALESCE(OLD.client_mutation_id::TEXT, OLD.id::TEXT);
				ELSIF v_table_name = 'subscription_plans' THEN
					v_natural_key := OLD.plan_name;
				END IF;
			ELSE
				v_record_id := NEW.id;
				v_payload := to_jsonb(NEW);

				IF v_table_name = 'customers' THEN
					v_natural_key := NEW.subscriber_number;
				ELSIF v_table_name = 'invoices' THEN
					v_natural_key := NEW.invoice_number;
				ELSIF v_table_name = 'payments' THEN
					v_natural_key := NEW.receipt_number;
				ELSIF v_table_name = 'meter_readings' THEN
					v_natural_key := COALESCE(NEW.client_mutation_id::TEXT, NEW.id::TEXT);
				ELSIF v_table_name = 'subscription_plans' THEN
					v_natural_key := NEW.plan_name;
				END IF;
			END IF;

			INSERT INTO public.sync_outbox (
				table_name,
				record_id,
				natural_key,
				operation,
				payload,
				status,
				created_at
			) VALUES (
				v_table_name,
				v_record_id,
				v_natural_key,
				v_operation,
				v_payload,
				'PENDING',
				CURRENT_TIMESTAMP
			);

			IF TG_OP = 'DELETE' THEN
				RETURN OLD;
			ELSE
				RETURN NEW;
			END IF;
		END;
		$$;

		DROP TRIGGER IF EXISTS trg_sync_outbox_customers ON public.customers;
		CREATE TRIGGER trg_sync_outbox_customers AFTER INSERT OR UPDATE OR DELETE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

		DROP TRIGGER IF EXISTS trg_sync_outbox_subscription_plans ON public.subscription_plans;
		CREATE TRIGGER trg_sync_outbox_subscription_plans AFTER INSERT OR UPDATE OR DELETE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

		DROP TRIGGER IF EXISTS trg_sync_outbox_meter_readings ON public.meter_readings;
		CREATE TRIGGER trg_sync_outbox_meter_readings AFTER INSERT OR UPDATE OR DELETE ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

		DROP TRIGGER IF EXISTS trg_sync_outbox_invoices ON public.invoices;
		CREATE TRIGGER trg_sync_outbox_invoices AFTER INSERT OR UPDATE OR DELETE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

		DROP TRIGGER IF EXISTS trg_sync_outbox_payments ON public.payments;
		CREATE TRIGGER trg_sync_outbox_payments AFTER INSERT OR UPDATE OR DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();

		DROP TRIGGER IF EXISTS trg_sync_outbox_payment_allocations ON public.payment_allocations;
		CREATE TRIGGER trg_sync_outbox_payment_allocations AFTER INSERT OR UPDATE OR DELETE ON public.payment_allocations FOR EACH ROW EXECUTE FUNCTION public.fn_capture_sync_outbox();
	`
	_ = s.db.Exec(createOutboxSQL)
}

func (s *CloudSyncService) Start() {
	go s.workerLoop()
	log.Println("☁️ Cloud Sync Engine initialized (Zero-Conflict Atomic Outbox & Natural Keys)")
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

	var pendingCount int64
	if s.db != nil {
		_ = s.db.Model(&OutboxRow{}).Where("status = ?", "PENDING").Count(&pendingCount).Error
	}
	currentStatus := s.status
	currentStatus.PendingCount = pendingCount
	return currentStatus
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

	cleanupTicker := time.NewTicker(24 * time.Hour)
	defer cleanupTicker.Stop()

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
		case <-cleanupTicker.C:
			s.cleanupOldOutbox()
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

	// 1. Process Outbox Events (Primary Zero-Conflict Stream)
	syncedOutbox, err := s.processOutboxBatch(200)
	if err != nil {
		log.Printf("⚠️ [CloudSync] Error processing outbox batch: %v", err)
		s.mu.Lock()
		s.status.LastError = err.Error()
		s.mu.Unlock()
	}

	// 2. If Outbox has 0 pending items, do historical baseline reconciliation
	if syncedOutbox == 0 {
		var pendingCount int64
		_ = s.db.Model(&OutboxRow{}).Where("status = ?", "PENDING").Count(&pendingCount).Error
		if pendingCount == 0 {
			if n, err := s.reconcileHistoricalData(); err != nil {
				log.Printf("⚠️ [CloudSync] Historical reconciliation error: %v", err)
			} else if n > 0 {
				syncedOutbox += n
			}
		}
	}

	if syncedOutbox > 0 {
		s.mu.Lock()
		s.status.TotalSyncedRows += int64(syncedOutbox)
		s.status.LastSyncTime = time.Now()
		s.status.LastError = ""
		s.mu.Unlock()
		log.Printf("☁️ [CloudSync] Successfully synced %d entities atomically to Supabase", syncedOutbox)
	}
}

func (s *CloudSyncService) callSupabaseRPC(functionName string, payload interface{}) (map[string]interface{}, error) {
	reqBody := map[string]interface{}{
		"p_payload": payload,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal RPC error: %w", err)
	}

	url := fmt.Sprintf("%s/rest/v1/rpc/%s", s.supabaseURL, functionName)
	req, err := http.NewRequest("POST", url, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create RPC request error: %w", err)
	}

	req.Header.Set("apikey", s.anonKey)
	req.Header.Set("Authorization", "Bearer "+s.anonKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute RPC error: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("Supabase RPC returned %d: %s", resp.StatusCode, string(respBody))
	}

	var result map[string]interface{}
	_ = json.Unmarshal(respBody, &result)
	return result, nil
}

func (s *CloudSyncService) processOutboxBatch(batchSize int) (int, error) {
	var rows []OutboxRow
	if err := s.db.Where("status = ?", "PENDING").Order("id ASC").Limit(batchSize).Find(&rows).Error; err != nil || len(rows) == 0 {
		return 0, nil
	}

	payload := SyncStationPayload{
		SubscriptionPlans: make([]PlanDTO, 0),
		Customers:         make([]CustomerDTO, 0),
		MeterReadings:     make([]ReadingDTO, 0),
		Invoices:          make([]InvoiceDTO, 0),
		Payments:          make([]PaymentDTO, 0),
		Allocations:       make([]AllocationDTO, 0),
	}

	var rowIDs []int64

	for _, r := range rows {
		rowIDs = append(rowIDs, r.ID)

		switch r.Table {
		case "subscription_plans":
			var p models.SubscriptionPlan
			if err := json.Unmarshal(r.Payload, &p); err == nil {
				createdAt := time.Now()
				if p.CreatedAt != nil {
					createdAt = *p.CreatedAt
				}
				payload.SubscriptionPlans = append(payload.SubscriptionPlans, PlanDTO{
					PlanName:        p.PlanName,
					KwhPrice:        p.KwhPrice,
					FixedFee:        p.FixedFee,
					GracePeriodDays: p.GracePeriodDays,
					Description:     p.Description,
					IsActive:        p.IsActive,
					CreatedAt:       createdAt,
				})
			}
		case "customers":
			var c models.Customer
			if err := json.Unmarshal(r.Payload, &c); err == nil {
				var planName *string
				if c.SubscriptionPlanID != nil {
					var plan models.SubscriptionPlan
					if err := s.db.First(&plan, *c.SubscriptionPlanID).Error; err == nil {
						planName = &plan.PlanName
					}
				}
				createdAt := time.Now()
				if c.CreatedAt != nil {
					createdAt = *c.CreatedAt
				}
				payload.Customers = append(payload.Customers, CustomerDTO{
					SubscriberNumber: c.SubscriberNumber,
					FullName:         c.FullName,
					PhoneNumber:      c.PhoneNumber,
					IdCardURL:        c.IdCardURL,
					Address:          c.Address,
					MeterNumber:      c.MeterNumber,
					RouteNumber:      c.RouteNumber,
					PlanName:         planName,
					InitialReading:   c.InitialReading,
					StartCycle:       c.StartCycle,
					Status:           c.Status,
					SortOrder:        c.SortOrder,
					IsDeleted:        c.IsDeleted,
					CreatedAt:        createdAt,
				})
			}
		case "meter_readings":
			var m models.MeterReading
			if err := json.Unmarshal(r.Payload, &m); err == nil {
				var subNum string
				if m.CustomerID != nil {
					_ = s.db.Table("customers").Where("id = ?", *m.CustomerID).Pluck("subscriber_number", &subNum)
				}
				if subNum != "" {
					readingDate := time.Now()
					if m.ReadingDate != nil {
						readingDate = *m.ReadingDate
					}
					createdAt := time.Now()
					if m.CreatedAt != nil {
						createdAt = *m.CreatedAt
					}
					payload.MeterReadings = append(payload.MeterReadings, ReadingDTO{
						SubscriberNumber: subNum,
						ReadingValue:     m.ReadingValue,
						ReadingDate:      readingDate,
						CollectorName:    m.CollectorName,
						ApprovalStatus:   m.ApprovalStatus,
						ClientMutationID: m.ClientMutationID,
						WhatsAppSent:     m.WhatsAppSent,
						CreatedAt:        createdAt,
					})
				}
			}
		case "invoices":
			var inv models.Invoice
			if err := json.Unmarshal(r.Payload, &inv); err == nil {
				var subNum string
				if inv.CustomerID != nil {
					_ = s.db.Table("customers").Where("id = ?", *inv.CustomerID).Pluck("subscriber_number", &subNum)
				}
				invNum := ""
				if inv.InvoiceNumber != nil {
					invNum = *inv.InvoiceNumber
				}
				if invNum != "" && subNum != "" {
					createdAt := time.Now()
					if inv.CreatedAt != nil {
						createdAt = *inv.CreatedAt
					}
					payload.Invoices = append(payload.Invoices, InvoiceDTO{
						SubscriberNumber: subNum,
						InvoiceNumber:    invNum,
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
			}
		case "payments":
			var p models.Payment
			if err := json.Unmarshal(r.Payload, &p); err == nil {
				var subNum string
				if p.CustomerID != nil {
					_ = s.db.Table("customers").Where("id = ?", *p.CustomerID).Pluck("subscriber_number", &subNum)
				}
				var invNum *string
				if p.InvoiceID != nil {
					var foundInv models.Invoice
					if err := s.db.First(&foundInv, *p.InvoiceID).Error; err == nil {
						invNum = foundInv.InvoiceNumber
					}
				}
				receiptNum := ""
				if p.ReceiptNumber != nil {
					receiptNum = *p.ReceiptNumber
				}
				if receiptNum != "" && subNum != "" {
					paymentDate := time.Now()
					if p.PaymentDate != nil {
						paymentDate = *p.PaymentDate
					}
					createdAt := time.Now()
					if p.CreatedAt != nil {
						createdAt = *p.CreatedAt
					}
					payload.Payments = append(payload.Payments, PaymentDTO{
						SubscriberNumber: subNum,
						InvoiceNumber:    invNum,
						ReceiptNumber:    receiptNum,
						PaymentMethod:    p.PaymentMethod,
						AmountPaid:       p.AmountPaid,
						PaymentDate:      paymentDate,
						AccountantName:   p.AccountantName,
						ApprovalStatus:   p.ApprovalStatus,
						Notes:            p.Notes,
						ClientMutationID: p.ClientMutationID,
						WhatsAppSent:     p.WhatsAppSent,
						CreatedAt:        createdAt,
					})
				}
			}
		case "payment_allocations":
			var alloc models.PaymentAllocation
			if err := json.Unmarshal(r.Payload, &alloc); err == nil {
				var receiptNum string
				_ = s.db.Table("payments").Where("id = ?", alloc.PaymentID).Pluck("receipt_number", &receiptNum)
				var invNum string
				_ = s.db.Table("invoices").Where("id = ?", alloc.InvoiceID).Pluck("invoice_number", &invNum)

				if receiptNum != "" && invNum != "" {
					createdAt := time.Now()
					if alloc.CreatedAt != nil {
						createdAt = *alloc.CreatedAt
					}
					payload.Allocations = append(payload.Allocations, AllocationDTO{
						ReceiptNumber:   receiptNum,
						InvoiceNumber:   invNum,
						AmountAllocated: alloc.AmountAllocated,
						IsReversed:      alloc.IsReversed,
						ReversedAt:      alloc.ReversedAt,
						ReversalReason:  alloc.ReversalReason,
						CreatedAt:       createdAt,
					})
				}
			}
		}
	}

	_, err := s.callSupabaseRPC("sync_station_payload", payload)
	if err != nil {
		_ = s.db.Model(&OutboxRow{}).Where("id IN ?", rowIDs).Updates(map[string]interface{}{
			"attempts":   gorm.Expr("attempts + 1"),
			"last_error": err.Error(),
		}).Error
		return 0, err
	}

	now := time.Now()
	_ = s.db.Model(&OutboxRow{}).Where("id IN ?", rowIDs).Updates(map[string]interface{}{
		"status":    "SYNCED",
		"synced_at": now,
	}).Error

	return len(rows), nil
}

func (s *CloudSyncService) reconcileHistoricalData() (int, error) {
	// Baseline snapshot query if sync_outbox is currently empty
	var customers []models.Customer
	if err := s.db.Limit(50).Find(&customers).Error; err != nil || len(customers) == 0 {
		return 0, nil
	}

	payload := SyncStationPayload{
		SubscriptionPlans: make([]PlanDTO, 0),
		Customers:         make([]CustomerDTO, 0),
		MeterReadings:     make([]ReadingDTO, 0),
		Invoices:          make([]InvoiceDTO, 0),
		Payments:          make([]PaymentDTO, 0),
		Allocations:       make([]AllocationDTO, 0),
	}

	for _, c := range customers {
		var planName *string
		if c.SubscriptionPlanID != nil {
			var plan models.SubscriptionPlan
			if err := s.db.First(&plan, *c.SubscriptionPlanID).Error; err == nil {
				planName = &plan.PlanName
			}
		}
		createdAt := time.Now()
		if c.CreatedAt != nil {
			createdAt = *c.CreatedAt
		}
		payload.Customers = append(payload.Customers, CustomerDTO{
			SubscriberNumber: c.SubscriberNumber,
			FullName:         c.FullName,
			PhoneNumber:      c.PhoneNumber,
			IdCardURL:        c.IdCardURL,
			Address:          c.Address,
			MeterNumber:      c.MeterNumber,
			RouteNumber:      c.RouteNumber,
			PlanName:         planName,
			InitialReading:   c.InitialReading,
			StartCycle:       c.StartCycle,
			Status:           c.Status,
			SortOrder:        c.SortOrder,
			IsDeleted:        c.IsDeleted,
			CreatedAt:        createdAt,
		})
	}

	_, err := s.callSupabaseRPC("sync_station_payload", payload)
	if err != nil {
		return 0, err
	}
	return len(customers), nil
}

func (s *CloudSyncService) cleanupOldOutbox() {
	if s.db == nil {
		return
	}
	cutoff := time.Now().AddDate(0, 0, -30)
	_ = s.db.Where("status = ? AND synced_at < ?", "SYNCED", cutoff).Delete(&OutboxRow{}).Error
	log.Println("🧹 Cleaned up synced outbox records older than 30 days")
}
