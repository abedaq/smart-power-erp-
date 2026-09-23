package services

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/licensing"
)

type BackupMetrics struct {
	ReferenceID   string `json:"reference_id"`
	FileName      string `json:"file_name"`
	FileSizeBytes int64  `json:"file_size_bytes"`
	SHA256Hash    string `json:"sha256_hash"`
	CustomerCount int    `json:"customer_count"`
	LastInvoiceID int64  `json:"last_invoice_id"`
	LastPaymentID int64  `json:"last_payment_id"`
	DownloadURL   string `json:"download_url,omitempty"`
	UploadTime    string `json:"upload_time"`
}

type StreamingBackupService struct {
	cfg         *config.Config
	db          *sql.DB
	supabaseURL string
	anonKey     string
	httpClient  *http.Client
}

func NewStreamingBackupService(cfg *config.Config, db *sql.DB) *StreamingBackupService {
	supaURL := ""
	anonKey := ""
	if cfg != nil {
		supaURL = cfg.SupabaseURL
		anonKey = cfg.SupabaseAnonKey
	}
	if supaURL == "" {
		supaURL = "https://pkuoytiickgbtfeffmxq.supabase.co"
	}
	if anonKey == "" {
		anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
	}

	return &StreamingBackupService{
		cfg:         cfg,
		db:          db,
		supabaseURL: supaURL,
		anonKey:     anonKey,
		httpClient: &http.Client{
			Timeout: 20 * time.Minute, // Sufficient timeout for large database backups over slow connections
		},
	}
}

func (s *StreamingBackupService) findPgDumpPath() string {
	execPath, err := os.Executable()
	if err != nil {
		execPath, _ = os.Getwd()
	}
	appDir := filepath.Dir(execPath)
	cwd, _ := os.Getwd()

	candidates := []string{
		filepath.Join(appDir, "pgsql", "bin", "pg_dump.exe"),
		filepath.Join(cwd, "pgsql", "bin", "pg_dump.exe"),
		filepath.Join(appDir, "..", "pgsql", "bin", "pg_dump.exe"),
		filepath.Join("pgsql", "bin", "pg_dump.exe"),
		`C:\Program Files\PostgreSQL\18\bin\pg_dump.exe`,
		`C:\Program Files\PostgreSQL\17\bin\pg_dump.exe`,
		`C:\Program Files\PostgreSQL\16\bin\pg_dump.exe`,
	}

	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	return "pg_dump"
}

// ExecuteBackupAndUpload runs pg_dump, compresses it to a temporary scratch file,
// computes SHA-256 and byte size on the fly, uploads directly to Supabase Storage with
// accurate Content-Length, records the audit metadata, and cleans up the scratch file.
func (s *StreamingBackupService) ExecuteBackupAndUpload(ctx context.Context, userNote string) (*BackupMetrics, error) {
	licMgr := licensing.GetLicenseManager()
	licStatus := licMgr.GetStatus()
	hwid := licensing.GetMachineHWID()

	appVersion := DefaultAppVersion
	if appVersion == "" {
		appVersion = "3.4.5"
	}

	timestamp := time.Now().Format("20060102_150405")
	shortHWID := hwid
	if len(shortHWID) > 8 {
		shortHWID = shortHWID[:8]
	}
	referenceID := fmt.Sprintf("BAK-%s-%s", strings.ToUpper(shortHWID), timestamp)
	fileName := fmt.Sprintf("db_%s_%s.sql.gz", shortHWID, timestamp)

	metrics := &BackupMetrics{
		ReferenceID: referenceID,
		FileName:    fileName,
		UploadTime:  time.Now().Format(time.RFC3339),
	}

	// 1. Collect live database metrics safely
	if s.db != nil {
		_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM customers WHERE is_deleted = false").Scan(&metrics.CustomerCount)
		_ = s.db.QueryRowContext(ctx, "SELECT COALESCE(MAX(id), 0) FROM invoices").Scan(&metrics.LastInvoiceID)
		_ = s.db.QueryRowContext(ctx, "SELECT COALESCE(MAX(id), 0) FROM payments").Scan(&metrics.LastPaymentID)
	}

	// 2. Prepare scratch file in OS temp directory with guaranteed cleanup
	tmpFile, err := os.CreateTemp("", "smartpower_dump_*.sql.gz")
	if err != nil {
		return nil, fmt.Errorf("failed to create temp scratch file for backup: %w", err)
	}
	tmpFilePath := tmpFile.Name()
	defer func() {
		_ = tmpFile.Close()
		_ = os.Remove(tmpFilePath)
	}()

	// 3. Setup multi-writer for gzip compression, SHA-256 computation, and size tracking
	hasher := sha256.New()
	teeWriter := io.MultiWriter(tmpFile, hasher)
	gzWriter := gzip.NewWriter(teeWriter)

	// 4. Locate pg_dump and parse connection parameters
	pgDumpPath := s.findPgDumpPath()
	host := "127.0.0.1"
	port := "15432"
	user := "postgres"
	password := "postgres"
	dbName := "smartpower_db"

	if s.cfg != nil && s.cfg.DatabaseURL != "" {
		if parsedURL, err := url.Parse(s.cfg.DatabaseURL); err == nil {
			if h := parsedURL.Hostname(); h != "" {
				host = h
			}
			if p := parsedURL.Port(); p != "" {
				port = p
			}
			if u := parsedURL.User; u != nil {
				if username := u.Username(); username != "" {
					user = username
				}
				if pass, hasPass := u.Password(); hasPass {
					password = pass
				}
			}
			if path := strings.TrimPrefix(parsedURL.Path, "/"); path != "" {
				dbName = path
			}
		}
	}

	cmd := exec.CommandContext(ctx, pgDumpPath,
		"-h", host,
		"-p", port,
		"-U", user,
		"-d", dbName,
		"--no-owner",
		"--no-privileges",
		"--clean",
		"--if-exists",
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", password), "PGCLIENTENCODING=UTF8")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to pipe pg_dump stdout: %w", err)
	}
	stderrBuffer := new(bytes.Buffer)
	cmd.Stderr = stderrBuffer

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to start pg_dump process: %w", err)
	}

	// Copy stream into gzip compressor
	if _, err := io.Copy(gzWriter, stdout); err != nil {
		return nil, fmt.Errorf("error compressing pg_dump stream: %w", err)
	}

	if err := gzWriter.Close(); err != nil {
		return nil, fmt.Errorf("failed to flush gzip compressor: %w", err)
	}

	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("pg_dump failed (%v): %s", err, stderrBuffer.String())
	}

	// Flush and stat temp file for exact Content-Length
	fileInfo, err := tmpFile.Stat()
	if err != nil {
		return nil, fmt.Errorf("failed to stat compressed backup file: %w", err)
	}
	metrics.FileSizeBytes = fileInfo.Size()
	metrics.SHA256Hash = hex.EncodeToString(hasher.Sum(nil))

	// Rewind file to start for HTTP upload
	if _, err := tmpFile.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek temp file: %w", err)
	}

	// 5. Upload to Supabase Storage bucket 'station-backups'
	uploadURL := fmt.Sprintf("%s/storage/v1/object/station-backups/%s", s.supabaseURL, fileName)
	req, err := http.NewRequestWithContext(ctx, "POST", uploadURL, tmpFile)
	if err != nil {
		return nil, fmt.Errorf("failed to build upload request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.anonKey)
	req.Header.Set("apikey", s.anonKey)
	req.Header.Set("Content-Type", "application/gzip")
	req.Header.Set("x-upsert", "true")
	req.ContentLength = metrics.FileSizeBytes

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to upload backup to Supabase storage: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("supabase storage rejected upload (HTTP %d): %s", resp.StatusCode, string(respBody))
	}

	publicURL := fmt.Sprintf("%s/storage/v1/object/public/station-backups/%s", s.supabaseURL, fileName)
	metrics.DownloadURL = publicURL

	// 6. Record metadata in station_database_backups table
	backupRecord := map[string]interface{}{
		"reference_id":    metrics.ReferenceID,
		"license_key":     licStatus.LicenseKey,
		"hwid":            hwid,
		"station_name":    licStatus.ClientName,
		"app_version":     appVersion,
		"file_name":       fileName,
		"file_url":        publicURL,
		"file_size_bytes": metrics.FileSizeBytes,
		"sha256_hash":     metrics.SHA256Hash,
		"customer_count":  metrics.CustomerCount,
		"last_invoice_id": metrics.LastInvoiceID,
		"last_payment_id": metrics.LastPaymentID,
		"user_note":       userNote,
	}

	recordBytes, _ := json.Marshal(backupRecord)
	tableURL := fmt.Sprintf("%s/rest/v1/station_database_backups", s.supabaseURL)
	tableReq, err := http.NewRequestWithContext(ctx, "POST", tableURL, bytes.NewReader(recordBytes))
	if err == nil {
		tableReq.Header.Set("Authorization", "Bearer "+s.anonKey)
		tableReq.Header.Set("apikey", s.anonKey)
		tableReq.Header.Set("Content-Type", "application/json")
		tableReq.Header.Set("Prefer", "return=minimal")
		tResp, tErr := s.httpClient.Do(tableReq)
		if tErr == nil {
			_ = tResp.Body.Close()
		}
	}

	log.Printf("☁️ [StreamingBackup] Successfully uploaded database snapshot: %s (Size: %d bytes, SHA256: %s)",
		fileName, metrics.FileSizeBytes, metrics.SHA256Hash)

	return metrics, nil
}
