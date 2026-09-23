package services

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/licensing"

	"golang.org/x/sys/windows"
)

type DiagnosticsService struct {
	cfg         *config.Config
	supabaseURL string
	anonKey     string
	httpClient  *http.Client
}

type DiagnosticUploadResult struct {
	Success      bool   `json:"success"`
	ReferenceID  string `json:"reference_id"`
	FileName     string `json:"file_name"`
	Message      string `json:"message"`
	DownloadURL  string `json:"download_url,omitempty"`
}

func NewDiagnosticsService(cfg *config.Config) *DiagnosticsService {
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

	return &DiagnosticsService{
		cfg:         cfg,
		supabaseURL: supaURL,
		anonKey:     anonKey,
		httpClient: &http.Client{
			Timeout: 45 * time.Second,
		},
	}
}

// readLastLinesNonExclusive reads the last n lines of a file on Windows without triggering Sharing Violations (Error 32)
func readLastLinesNonExclusive(filePath string, maxLines int) ([]string, error) {
	if runtime.GOOS == "windows" {
		pathPtr, err := windows.UTF16PtrFromString(filePath)
		if err != nil {
			return nil, err
		}

		handle, err := windows.CreateFile(
			pathPtr,
			windows.GENERIC_READ,
			windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE,
			nil,
			windows.OPEN_EXISTING,
			windows.FILE_ATTRIBUTE_NORMAL,
			0,
		)
		if err != nil {
			return nil, err
		}
		defer windows.CloseHandle(handle)

		f := os.NewFile(uintptr(handle), filePath)
		return readTailLines(f, maxLines)
	}

	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return readTailLines(f, maxLines)
}

func readTailLines(f *os.File, maxLines int) ([]string, error) {
	stat, err := f.Stat()
	if err != nil {
		return nil, err
	}

	size := stat.Size()
	if size == 0 {
		return []string{}, nil
	}

	// Read last 256KB max
	readSize := int64(256 * 1024)
	if size < readSize {
		readSize = size
	}

	offset := size - readSize
	buf := make([]byte, readSize)
	_, err = f.ReadAt(buf, offset)
	if err != nil && err != io.EOF {
		return nil, err
	}

	lines := strings.Split(string(buf), "\n")
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}

	// Clean trailing empty lines
	var result []string
	for _, l := range lines {
		trimmed := strings.TrimRight(l, "\r")
		if trimmed != "" || len(result) > 0 {
			result = append(result, trimmed)
		}
	}
	return result, nil
}

// sanitizeLogs masks sensitive tokens, passwords, and authorization keys
func sanitizeLogs(content string) string {
	// Redact Bearer tokens
	reBearer := regexp.MustCompile(`(?i)(Bearer\s+)[A-Za-z0-9\-\._~+/]+=*`)
	content = reBearer.ReplaceAllString(content, `${1}[REDACTED_TOKEN]`)

	// Redact DB passwords in URLs (e.g. postgres://user:pass@host)
	reDBPass := regexp.MustCompile(`(postgres(?:ql)?://[^:]+:)([^@]+)(@)`)
	content = reDBPass.ReplaceAllString(content, `${1}******${3}`)

	// Redact password fields in JSON / queries
	rePass := regexp.MustCompile(`(?i)("?password"?\s*[:=]\s*)"[^"]+"`)
	content = rePass.ReplaceAllString(content, `${1}"[REDACTED]"`)

	return content
}

// BuildDiagnosticBundle creates an in-memory zip containing sanitized logs and system telemetry
func (s *DiagnosticsService) BuildDiagnosticBundle(userNote string) ([]byte, map[string]interface{}, error) {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	if localAppData == "" {
		localAppData = "."
	}
	logsDir := filepath.Join(localAppData, "SmartPowerERP", "logs")

	licMgr := licensing.GetLicenseManager()
	licStatus := licMgr.GetStatus()
	hwid := licensing.GetMachineHWID()

	sysInfo := map[string]interface{}{
		"app_version":    DefaultAppVersion,
		"hwid":           hwid,
		"license_key":    licStatus.LicenseKey,
		"station_name":   licStatus.ClientName,
		"license_active": licStatus.IsLicensed,
		"os":             runtime.GOOS,
		"arch":           runtime.GOARCH,
		"timestamp":      time.Now().Format(time.RFC3339),
		"user_note":      userNote,
	}

	zipBuffer := new(bytes.Buffer)
	zipWriter := zip.NewWriter(zipBuffer)

	// Helper to create valid zip entry with Deflate compression and current timestamp
	addZipFile := func(name string, data []byte) error {
		header := &zip.FileHeader{
			Name:     name,
			Method:   zip.Deflate,
			Modified: time.Now(),
		}
		w, err := zipWriter.CreateHeader(header)
		if err != nil {
			return err
		}
		_, err = w.Write(data)
		return err
	}

	// 1. Add system_info.json
	sysInfoBytes, _ := json.MarshalIndent(sysInfo, "", "  ")
	_ = addZipFile("system_info.json", sysInfoBytes)

	// 2. Add log files (non-exclusive reading, up to 500 lines)
	logFiles := []string{"server.log", "postgres_engine.log", "updater.log"}
	for _, fname := range logFiles {
		fullPath := filepath.Join(logsDir, fname)
		if _, err := os.Stat(fullPath); os.IsNotExist(err) {
			continue
		}

		lines, err := readLastLinesNonExclusive(fullPath, 500)
		if err != nil {
			log.Printf("⚠️ [Diagnostics] Could not read %s: %v", fname, err)
			continue
		}

		sanitized := sanitizeLogs(strings.Join(lines, "\n"))
		_ = addZipFile(fname, []byte(sanitized))
	}

	if err := zipWriter.Close(); err != nil {
		return nil, nil, fmt.Errorf("failed to finalize zip: %w", err)
	}

	return zipBuffer.Bytes(), sysInfo, nil
}

// ExportToDesktop writes the diagnostics zip file to the user's Desktop (and OneDrive Desktop)
// and returns the primary file path and the raw zip bytes for browser download.
func (s *DiagnosticsService) ExportToDesktop(userNote string) (string, []byte, error) {
	zipData, _, err := s.BuildDiagnosticBundle(userNote)
	if err != nil {
		return "", nil, err
	}

	userProfile := os.Getenv("USERPROFILE")
	if userProfile == "" {
		userProfile = "."
	}

	timestamp := time.Now().Format("20060102_150405")
	fileName := fmt.Sprintf("SmartPower_Support_Logs_%s.zip", timestamp)

	// Collect all possible visible Desktop directories (including OneDrive)
	desktopDirs := []string{filepath.Join(userProfile, "Desktop")}
	for _, envVar := range []string{"OneDrive", "OneDriveConsumer", "OneDriveCommercial"} {
		if od := os.Getenv(envVar); od != "" {
			odDesktop := filepath.Join(od, "Desktop")
			if fi, err := os.Stat(odDesktop); err == nil && fi.IsDir() {
				desktopDirs = append(desktopDirs, odDesktop)
			}
		}
	}

	primaryPath := ""
	for _, dir := range desktopDirs {
		_ = os.MkdirAll(dir, 0755)
		targetPath := filepath.Join(dir, fileName)
		if err := os.WriteFile(targetPath, zipData, 0644); err == nil {
			if primaryPath == "" {
				primaryPath = targetPath
			}
			log.Printf("💾 [Diagnostics] Saved support bundle to: %s", targetPath)
		}
	}

	if primaryPath == "" {
		primaryPath = filepath.Join(userProfile, "Desktop", fileName)
		_ = os.WriteFile(primaryPath, zipData, 0644)
	}

	return primaryPath, zipData, nil
}

// UploadToCloud uploads the zip bundle to Supabase Storage and records an entry in support_diagnostics
func (s *DiagnosticsService) UploadToCloud(userNote string) (*DiagnosticUploadResult, error) {
	zipData, sysInfo, err := s.BuildDiagnosticBundle(userNote)
	if err != nil {
		return nil, err
	}

	timestamp := time.Now().Format("20060102_150405")
	hwid := fmt.Sprintf("%v", sysInfo["hwid"])
	if len(hwid) > 8 {
		hwid = hwid[:8]
	}
	fileName := fmt.Sprintf("diagnostics_%s_%s.zip", hwid, timestamp)
	referenceID := fmt.Sprintf("REF-%s", strings.ToUpper(timestamp))

	// 1. Upload to Supabase Storage bucket 'support-logs'
	storageURL := fmt.Sprintf("%s/storage/v1/object/support-logs/%s", s.supabaseURL, fileName)
	req, err := http.NewRequest("POST", storageURL, bytes.NewReader(zipData))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+s.anonKey)
	req.Header.Set("apikey", s.anonKey)
	req.Header.Set("Content-Type", "application/zip")
	req.Header.Set("x-upsert", "true")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	req = req.WithContext(ctx)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to upload logs bundle to cloud: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("cloud storage upload rejected (HTTP %d): %s", resp.StatusCode, string(respBody))
	}

	publicURL := fmt.Sprintf("%s/storage/v1/object/public/support-logs/%s", s.supabaseURL, fileName)

	// 2. Insert record into support_diagnostics table via REST
	record := map[string]interface{}{
		"reference_id": referenceID,
		"hwid":         sysInfo["hwid"],
		"license_key":  sysInfo["license_key"],
		"station_name": sysInfo["station_name"],
		"app_version":  sysInfo["app_version"],
		"user_note":    userNote,
		"file_name":    fileName,
		"file_url":     publicURL,
		"status":       "PENDING",
	}
	recordBytes, _ := json.Marshal(record)

	tableURL := fmt.Sprintf("%s/rest/v1/support_diagnostics", s.supabaseURL)
	tableReq, err := http.NewRequest("POST", tableURL, bytes.NewReader(recordBytes))
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

	return &DiagnosticUploadResult{
		Success:     true,
		ReferenceID: referenceID,
		FileName:    fileName,
		DownloadURL: publicURL,
		Message:     fmt.Sprintf("تم إرسال تقرير الدعم الفني بنجاح بالرقم المرجعي: %s", referenceID),
	}, nil
}
