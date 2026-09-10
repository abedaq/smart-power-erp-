package database

import (
	"fmt"
	"log"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

func InitDB(cfg *config.Config) (*gorm.DB, error) {
	logLevel := logger.Warn
	if cfg.Environment == "development" {
		logLevel = logger.Info
	}

	db, err := gorm.Open(postgres.New(postgres.Config{
		DSN:                  cfg.DatabaseURL,
		PreferSimpleProtocol: true, // Disables prepared statements to prevent cache collisions and support high concurrency
	}), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
		NowFunc: func() time.Time {
			return time.Now().UTC()
		},
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to postgres: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get sql.DB: %w", err)
	}

	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(50)
	sqlDB.SetConnMaxLifetime(time.Hour)
	sqlDB.SetConnMaxIdleTime(15 * time.Minute)

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Auto-ensure required schema tables & columns exist
	_ = db.AutoMigrate(&models.WhatsAppQueueMessage{}, &models.WhatsAppSession{})
	_ = db.Exec("ALTER TABLE customers ADD COLUMN IF NOT EXISTS sort_order INT DEFAULT 0;").Error
	_ = db.Exec("ALTER TABLE customers ADD COLUMN IF NOT EXISTS start_cycle VARCHAR(50) DEFAULT '2026-08-1';").Error
	_ = db.Exec("ALTER TABLE meter_readings ADD COLUMN IF NOT EXISTS lost_units NUMERIC(10,2) DEFAULT 0;").Error
	_ = db.Exec("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS whatsapp_sent_at TIMESTAMPTZ;").Error
	_ = db.Exec("ALTER TABLE invoices ADD COLUMN IF NOT EXISTS is_printed BOOLEAN DEFAULT FALSE;").Error
	_ = db.Exec("ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);").Error

	// Deduplication step: Rename any newer duplicate records with DUP- prefix keeping the lowest id intact
	dedupSQL := `
	WITH duplicates AS (
		SELECT id, subscriber_number,
			   ROW_NUMBER() OVER (
				   PARTITION BY COALESCE(NULLIF(REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', ''), ''), '0')
				   ORDER BY id ASC
			   ) as rnum
		FROM customers
		WHERE is_deleted = false
	)
	UPDATE customers c
	SET subscriber_number = 'DUP-' || c.subscriber_number
	FROM duplicates d
	WHERE c.id = d.id AND d.rnum > 1;
	`
	_ = db.Exec(dedupSQL).Error

	// Drop older/weaker index definition if not using zero-hardened expression
	_ = db.Exec(`
		DO $$
		BEGIN
			IF EXISTS (
				SELECT 1 FROM pg_indexes 
				WHERE indexname = 'uq_customers_subscriber_number_clean' 
				  AND indexdef NOT LIKE '%COALESCE%'
			) THEN
				DROP INDEX IF EXISTS uq_customers_subscriber_number_clean;
			END IF;
		END $$;
	`).Error

	// Fortified zero-safe unique index on subscriber numbers
	indexSQL := `
	CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_subscriber_number_clean 
	ON public.customers USING btree (
		COALESCE(NULLIF(REGEXP_REPLACE(TRIM(BOTH FROM lower(subscriber_number)), '^0+', ''), ''), '0')
	) 
	WHERE (is_deleted = false);
	`
	_ = db.Exec(indexSQL).Error

	DB = db
	log.Printf("[DB] Connected successfully to PostgreSQL (%s)", cfg.DatabaseURL)
	return db, nil
}