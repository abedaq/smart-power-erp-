package services

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
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
	"unsafe"

	"smartpower/internal/config"
	"smartpower/internal/licensing"
)

var (
	shell32           = syscall.NewLazyDLL("shell32.dll")
	procShellExecuteW = shell32.NewProc("ShellExecuteW")
)

var (
	// DefaultAppVersion represents current release version of SmartPower ERP
	DefaultAppVersion = "3.4.4.1"
	// DefaultManifestURL fallback remote version metadata endpoint
	DefaultManifestURL = "https://pkuoytiickgbtfeffmxq.supabase.co/storage/v1/object/public/updates/version.json"
)

// UpdateManifest describes remote version metadata
type UpdateManifest struct {
	Version        string   `json:"version"`
	DownloadURL    string   `json:"download_url"`
	SHA256         string   `json:"sha256"`
	Changelog      string   `json:"changelog"`
	Mandatory      bool     `json:"mandatory"`
	ReleaseDate    string   `json:"release_date,omitempty"`
	MinVersion     string   `json:"min_version,omitempty"`
	TargetLicenses []string `json:"target_licenses,omitempty"`
	TargetHWIDs    []string `json:"target_hwids,omitempty"`
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

	// Targeted Canary Filtering (Safeguard 2):
	// If TargetLicenses or TargetHWIDs are non-empty, the update is restricted ONLY to matching devices.
	if hasUpdate && (len(manifest.TargetLicenses) > 0 || len(manifest.TargetHWIDs) > 0) {
		licMgr := licensing.GetLicenseManager()
		currentHWID := licensing.GetMachineHWID()
		currentLicKey := ""
		if licMgr != nil {
			currentLicKey = licMgr.GetStatus().LicenseKey
		}

		matched := false
		for _, l := range manifest.TargetLicenses {
			trimmed := strings.TrimSpace(l)
			if trimmed != "" && strings.EqualFold(trimmed, strings.TrimSpace(currentLicKey)) {
				matched = true
				break
			}
		}
		if !matched {
			for _, h := range manifest.TargetHWIDs {
				trimmed := strings.TrimSpace(h)
				if trimmed != "" && strings.EqualFold(trimmed, strings.TrimSpace(currentHWID)) {
					matched = true
					break
				}
			}
		}

		if !matched {
			// This device is not whitelisted for this canary/patch update -> suppress update notification
			hasUpdate = false
		}
	}

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

func getUpdatesDir() string {
	progData := os.Getenv("ProgramData")
	if progData == "" {
		progData = "C:\\ProgramData"
	}
	if _, err := os.Stat(progData); err != nil {
		progData = os.TempDir()
	}
	updatesDir := filepath.Join(progData, "SmartPowerERP_Updates")
	_ = os.MkdirAll(updatesDir, 0755)
	return updatesDir
}

// DownloadUpdate downloads the update binary/executable into %ProgramData%\SmartPowerERP_Updates\
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

	tempDir := getUpdatesDir()
	destPath := filepath.Join(tempDir, "SmartPowerERP_new.exe")
	_ = os.Remove(destPath)

	req, err := http.NewRequestWithContext(downloadCtx, "GET", downloadURL, nil)
	if err != nil {
		s.recordError(fmt.Sprintf("failed to prepare download request: %v", err))
		return "", err
	}
	req.Header.Set("User-Agent", fmt.Sprintf("SmartPowerERP/%s", s.GetCurrentVersion()))

	downloadTransport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   15 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          10,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
	downloadClient := &http.Client{
		Timeout:   0, // Unlimited duration for large binary downloads
		Transport: downloadTransport,
	}

	resp, err := downloadClient.Do(req)
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
		// Check default updates location
		tempDefault := filepath.Join(getUpdatesDir(), "SmartPowerERP_new.exe")
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

	pid := os.Getpid()
	workDir := filepath.Dir(currentExe)

	// Locate native updater executable
	updaterExe := filepath.Join(targetDir, "updater.exe")
	if fi, err := os.Stat(updaterExe); err != nil || fi.Size() == 0 {
		tempUpdater := filepath.Join(getUpdatesDir(), "updater.exe")
		if fiT, errT := os.Stat(tempUpdater); errT == nil && fiT.Size() > 0 {
			updaterExe = tempUpdater
		}
	}

	log.Printf("🚀 Launching native Go silent updater at: %s (PID: %d, Binary: %s)", updaterExe, pid, currentExe)

	if runtime.GOOS == "windows" {
		verbPtr, err := syscall.UTF16PtrFromString("open")
		if err != nil {
			return fmt.Errorf("failed to encode verb: %w", err)
		}
		exePtr, err := syscall.UTF16PtrFromString(updaterExe)
		if err != nil {
			return fmt.Errorf("failed to encode updater path: %w", err)
		}
		argsStr := fmt.Sprintf("-pid=%d -target=\"%s\" -new=\"%s\" -workdir=\"%s\"", pid, currentExe, downloadedFilePath, workDir)
		argsPtr, err := syscall.UTF16PtrFromString(argsStr)
		if err != nil {
			return fmt.Errorf("failed to encode updater args: %w", err)
		}
		dirPtr, err := syscall.UTF16PtrFromString(workDir)
		if err != nil {
			return fmt.Errorf("failed to encode workdir: %w", err)
		}

		// SW_HIDE = 0 (completely windowless execution)
		ret, _, _ := procShellExecuteW.Call(
			0,
			uintptr(unsafe.Pointer(verbPtr)),
			uintptr(unsafe.Pointer(exePtr)),
			uintptr(unsafe.Pointer(argsPtr)),
			uintptr(unsafe.Pointer(dirPtr)),
			uintptr(0), // SW_HIDE
		)

		if ret <= 32 {
			// Fallback: direct exec.Command detached
			cmd := exec.Command(updaterExe, fmt.Sprintf("-pid=%d", pid), fmt.Sprintf("-target=%s", currentExe), fmt.Sprintf("-new=%s", downloadedFilePath), fmt.Sprintf("-workdir=%s", workDir))
			cmd.Dir = workDir
			cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000 | 0x00000008}
			if startErr := cmd.Start(); startErr != nil {
				s.recordError(fmt.Sprintf("فشل إطلاق المساعد التنفيذي للتحديث: %v", startErr))
				log.Printf("❌ Failed to launch updater binary: %v", startErr)
				return fmt.Errorf("فشل إطلاق المساعد التنفيذي للتحديث: %w", startErr)
			}
		}
		log.Printf("✅ Native Go Updater launched successfully for PID %d", pid)
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

	// Initiate graceful application shutdown with guaranteed termination
	s.mu.RLock()
	shutdownFn := s.shutdownFn
	s.mu.RUnlock()

	go func() {
		time.Sleep(300 * time.Millisecond)
		log.Println("🛑 Application is terminating to allow atomic binary replacement...")
		if shutdownFn != nil {
			shutdownFn()
		}
		time.Sleep(500 * time.Millisecond)
		os.Exit(0)
	}()

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

// DownloadAndApplyUIUpdate downloads the UI update bundle (ZIP), verifies SHA256 integrity,
// safely extracts it with Anti-Zip Slip protection into custom_ui_temp,
// closes all open file handles, and performs an atomic directory swap into custom_ui.
func (s *UpdateService) DownloadAndApplyUIUpdate(ctx context.Context, downloadURL, expectedSHA256 string) error {
	if downloadURL == "" {
		return errors.New("UI update download URL is empty")
	}

	updatesDir := getUpdatesDir()
	zipDestPath := filepath.Join(updatesDir, "ui_bundle.zip")
	_ = os.Remove(zipDestPath)

	req, err := http.NewRequestWithContext(ctx, "GET", downloadURL, nil)
	if err != nil {
		return fmt.Errorf("failed to prepare UI download request: %w", err)
	}
	req.Header.Set("User-Agent", fmt.Sprintf("SmartPowerERP/%s", s.GetCurrentVersion()))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("UI bundle download failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("UI bundle server returned HTTP %d", resp.StatusCode)
	}

	out, err := os.OpenFile(zipDestPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return fmt.Errorf("failed to create UI zip destination: %w", err)
	}

	hasher := sha256.New()
	mw := io.MultiWriter(out, hasher)
	_, copyErr := io.Copy(mw, resp.Body)
	_ = out.Close()
	if copyErr != nil {
		_ = os.Remove(zipDestPath)
		return fmt.Errorf("failed while downloading UI zip bundle: %w", copyErr)
	}

	// Verify SHA256 integrity checksum if specified
	if strings.TrimSpace(expectedSHA256) != "" {
		calcHash := hex.EncodeToString(hasher.Sum(nil))
		if !strings.EqualFold(calcHash, strings.TrimSpace(expectedSHA256)) {
			_ = os.Remove(zipDestPath)
			return fmt.Errorf("UI bundle SHA256 integrity mismatch! Expected: %s, Computed: %s", expectedSHA256, calcHash)
		}
		log.Printf("🔒 UI bundle SHA256 verified successfully: %s", calcHash)
	}

	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	if localAppData == "" {
		localAppData = "."
	}

	baseDir := filepath.Join(localAppData, "SmartPowerERP")
	customUIDir := filepath.Join(baseDir, "custom_ui")
	customUITemp := filepath.Join(baseDir, "custom_ui_temp")
	customUIOld := filepath.Join(baseDir, "custom_ui_old")

	_ = os.RemoveAll(customUITemp)
	if err := os.MkdirAll(customUITemp, 0755); err != nil {
		_ = os.Remove(zipDestPath)
		return fmt.Errorf("failed to create temp extraction directory: %w", err)
	}

	// Unzip with Anti-Zip Slip protection
	extractErr := func() error {
		zipReader, err := zip.OpenReader(zipDestPath)
		if err != nil {
			return fmt.Errorf("failed to open UI zip bundle: %w", err)
		}
		defer zipReader.Close()

		cleanDestDir := filepath.Clean(customUITemp) + string(os.PathSeparator)

		for _, f := range zipReader.File {
			targetPath := filepath.Join(customUITemp, f.Name)
			cleanTarget := filepath.Clean(targetPath)

			// Anti-Zip Slip verification
			if !strings.HasPrefix(cleanTarget+string(os.PathSeparator), cleanDestDir) && cleanTarget != filepath.Clean(customUITemp) {
				return fmt.Errorf("security violation: illegal path in zip archive (zip-slip detected): %s", f.Name)
			}

			if f.FileInfo().IsDir() {
				if err := os.MkdirAll(cleanTarget, f.Mode()); err != nil {
					return err
				}
				continue
			}

			if err := os.MkdirAll(filepath.Dir(cleanTarget), 0755); err != nil {
				return err
			}

			rc, err := f.Open()
			if err != nil {
				return err
			}

			dstFile, err := os.OpenFile(cleanTarget, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
			if err != nil {
				_ = rc.Close()
				return err
			}

			_, copyErr := io.Copy(dstFile, rc)
			_ = rc.Close()
			_ = dstFile.Close()
			if copyErr != nil {
				return copyErr
			}
		}
		return nil
	}()

	// Ensure downloaded zip archive is deleted after extraction and file descriptor release
	_ = os.Remove(zipDestPath)

	if extractErr != nil {
		_ = os.RemoveAll(customUITemp)
		return fmt.Errorf("UI extraction failed: %w", extractErr)
	}

	// Atomic Swap:
	// 1. Remove custom_ui_old if exists
	_ = os.RemoveAll(customUIOld)

	// 2. If custom_ui exists, rename to custom_ui_old
	if _, err := os.Stat(customUIDir); err == nil {
		if err := os.Rename(customUIDir, customUIOld); err != nil {
			_ = os.RemoveAll(customUITemp)
			return fmt.Errorf("failed to move active UI to backup: %w", err)
		}
	}

	// 3. Rename custom_ui_temp to custom_ui
	if err := os.Rename(customUITemp, customUIDir); err != nil {
		// Attempt rollback
		if _, statErr := os.Stat(customUIOld); statErr == nil {
			_ = os.Rename(customUIOld, customUIDir)
		}
		return fmt.Errorf("atomic swap failed (promoted temp UI): %w", err)
	}

	// 4. Clean up custom_ui_old
	_ = os.RemoveAll(customUIOld)

	log.Printf("✨ UI bundle successfully updated and atomically deployed to: %s", customUIDir)
	return nil
}
