package services

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/crypto"
	"smartpower/internal/licensing"
)

type ClaimedCommand struct {
	CommandID      int64           `json:"command_id"`
	CmdType        string          `json:"cmd_type"`
	CmdPayload     json.RawMessage `json:"cmd_payload"`
	CmdSignature   string          `json:"cmd_signature"`
	CmdMinVersion  *string         `json:"cmd_min_version,omitempty"`
	CmdMaxVersion  *string         `json:"cmd_max_version,omitempty"`
}

type PatchPayload struct {
	SQL           string `json:"sql"`
	Transactional bool   `json:"transactional"`
	Description   string `json:"description,omitempty"`
}

type RemoteCommandWorker struct {
	cfg           *config.Config
	db            *sql.DB
	verifier      *crypto.Verifier
	backupService *StreamingBackupService
	supabaseURL   string
	anonKey       string
	httpClient    *http.Client
	triggerChan   chan struct{}
	stopChan      chan struct{}
	isProcessing  bool
	mu            sync.Mutex
}

func NewRemoteCommandWorker(cfg *config.Config, db *sql.DB, backupService *StreamingBackupService) (*RemoteCommandWorker, error) {
	v, err := crypto.NewVerifier()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize Ed25519 verifier: %w", err)
	}

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

	return &RemoteCommandWorker{
		cfg:           cfg,
		db:            db,
		verifier:      v,
		backupService: backupService,
		supabaseURL:   supaURL,
		anonKey:       anonKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		triggerChan: make(chan struct{}, 5),
		stopChan:    make(chan struct{}),
	}, nil
}

func (w *RemoteCommandWorker) Start() {
	go w.workerLoop()
	log.Println("🛡️ [RemoteCommandWorker] Secure Cloud Command & Patch Worker started")
}

func (w *RemoteCommandWorker) Stop() {
	close(w.stopChan)
	log.Println("🛑 [RemoteCommandWorker] Stopped gracefully")
}

func (w *RemoteCommandWorker) Trigger() {
	select {
	case w.triggerChan <- struct{}{}:
	default:
	}
}

func (w *RemoteCommandWorker) workerLoop() {
	// First check after 5 seconds of startup
	time.Sleep(5 * time.Second)
	w.pollAndExecute()

	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-w.stopChan:
			return
		case <-w.triggerChan:
			w.pollAndExecute()
		case <-ticker.C:
			w.pollAndExecute()
		}
	}
}

func (w *RemoteCommandWorker) pollAndExecute() {
	w.mu.Lock()
	if w.isProcessing {
		w.mu.Unlock()
		return
	}
	w.isProcessing = true
	w.mu.Unlock()

	defer func() {
		w.mu.Lock()
		w.isProcessing = false
		w.mu.Unlock()
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	hwid := licensing.GetMachineHWID()
	appVersion := DefaultAppVersion
	if appVersion == "" {
		appVersion = "3.4.5"
	}

	// 1. Claim next command atomically using Supabase RPC (FOR UPDATE SKIP LOCKED)
	claimURL := fmt.Sprintf("%s/rest/v1/rpc/claim_next_station_command", w.supabaseURL)
	claimReqBody, _ := json.Marshal(map[string]string{
		"p_hwid":        hwid,
		"p_app_version": appVersion,
	})

	req, err := http.NewRequestWithContext(ctx, "POST", claimURL, bytes.NewReader(claimReqBody))
	if err != nil {
		return
	}
	req.Header.Set("Authorization", "Bearer "+w.anonKey)
	req.Header.Set("apikey", w.anonKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := w.httpClient.Do(req)
	if err != nil {
		// Silent return when offline to avoid filling logs
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil || len(bodyBytes) == 0 {
		return
	}

	var commands []ClaimedCommand
	if err := json.Unmarshal(bodyBytes, &commands); err != nil {
		return
	}

	if len(commands) == 0 {
		return // No pending commands
	}

	for _, cmd := range commands {
		w.processSingleCommand(ctx, cmd, hwid)
	}
}

func (w *RemoteCommandWorker) processSingleCommand(ctx context.Context, cmd ClaimedCommand, hwid string) {
	log.Printf("📥 [RemoteCommandWorker] Claimed command #%d (Type: %s)", cmd.CommandID, cmd.CmdType)

	switch cmd.CmdType {
	case "RUN_SQL_PATCH":
		w.handleSQLPatch(ctx, cmd, hwid)
	case "FORCE_BACKUP":
		w.handleForceBackup(ctx, cmd, hwid)
	default:
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("UNKNOWN_COMMAND_TYPE: %s", cmd.CmdType), 0)
	}
}

func (w *RemoteCommandWorker) handleSQLPatch(ctx context.Context, cmd ClaimedCommand, hwid string) {
	var payload PatchPayload
	if err := json.Unmarshal(cmd.CmdPayload, &payload); err != nil {
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("MALFORMED_PAYLOAD: %v", err), 0)
		return
	}

	cleanSQL := strings.TrimSpace(payload.SQL)
	if cleanSQL == "" {
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", "EMPTY_SQL_PAYLOAD", 0)
		return
	}

	// 1. Verify Ed25519 digital signature against canonical message
	isValid := w.verifier.VerifySignature(cmd.CmdType, hwid, cleanSQL, cmd.CmdSignature)
	if !isValid {
		alertMsg := fmt.Sprintf("SECURITY_VIOLATION: Ed25519 signature verification failed for command #%d on station %s", cmd.CommandID, hwid)
		log.Printf("🚨 %s", alertMsg)
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", alertMsg, 0)
		return
	}

	start := time.Now()

	// 2. Dual-mode execution
	if payload.Transactional {
		// --- Transactional Mode (ACID with full Rollback on error) ---
		tx, err := w.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
		if err != nil {
			w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("BEGIN_TX_ERROR: %v", err), 0)
			return
		}
		defer tx.Rollback()

		res, err := tx.ExecContext(ctx, cleanSQL)
		if err != nil {
			log.Printf("❌ [SQLPatch] Command #%d execution failed: %v", cmd.CommandID, err)
			w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("SQL_EXECUTION_ERROR: %v", err), 0)
			return
		}

		if err := tx.Commit(); err != nil {
			w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("COMMIT_ERROR: %v", err), 0)
			return
		}

		rows, _ := res.RowsAffected()
		elapsed := time.Since(start)
		output := fmt.Sprintf("SUCCESS (Transactional): %d rows affected in %v", rows, elapsed)
		log.Printf("✅ [SQLPatch] Command #%d applied successfully (%s)", cmd.CommandID, output)
		w.updateCommandStatus(ctx, cmd.CommandID, "COMPLETED", output, "", int(rows))
	} else {
		// --- Direct Mode (For VACUUM, CREATE INDEX CONCURRENTLY, etc.) ---
		res, err := w.db.ExecContext(ctx, cleanSQL)
		if err != nil {
			log.Printf("❌ [SQLPatch] Command #%d direct execution failed: %v", cmd.CommandID, err)
			w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("DIRECT_SQL_ERROR: %v", err), 0)
			return
		}

		rows, _ := res.RowsAffected()
		elapsed := time.Since(start)
		output := fmt.Sprintf("SUCCESS (Direct Mode): %d rows affected in %v", rows, elapsed)
		log.Printf("✅ [SQLPatch] Command #%d applied successfully in direct mode (%s)", cmd.CommandID, output)
		w.updateCommandStatus(ctx, cmd.CommandID, "COMPLETED", output, "", int(rows))
	}
}

func (w *RemoteCommandWorker) handleForceBackup(ctx context.Context, cmd ClaimedCommand, hwid string) {
	if w.backupService == nil {
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", "BACKUP_SERVICE_NOT_INITIALIZED", 0)
		return
	}

	userNote := fmt.Sprintf("Triggered by Remote Command #%d", cmd.CommandID)
	metrics, err := w.backupService.ExecuteBackupAndUpload(ctx, userNote)
	if err != nil {
		log.Printf("❌ [RemoteBackup] Force backup command #%d failed: %v", cmd.CommandID, err)
		w.updateCommandStatus(ctx, cmd.CommandID, "FAILED", "", fmt.Sprintf("BACKUP_EXECUTION_ERROR: %v", err), 0)
		return
	}

	output := fmt.Sprintf("SUCCESS: Uploaded %s (%d bytes, SHA256: %s, Ref: %s)",
		metrics.FileName, metrics.FileSizeBytes, metrics.SHA256Hash, metrics.ReferenceID)
	log.Printf("✅ [RemoteBackup] Command #%d completed: %s", cmd.CommandID, output)
	w.updateCommandStatus(ctx, cmd.CommandID, "COMPLETED", output, "", 0)
}

func (w *RemoteCommandWorker) updateCommandStatus(ctx context.Context, cmdID int64, status, output, errorMsg string, affectedRows int) {
	updateURL := fmt.Sprintf("%s/rest/v1/station_remote_commands?id=eq.%d", w.supabaseURL, cmdID)
	payload := map[string]interface{}{
		"status":        status,
		"executed_at":   time.Now().UTC().Format(time.RFC3339),
		"affected_rows": affectedRows,
	}
	if output != "" {
		payload["result_output"] = output
	}
	if errorMsg != "" {
		payload["error_message"] = errorMsg
	}

	bodyBytes, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, "PATCH", updateURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return
	}
	req.Header.Set("Authorization", "Bearer "+w.anonKey)
	req.Header.Set("apikey", w.anonKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")

	resp, err := w.httpClient.Do(req)
	if err == nil {
		_ = resp.Body.Close()
	}
}
