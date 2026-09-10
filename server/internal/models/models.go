package models

import (
	"time"
)

type User struct {
	ID           int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	Username     string     `gorm:"type:varchar(50);unique;not null;column:username" json:"username"`
	PasswordHash string     `gorm:"type:text;not null;column:password_hash" json:"-"`
	FullName     string     `gorm:"type:varchar(100);not null;column:full_name" json:"full_name"`
	Role         string     `gorm:"type:varchar(20);default:'CASHIER';column:role" json:"role"`
	PhoneNumber  *string    `gorm:"type:varchar(20);column:phone_number" json:"phone_number,omitempty"`
	IsActive     bool       `gorm:"default:true;column:is_active" json:"is_active"`
	SupabaseUID  *string    `gorm:"type:uuid;unique;column:supabase_uid" json:"supabase_uid,omitempty"`
	CreatedAt    *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt    *time.Time `gorm:"column:updated_at" json:"updated_at,omitempty"`
}

func (User) TableName() string {
	return "users"
}

type SystemSettings struct {
	ID                int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	StationName       string     `gorm:"type:varchar(100);not null;column:station_name" json:"station_name"`
	StationLogoURL    *string    `gorm:"type:text;column:station_logo_url" json:"station_logo_url,omitempty"`
	StationPhone      *string    `gorm:"type:varchar(100);column:station_phone" json:"station_phone,omitempty"`
	StationPhoneAlt   *string    `gorm:"type:varchar(100);column:station_phone_alt" json:"station_phone_alt,omitempty"`
	BankAccounts      *string    `gorm:"type:text;column:bank_accounts" json:"bank_accounts,omitempty"`
	InvoicePolicyText *string    `gorm:"type:text;column:invoice_policy_text" json:"invoice_policy_text,omitempty"`
	WhatsAppStatus    string     `gorm:"type:varchar(20);default:'Disconnected';column:whatsapp_status" json:"whatsapp_status"`
	ReceiptFooter     *string    `gorm:"type:varchar(255);column:receipt_footer" json:"receipt_footer,omitempty"`
	ArrearsThreshold  float64    `gorm:"type:numeric(10,2);default:0;column:arrears_threshold" json:"arrears_threshold"`
	DefaultKwhPrice   float64    `gorm:"type:numeric(10,2);default:1000;column:default_kwh_price" json:"default_kwh_price"`
	DefaultFixedFee   float64    `gorm:"type:numeric(10,2);default:1000;column:default_fixed_fee" json:"default_fixed_fee"`
	MaxOverdueDays    int        `gorm:"default:7;column:max_overdue_days" json:"max_overdue_days"`
	Currency          string     `gorm:"type:varchar(20);default:'YER';column:currency" json:"currency"`
	CreatedAt         *time.Time `gorm:"column:created_at" json:"created_at,omitempty"`
	UpdatedAt         *time.Time `gorm:"column:updated_at" json:"updated_at,omitempty"`
}

func (SystemSettings) TableName() string {
	return "system_settings"
}

type SubscriptionPlan struct {
	ID              int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	PlanName        string     `gorm:"type:varchar(50);not null;column:plan_name" json:"plan_name"`
	KwhPrice        float64    `gorm:"type:numeric(10,2);not null;column:kwh_price" json:"kwh_price"`
	FixedFee        float64    `gorm:"type:numeric(10,2);default:0;column:fixed_fee" json:"fixed_fee"`
	GracePeriodDays int        `gorm:"default:10;column:grace_period_days" json:"grace_period_days"`
	Description     *string    `gorm:"type:text;column:description" json:"description,omitempty"`
	IsActive        bool       `gorm:"default:true;column:is_active" json:"is_active"`
	CreatedAt       *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt       *time.Time `gorm:"column:updated_at" json:"updated_at,omitempty"`
}

func (SubscriptionPlan) TableName() string {
	return "subscription_plans"
}

type Customer struct {
	ID                 int64             `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	SubscriberNumber   string            `gorm:"type:varchar(50);unique;not null;column:subscriber_number" json:"subscriber_number"`
	FullName           string            `gorm:"type:varchar(100);not null;column:full_name" json:"full_name"`
	PhoneNumber        string            `gorm:"type:varchar(20);not null;column:phone_number" json:"phone_number"`
	IdCardURL          *string           `gorm:"type:varchar(255);column:id_card_url" json:"id_card_url,omitempty"`
	Address            *string           `gorm:"type:varchar(255);column:address" json:"address,omitempty"`
	MeterNumber        *string           `gorm:"type:varchar(50);column:meter_number" json:"meter_number,omitempty"`
	RouteNumber        *string           `gorm:"type:varchar(50);column:route_number" json:"route_number,omitempty"`
	SubscriptionPlanID *int64            `gorm:"column:subscription_plan_id" json:"subscription_plan_id,omitempty"`
	SubscriptionPlan   *SubscriptionPlan `gorm:"foreignKey:SubscriptionPlanID" json:"subscription_plan,omitempty"`
	InitialReading     float64           `gorm:"type:numeric(10,2);default:0;column:initial_reading" json:"initial_reading"`
	StartCycle         string            `gorm:"type:varchar(50);default:'2026-08-1';column:start_cycle" json:"start_cycle"`
	Status             string            `gorm:"type:varchar(20);default:'Active';column:status" json:"status"`
	SortOrder          int               `gorm:"column:sort_order;default:0" json:"sort_order"`
	IsDeleted          bool              `gorm:"default:false;column:is_deleted" json:"is_deleted"`
	TestRunID          *string           `gorm:"type:varchar(100);column:test_run_id" json:"test_run_id,omitempty"`
	CreatedAt          *time.Time        `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt          *time.Time        `gorm:"column:updated_at" json:"updated_at,omitempty"`

	CurrentReading   float64  `gorm:"->" json:"current_reading"`
	LastReading      float64  `gorm:"->" json:"last_reading"`
	PreviousReading  float64  `gorm:"->" json:"previous_reading"`
	TotalDue         float64  `gorm:"->" json:"total_due"`
	Arrears          float64  `gorm:"->" json:"arrears"`
	PaidAmount       float64  `gorm:"->" json:"paid_amount"`
	Balance          float64  `gorm:"->" json:"balance"`
	AvailableCredits float64  `gorm:"->" json:"available_credits"`
	LatestInvoice    *Invoice `gorm:"->" json:"latest_invoice,omitempty"`

	MeterReadings []MeterReading   `gorm:"foreignKey:CustomerID" json:"meter_readings,omitempty"`
	Invoices      []Invoice        `gorm:"foreignKey:CustomerID" json:"invoices,omitempty"`
	Payments      []Payment        `gorm:"foreignKey:CustomerID" json:"payments,omitempty"`
	Credits       []CustomerCredit `gorm:"foreignKey:CustomerID" json:"credits,omitempty"`
}

func (Customer) TableName() string {
	return "customers"
}

type MeterReading struct {
	ID               int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	CustomerID       *int64     `gorm:"column:customer_id" json:"customer_id,omitempty"`
	Customer         *Customer  `gorm:"foreignKey:CustomerID" json:"customer,omitempty"`
	ReadingValue     float64    `gorm:"type:numeric(10,2);not null;column:reading_value" json:"reading_value"`
	ReadingDate      *time.Time `gorm:"default:now();column:reading_date" json:"reading_date"`
	CollectorName    string     `gorm:"type:varchar(100);not null;column:collector_name" json:"collector_name"`
	CollectorUserID  *int64     `gorm:"column:collector_user_id" json:"collector_user_id,omitempty"`
	CollectorUser    *User      `gorm:"foreignKey:CollectorUserID" json:"collector_user,omitempty"`
	ApprovalStatus   string     `gorm:"type:varchar(20);default:'APPROVED';column:approval_status" json:"approval_status"`
	ClientMutationID *string    `gorm:"type:uuid;column:client_mutation_id" json:"client_mutation_id,omitempty"`
	RejectionReason  *string    `gorm:"type:text;column:rejection_reason" json:"rejection_reason,omitempty"`
	WhatsAppSent     bool       `gorm:"default:false;column:whatsapp_sent" json:"whatsapp_sent"`
	LostUnits        float64    `gorm:"type:numeric(10,2);default:0;column:lost_units" json:"lost_units"`
	CreatedAt        *time.Time `gorm:"column:created_at" json:"created_at,omitempty"`
	UpdatedAt        *time.Time `gorm:"column:updated_at" json:"updated_at,omitempty"`
}

func (MeterReading) TableName() string {
	return "meter_readings"
}

type Invoice struct {
	ID               int64               `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	CustomerID       *int64              `gorm:"column:customer_id" json:"customer_id,omitempty"`
	Customer         *Customer           `gorm:"foreignKey:CustomerID" json:"customer,omitempty"`
	ReadingID        *int64              `gorm:"column:reading_id" json:"reading_id,omitempty"`
	MeterReading     *MeterReading       `gorm:"foreignKey:ReadingID" json:"meter_reading,omitempty"`
	InvoiceNumber    *string             `gorm:"type:varchar(50);column:invoice_number" json:"invoice_number,omitempty"`
	PreviousReading  float64             `gorm:"type:numeric(10,2);default:0;column:previous_reading" json:"previous_reading"`
	CurrentReading   float64             `gorm:"type:numeric(10,2);default:0;column:current_reading" json:"current_reading"`
	Consumption      float64             `gorm:"type:numeric(10,2);default:0;column:consumption" json:"consumption"`
	LostUnits        float64             `gorm:"type:numeric(10,2);default:0;column:lost_units" json:"lost_units"`
	ConsumptionValue float64             `gorm:"type:numeric(10,2);default:0;column:consumption_value" json:"consumption_value"`
	KwhPriceSnapshot float64             `gorm:"type:numeric(10,2);not null;column:kwh_price_snapshot" json:"kwh_price_snapshot"`
	FixedFeeSnapshot float64             `gorm:"type:numeric(10,2);not null;column:fixed_fee_snapshot" json:"fixed_fee_snapshot"`
	Arrears          float64             `gorm:"type:numeric(10,2);default:0;column:arrears" json:"arrears"`
	TotalDue         float64             `gorm:"type:numeric(10,2);default:0;column:total_due" json:"total_due"`
	PaidAmount       float64             `gorm:"type:numeric(10,2);default:0;column:paid_amount" json:"paid_amount"`
	RemainingAmount  float64             `gorm:"type:numeric(10,2);default:0;column:remaining_amount" json:"remaining_amount"`
	BillingCycle     *string             `gorm:"type:varchar(50);column:billing_cycle" json:"billing_cycle,omitempty"`
	TotalAmount      float64             `gorm:"type:numeric(10,2);not null;column:total_amount" json:"total_amount"`
	DueDate          time.Time           `gorm:"type:date;not null;column:due_date" json:"due_date"`
	ApprovalStatus   string              `gorm:"type:varchar(20);default:'APPROVED';column:approval_status" json:"approval_status"`
	Status           string              `gorm:"type:varchar(20);default:'Unpaid';column:status" json:"status"`
	CreatedAt        *time.Time          `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt        *time.Time          `gorm:"column:updated_at" json:"updated_at,omitempty"`
	Allocations      []PaymentAllocation `gorm:"foreignKey:InvoiceID" json:"allocations,omitempty"`
}

func (Invoice) TableName() string {
	return "invoices"
}

type Shift struct {
	ID             int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	UserID         *int64     `gorm:"column:user_id" json:"user_id,omitempty"`
	User           *User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	CashierName    string     `gorm:"type:varchar(100);not null;column:cashier_name" json:"cashier_name"`
	StartTime      time.Time  `gorm:"default:now();column:start_time" json:"start_time"`
	EndTime        *time.Time `gorm:"column:end_time" json:"end_time,omitempty"`
	StartingCash   float64    `gorm:"type:numeric(10,2);default:0;column:starting_cash" json:"starting_cash"`
	EndingCash     *float64   `gorm:"type:numeric(10,2);column:ending_cash" json:"ending_cash,omitempty"`
	TotalCollected float64    `gorm:"type:numeric(10,2);default:0;column:total_collected" json:"total_collected"`
	Status         string     `gorm:"type:varchar(20);default:'OPEN';column:status" json:"status"`
	CreatedAt      *time.Time `gorm:"column:created_at" json:"created_at,omitempty"`
}

func (Shift) TableName() string {
	return "shifts"
}

type Payment struct {
	ID               int64               `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	InvoiceID        *int64              `gorm:"column:invoice_id" json:"invoice_id,omitempty"`
	Invoice          *Invoice            `gorm:"foreignKey:InvoiceID" json:"invoice,omitempty"`
	CustomerID       *int64              `gorm:"column:customer_id" json:"customer_id,omitempty"`
	Customer         *Customer           `gorm:"foreignKey:CustomerID" json:"customer,omitempty"`
	ShiftID          *int64              `gorm:"column:shift_id" json:"shift_id,omitempty"`
	Shift            *Shift              `gorm:"foreignKey:ShiftID" json:"shift,omitempty"`
	ReceiptNumber    *string             `gorm:"type:varchar(50);unique;column:receipt_number" json:"receipt_number,omitempty"`
	PaymentMethod    string              `gorm:"type:varchar(20);default:'CASH';column:payment_method" json:"payment_method"`
	AmountPaid       float64             `gorm:"type:numeric(10,2);not null;column:amount_paid" json:"amount_paid"`
	PaymentDate      *time.Time          `gorm:"default:now();column:payment_date" json:"payment_date"`
	AccountantName   string              `gorm:"type:varchar(100);not null;column:accountant_name" json:"accountant_name"`
	AccountantUserID *int64              `gorm:"column:accountant_user_id" json:"accountant_user_id,omitempty"`
	AccountantUser   *User               `gorm:"foreignKey:AccountantUserID" json:"accountant_user,omitempty"`
	ApprovalStatus   string              `gorm:"type:varchar(20);default:'APPROVED';column:approval_status" json:"approval_status"`
	Notes            *string             `gorm:"type:text;column:notes" json:"notes,omitempty"`
	ClientMutationID *string             `gorm:"type:uuid;column:client_mutation_id" json:"client_mutation_id,omitempty"`
	RejectionReason  *string             `gorm:"type:text;column:rejection_reason" json:"rejection_reason,omitempty"`
	WhatsAppSent     bool                `gorm:"default:false;column:whatsapp_sent" json:"whatsapp_sent"`
	CreatedAt        *time.Time          `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt        *time.Time          `gorm:"column:updated_at" json:"updated_at,omitempty"`
	Allocations      []PaymentAllocation `gorm:"foreignKey:PaymentID" json:"allocations,omitempty"`
}

func (Payment) TableName() string {
	return "payments"
}

type PaymentAllocation struct {
	ID              int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	PaymentID       int64      `gorm:"not null;column:payment_id" json:"payment_id"`
	Payment         *Payment   `gorm:"foreignKey:PaymentID" json:"payment,omitempty"`
	InvoiceID       int64      `gorm:"not null;column:invoice_id" json:"invoice_id"`
	Invoice         *Invoice   `gorm:"foreignKey:InvoiceID" json:"invoice,omitempty"`
	AmountAllocated float64    `gorm:"type:numeric(10,2);not null;column:amount_allocated" json:"amount_allocated"`
	IsReversed      bool       `gorm:"default:false;column:is_reversed" json:"is_reversed"`
	ReversedAt      *time.Time `gorm:"column:reversed_at" json:"reversed_at,omitempty"`
	ReversalReason  *string    `gorm:"type:text;column:reversal_reason" json:"reversal_reason,omitempty"`
	CreatedAt       *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
}

func (PaymentAllocation) TableName() string {
	return "payment_allocations"
}

type CustomerCredit struct {
	ID              int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	CustomerID      int64      `gorm:"not null;column:customer_id" json:"customer_id"`
	Customer        *Customer  `gorm:"foreignKey:CustomerID" json:"customer,omitempty"`
	PaymentID       int64      `gorm:"not null;column:payment_id" json:"payment_id"`
	Payment         *Payment   `gorm:"foreignKey:PaymentID" json:"payment,omitempty"`
	Amount          float64    `gorm:"type:numeric(10,2);not null;column:amount" json:"amount"`
	RemainingAmount float64    `gorm:"type:numeric(10,2);not null;column:remaining_amount" json:"remaining_amount"`
	Status          string     `gorm:"type:varchar(20);default:'AVAILABLE';column:status" json:"status"`
	CreatedAt       *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
}

func (CustomerCredit) TableName() string {
	return "customer_credits"
}

type PaymentReceiptCounter struct {
	Year      int   `gorm:"primaryKey;column:year" json:"year"`
	LastValue int64 `gorm:"default:0;column:last_value" json:"last_value"`
}

func (PaymentReceiptCounter) TableName() string {
	return "payment_receipt_counters"
}

type AuditContext struct {
	UserID    *int64  `json:"user_id"`
	Username  string  `json:"username"`
	FullName  string  `json:"full_name"`
	Role      string  `json:"role"`
	IPAddress string  `json:"ip_address"`
}

type AuditLog struct {
	ID        int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	UserID    *int64     `gorm:"column:user_id" json:"user_id,omitempty"`
	User      *User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Action    string     `gorm:"type:varchar(50);not null;column:action" json:"action"`
	Entity    string     `gorm:"type:varchar(50);not null;column:entity" json:"entity"`
	EntityID  *string    `gorm:"type:varchar(100);column:entity_id" json:"entity_id,omitempty"`
	IPAddress *string    `gorm:"type:varchar(50);column:ip_address" json:"ip_address,omitempty"`
	Details   *string    `gorm:"type:text;column:details" json:"details,omitempty"`
	CreatedAt *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
}

func (AuditLog) TableName() string {
	return "audit_logs"
}

type WhatsAppQueueMessage struct {
	ID                   int64      `gorm:"primaryKey;autoIncrement;column:id" json:"id"`
	PhoneNumber          string     `gorm:"type:varchar(30);not null;column:phone_number" json:"phone_number"`
	Type                 string     `gorm:"type:varchar(20);default:'TEXT';column:type" json:"type"`
	Message              *string    `gorm:"type:text;column:message" json:"message,omitempty"`
	ImageBase64          *string    `gorm:"type:text;column:image_base64" json:"image_base64,omitempty"`
	Caption              *string    `gorm:"type:text;column:caption" json:"caption,omitempty"`
	MediaPath            *string    `gorm:"type:text;column:media_path" json:"media_path,omitempty"`
	Status               string     `gorm:"type:varchar(20);default:'PENDING';column:status" json:"status"`
	Retries              int        `gorm:"default:0;column:retries" json:"retries"`
	MaxRetries           int        `gorm:"default:3;column:max_retries" json:"max_retries"`
	ErrorMsg             *string    `gorm:"type:text;column:error_msg" json:"error_msg,omitempty"`
	SourceEntity         *string    `gorm:"type:varchar(30);column:source_entity" json:"source_entity,omitempty"`
	SourceID             *int64     `gorm:"column:source_id" json:"source_id,omitempty"`
	ClientMutationID     *string    `gorm:"type:uuid;column:client_mutation_id" json:"client_mutation_id,omitempty"`
	ScheduledAt          *time.Time `gorm:"default:now();column:scheduled_at" json:"scheduled_at"`
	ProcessingStartedAt *time.Time `gorm:"column:processing_started_at" json:"processing_started_at,omitempty"`
	SentAt               *time.Time `gorm:"column:sent_at" json:"sent_at,omitempty"`
	CreatedAt            *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt            *time.Time `gorm:"default:now();column:updated_at" json:"updated_at"`
}

func (WhatsAppQueueMessage) TableName() string {
	return "whatsapp_queue_messages"
}

type WhatsAppSession struct {
	SessionID       string     `gorm:"primaryKey;type:varchar(100);column:session_id" json:"session_id"`
	JID             *string    `gorm:"type:varchar(100);column:jid" json:"jid,omitempty"`
	Status          string     `gorm:"type:varchar(30);default:'DISCONNECTED';column:status" json:"status"`
	QRCode          *string    `gorm:"type:text;column:qr_code" json:"qr_code,omitempty"`
	PushName        *string    `gorm:"type:varchar(100);column:push_name" json:"push_name,omitempty"`
	AuthData        []byte     `gorm:"type:bytea;column:auth_data" json:"-"`
	IsActive        bool       `gorm:"default:false;column:is_active" json:"is_active"`
	LastConnectedAt *time.Time `gorm:"column:last_connected_at" json:"last_connected_at,omitempty"`
	LastHeartbeatAt *time.Time `gorm:"column:last_heartbeat_at" json:"last_heartbeat_at,omitempty"`
	CreatedAt       *time.Time `gorm:"default:now();column:created_at" json:"created_at"`
	UpdatedAt       *time.Time `gorm:"column:updated_at" json:"updated_at,omitempty"`
}

func (WhatsAppSession) TableName() string {
	return "whatsapp_sessions"
}