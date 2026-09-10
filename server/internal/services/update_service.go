package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"smartpower/internal/config"
)

const (
	// DefaultAppVersion represents current release version of SmartPower ERP
	DefaultAppVersion = "1.0.1"
	// DefaultManifestURL fallback remote version metadata endpoint
	DefaultManifestURL = "https://pkuoytiickgbtfeffmxq.supabase.co/storage/v1/object/public/updates/version.json"
)

// UpdateManifest describes remote version metadata
type UpdateManifest struct {
	Version     string `json:"version"`
	DownloadURL string `json:"download_url"`
	SHA256      string `json:"sha256"`
	Changelog   string `json:"changelog"`
	Mandatory   bool   `json:"mandatory"`
	ReleaseDate string `json:"release_date,omitempty"`
	MinVersion  string `json:"min_version,omitempty"`
}

// CheckUpdateResponse describes update availability response
type CheckUpdateResponse struct {
	HasUpdate      bool   `json:"has_update"`
	CurrentVersion string `json:"current_version"`
	LatestVersion  string `json:"latest_version"`
	DownloadURL    string `json:"download_url"`
	SHA256         string `json:"sha256"`
	Changelog      string `json:"changelog"`
	Mandatory      bool   `json:"mandatory"`
}

// UpdateProgress tracks download and application state
type UpdateProgress struct {
	Status         string  `json:"status"` // "idle", "checking", "downloading", "ready", "applying", "error"
	Progress       float64 `json:"progress"`
	BytesReceived  int64   `json:"bytes_received"`
	TotalBytes     int64   `json:"total_bytes"`
	DownloadedPath string  `json:"downloaded_path,omitempty"`
	LastError      string  `json:"last_error,omitempty"`
	LatestVersion  string  `json:"latest_version,omitempty"`
}

// UpdateService coordinates version checking, secure downloading with SHA256 integrity,
// and safe atomic Windows hot-swap binary replacement.
type UpdateService struct {
	cfg        *config.Config
	eventHub   *EventHub
	httpClient *http.Client
	shutdownFn func()
	version    string
	manifestURL string

	mu         sync.RWMutex
	progress   UpdateProgress
	cancelFunc context.CancelFunc
}

// NewUpdateService creates a new update service instance
func NewUpdateService(cfg *config.Config, eventHub *EventHub, shutdownFn func()) *UpdateService {
	appVer := os.Getenv("APP_VERSION")
	if appVer == "" {
		appVer = DefaultAppVersion
	}

	manifestURL := os.Getenv("UPDATE_MANIFEST_URL")
	if manifestURL == "" {
		manifestURL = DefaultManifestURL
	}

	return &UpdateService{
		cfg:         cfg,
		eventHub:    eventHub,
		shutdownFn:  shutdownFn,
		version:     appVer,
		manifestURL: manifestURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		progress: UpdateProgress{
			Status:   "idle",
			Progress: 0,
		},
	}
}

// SetShutdownFn updates the application shutdown callback
func (s *UpdateService) SetShutdownFn(fn func()) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.shutdownFn = fn
}

// SetManifestURL updates the manifest URL (useful for testing or dynamic config)
func (s *UpdateService) SetManifestURL(url string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.manifestURL = url
}

// GetCurrentVersion returns the running app version
func (s *UpdateService) GetCurrentVersion() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.version
}

// SetCurrentVersion updates current version (useful in testing)
func (s *UpdateService) SetCurrentVersion(ver string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.version = ver
}

// GetProgress returns thread-safe copy of current update state
func (s *UpdateService) GetProgress() UpdateProgress {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.progress
}

// CompareVersions compares two semver strings:
// Returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal
func CompareVersions(v1, v2 string) int {
	clean1 := strings.TrimPrefix(strings.TrimSpace(v1), "v")
	clean2 := strings.TrimPrefix(strings.TrimSpace(v2), "v")

	if idx := strings.IndexAny(clean1, "-+"); idx != -1 {
		clean1 = clean1[:idx]
	}
	if idx := strings.IndexAny(clean2, "-+"); idx != -1 {
		clean2 = clean2[:idx]
	}

	parts1 := strings.Split(clean1, ".")
	parts2 := strings.Split(clean2, ".")

	maxLen := len(parts1)
	if len(parts2) > maxLen {
		maxLen = len(parts2)
	}

	for i := 0; i < maxLen; i++ {
		var n1, n2 int64
		if i < len(parts1) {
			n1, _ = strconv.ParseInt(parts1[i], 10, 64)
		}
		if i < len(parts2) {
			n2, _ = strconv.ParseInt(parts2[i], 10, 64)
		}
		if n1 > n2 {
			return 1
		}
		if n1 < n2 {
			return -1
		}
	}
	return 0
}

// IsNewerVersion returns true if remote version is strictly greater than current
func IsNewerVersion(remote, current string) bool {
	return CompareVersions(remote, current) > 0
}

// CheckForUpdates fetches remote manifest and evaluates if a newer version is available
func (s *UpdateService) CheckForUpdates() (*CheckUpdateResponse, error) {
	s.mu.RLock()
	manifestURL := s.manifestURL
	currentVer := s.version
	s.mu.RUnlock()

	req, err := http.NewRequestWithContext(context.Background(), "GET", manifestURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request for update manifest: %w", err)
	}
	req.Header.Set("User-Agent", fmt.Sprintf("SmartPowerERP/%s", currentVer))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to update manifest server: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("update manifest server returned HTTP status %d", resp.StatusCode)
	}

	var manifest UpdateManifest
	if err := json.NewDecoder(resp.Body).Decode(&manifest); err != nil {
		return nil, fmt.Errorf("failed to parse update manifest JSON: %w", err)
	}

	if manifest.Version == "" {
		return nil, errors.New("invalid manifest: missing version field")
	}

	hasUpdate := IsNewerVersion(manifest.Version, currentVer)

	// If min_version is specified and current version is lower, update is mandatory
	isMandatory := manifest.Mandatory
	if manifest.MinVersion != "" && CompareVersions(manifest.MinVersion, currentVer) > 0 {
		isMandatory = true
	}

	s.mu.Lock()
	s.progress.LatestVersion = manifest.Version
	s.mu.Unlock()

	return &CheckUpdateResponse{
		HasUpdate:      hasUpdate,
		CurrentVersion: currentVer,
		LatestVersion:  manifest.Version,
		DownloadURL:    manifest.DownloadURL,
		SHA256:         manifest.SHA256,
		Changelog:      manifest.Changelog,
		Mandatory:      isMandatory,
	}, nil
}

// DownloadUpdate downloads the update binary/executable into %TEMP%\SmartPowerERP_Update\
// and verifies its SHA256 integrity while tracking progress.
func (s *UpdateService) DownloadUpdate(ctx context.Context, downloadURL string, expectedSHA256 string) (string, error) {
	if downloadURL == "" {
		// Try fetching manifest to get download URL
		check, err := s.CheckForUpdates()
		if err != nil {
			return "", fmt.Errorf("no download URL specified and failed to check manifest: %w", err)
		}
		downloadURL = check.DownloadURL
		if expectedSHA256 == "" {
			expectedSHA256 = check.SHA256
		}
	}

	if downloadURL == "" {
		return "", errors.New("download URL is empty in update manifest")
	}

	s.mu.Lock()
	if s.progress.Status == "downloading" {
		s.mu.Unlock()
		return "", errors.New("update download is already in progress")
	}

	downloadCtx, cancel := context.WithCancel(ctx)
	s.cancelFunc = cancel
	s.progress = UpdateProgress{
		Status:        "downloading",
		Progress:      0,
		BytesReceived: 0,
		TotalBytes:    0,
		LastError:     "",
	}
	s.mu.Unlock()

	s.emitProgressEvent()

	tempDir := filepath.Join(os.TempDir(), "SmartPowerERP_Update")
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		s.recordError(fmt.Sprintf("failed to create temp directory: %v", err))
		return "", err
	}

	destPath := filepath.Join(tempDir, "SmartPowerERP_new.exe")
	_ = os.Remove(destPath)

	req, err := http.NewRequestWithContext(downloadCtx, "GET", downloadURL, nil)
	if err != nil {
		s.recordError(fmt.Sprintf("failed to prepare download request: %v", err))
		return "", err
	}
	req.Header.Set("User-Agent", fmt.Sprintf("SmartPowerERP/%s", s.GetCurrentVersion()))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.recordError(fmt.Sprintf("download request failed: %v", err))
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("download server returned HTTP %d", resp.StatusCode)
		s.recordError(err.Error())
		return "", err
	}

	totalBytes := resp.ContentLength
	s.mu.Lock()
	s.progress.TotalBytes = totalBytes
	s.mu.Unlock()

	out, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		s.recordError(fmt.Sprintf("failed to create file at %s: %v", destPath, err))
		return "", err
	}
	defer out.Close()

	hasher := sha256.New()
	buf := make([]byte, 64*1024)
	var downloaded int64
	lastEmitTime := time.Now()

	for {
		select {
		case <-downloadCtx.Done():
			s.recordError("download cancelled")
			_ = out.Close()
			_ = os.Remove(destPath)
			return "", downloadCtx.Err()
		default:
		}

		n, rErr := resp.Body.Read(buf)
		if n > 0 {
			if _, wErr := out.Write(buf[:n]); wErr != nil {
				s.recordError(fmt.Sprintf("failed to write data: %v", wErr))
				return "", wErr
			}
			hasher.Write(buf[:n])
			downloaded += int64(n)

			s.mu.Lock()
			s.progress.BytesReceived = downloaded
			if totalBytes > 0 {
				s.progress.Progress = float64(downloaded) / float64(totalBytes) * 100
			}
			s.mu.Unlock()

			if time.Since(lastEmitTime) > 300*time.Millisecond {
				s.emitProgressEvent()
				lastEmitTime = time.Now()
			}
		}

		if rErr != nil {
			if rErr == io.EOF {
				break
			}
			s.recordError(fmt.Sprintf("error reading download stream: %v", rErr))
			return "", rErr
		}
	}

	// Explicitly close file before computing final status and releasing file handle
	_ = out.Close()

	// Verify SHA256 integrity checksum if specified
	if strings.TrimSpace(expectedSHA256) != "" {
		calculatedHash := hex.EncodeToString(hasher.Sum(nil))
		if !strings.EqualFold(calculatedHash, strings.TrimSpace(expectedSHA256)) {
			_ = os.Remove(destPath)
			err := fmt.Errorf("SHA256 integrity checksum mismatch! Expected: %s, Computed: %s", expectedSHA256, calculatedHash)
			s.recordError(err.Error())
			return "", err
		}
		log.Printf("🔒 SHA256 integrity verified successfully: %s", calculatedHash)
	}

	s.mu.Lock()
	s.progress.Status = "ready"
	s.progress.Progress = 100
	s.progress.BytesReceived = downloaded
	s.progress.DownloadedPath = destPath
	s.progress.LastError = ""
	s.mu.Unlock()

	s.emitProgressEvent()
	log.Printf("✅ Update package downloaded securely to %s (%d bytes)", destPath, downloaded)

	return destPath, nil
}

// StartAsyncDownload starts the update download in a background goroutine
func (s *UpdateService) StartAsyncDownload(downloadURL, sha256 string) {
	go func() {
		ctx := context.Background()
		_, err := s.DownloadUpdate(ctx, downloadURL, sha256)
		if err != nil {
			log.Printf("❌ Async update download failed: %v", err)
		}
	}()
}

// ApplyUpdate performs safe atomic Windows hot-swap binary replacement.
// It executes a detached updater script helper that waits for SmartPowerERP.exe
// to terminate, creates SmartPowerERP.exe.bak, swaps in the new executable,
// and restarts the application cleanly.
//
// CRITICAL DATA SAFETY:
// Database directories (`pgsql/data`, `data/`, backups) and config files
// are NEVER touched or deleted.
func (s *UpdateService) ApplyUpdate(downloadedFilePath string) error {
	// 1. Locate current running executable
	currentExe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to determine current running executable path: %w", err)
	}
	currentExe, err = filepath.EvalSymlinks(currentExe)
	if err != nil {
		return fmt.Errorf("failed to resolve executable symlinks: %w", err)
	}

	// 2. Resolve downloaded binary path
	if downloadedFilePath == "" {
		s.mu.RLock()
		downloadedFilePath = s.progress.DownloadedPath
		s.mu.RUnlock()
	}

	if downloadedFilePath == "" {
		// Check default temp location
		tempDefault := filepath.Join(os.TempDir(), "SmartPowerERP_Update", "SmartPowerERP_new.exe")
		if fi, err := os.Stat(tempDefault); err == nil && fi.Size() > 0 {
			downloadedFilePath = tempDefault
		}
	}

	if downloadedFilePath == "" {
		return errors.New("no downloaded update binary is ready to apply. Please download the update first.")
	}

	fi, err := os.Stat(downloadedFilePath)
	if err != nil || fi.Size() == 0 {
		return fmt.Errorf("downloaded update binary '%s' is missing or empty", downloadedFilePath)
	}

	// 3. CRITICAL DATA SAFETY ENFORCEMENT
	// Ensure target is strictly a valid executable and NOT inside database or data directories
	cleanExeName := strings.ToLower(filepath.Base(currentExe))
	if runtime.GOOS == "windows" && !strings.HasSuffix(cleanExeName, ".exe") {
		return fmt.Errorf("safety check failed: target file '%s' is not a windows executable", currentExe)
	}

	targetDir := filepath.Dir(currentExe)
	lowerTargetDir := strings.ToLower(targetDir)
	if strings.Contains(lowerTargetDir, "pgsql") || (strings.Contains(lowerTargetDir, "data") && !strings.Contains(lowerTargetDir, "appdata") && !strings.Contains(lowerTargetDir, "program files")) {
		if strings.HasSuffix(lowerTargetDir, "pgsql\\data") || strings.HasSuffix(lowerTargetDir, "pgsql/data") {
			return fmt.Errorf("safety check failed: target executable cannot reside inside database folder: %s", targetDir)
		}
	}

	backupExe := filepath.Join(targetDir, filepath.Base(currentExe)+".bak")
	tempDir := filepath.Dir(downloadedFilePath)
	scriptPath := filepath.Join(tempDir, "apply_update.bat")

	pid := os.Getpid()

	// Write standalone atomic batch script with resilient retry loop
	scriptContent := fmt.Sprintf(`@echo off
setlocal enabledelayedexpansion
title SmartPower ERP Auto-Updater
chcp 65001 >nul

set "PID=%d"
set "TARGET_EXE=%s"
set "BACKUP_EXE=%s"
set "NEW_EXE=%s"

:: Wait up to 30 seconds for the SmartPowerERP process (PID !PID!) to exit cleanly
set /A TIMEOUT_SEC=30
:WAIT_LOOP
tasklist /FI "PID eq !PID!" 2>NUL | find /I "!PID!" >NUL
if not errorlevel 1 (
    timeout /t 1 /nobreak >nul
    set /A TIMEOUT_SEC-=1
    if !TIMEOUT_SEC! GTR 0 goto WAIT_LOOP
    taskkill /F /PID !PID! >nul 2>&1
)

:: Safety delay ensuring file handles are fully released
timeout /t 2 /nobreak >nul

:: Backup old executable
if exist "!TARGET_EXE!" (
    copy /Y "!TARGET_EXE!" "!BACKUP_EXE!" >nul 2>&1
)

:: Resilient retry loop for atomic replacement (up to 15 retries with 1s delay)
set /A RETRIES=15
:REPLACE_LOOP
copy /Y "!NEW_EXE!" "!TARGET_EXE!" >nul 2>&1
if not errorlevel 1 goto REPLACE_SUCCESS
move /Y "!NEW_EXE!" "!TARGET_EXE!" >nul 2>&1
if not errorlevel 1 goto REPLACE_SUCCESS

timeout /t 1 /nobreak >nul
set /A RETRIES-=1
if !RETRIES! GTR 0 goto REPLACE_LOOP

:: Fallback safety: If replacement failed completely, restore backup if target missing
if not exist "!TARGET_EXE!" if exist "!BACKUP_EXE!" (
    copy /Y "!BACKUP_EXE!" "!TARGET_EXE!" >nul 2>&1
)
goto RELAUNCH

:REPLACE_SUCCESS
:: Clean up temp downloaded binary only after successful replacement
if exist "!NEW_EXE!" (
    del /F /Q "!NEW_EXE!" >nul 2>&1
)

:RELAUNCH
:: Relaunch updated SmartPower ERP application
start "" "!TARGET_EXE!"

:: Clean up this helper script after execution
(goto) 2>nul & del "%%~f0"
exit
`, pid, currentExe, backupExe, downloadedFilePath)

	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		return fmt.Errorf("failed to write updater helper script: %w", err)
	}

	log.Printf("🚀 Prepared atomic hot-swap updater script at: %s (Target PID: %d, Binary: %s)", scriptPath, pid, currentExe)

	// Spawning detached process in Windows
	if runtime.GOOS == "windows" {
		cmd := exec.Command("cmd.exe", "/C", scriptPath)
		cmd.SysProcAttr = &syscall.SysProcAttr{
			HideWindow:    true,
			CreationFlags: 0x08000000 | 0x00000200 | 0x00000008, // CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS
		}
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("failed to launch updater helper process: %w", err)
		}
	} else {
		// Non-windows fallback
		cmd := exec.Command("sh", "-c", fmt.Sprintf("sleep 2 && cp '%s' '%s' && rm -f '%s'", downloadedFilePath, currentExe, downloadedFilePath))
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("failed to launch unix updater fallback: %w", err)
		}
	}

	s.mu.Lock()
	s.progress.Status = "applying"
	s.mu.Unlock()
	s.emitProgressEvent()

	// Initiate graceful application shutdown
	s.mu.RLock()
	shutdownFn := s.shutdownFn
	s.mu.RUnlock()

	if shutdownFn != nil {
		go func() {
			time.Sleep(300 * time.Millisecond)
			log.Println("🛑 Application is terminating to allow atomic binary replacement...")
			shutdownFn()
		}()
	}

	return nil
}

func (s *UpdateService) recordError(errMsg string) {
	s.mu.Lock()
	s.progress.Status = "error"
	s.progress.LastError = errMsg
	s.mu.Unlock()
	s.emitProgressEvent()
	log.Printf("❌ [UpdateService Error] %s", errMsg)
}

func (s *UpdateService) emitProgressEvent() {
	if s.eventHub != nil {
		s.mu.RLock()
		p := s.progress
		s.mu.RUnlock()
		s.eventHub.Broadcast("system:update_progress", p)
	}
}
