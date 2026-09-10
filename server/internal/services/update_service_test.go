package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"smartpower/internal/config"
)

func TestCompareVersions(t *testing.T) {
	tests := []struct {
		v1       string
		v2       string
		expected int
	}{
		{"1.0.0", "1.0.0", 0},
		{"1.0.1", "1.0.0", 1},
		{"1.0.0", "1.0.1", -1},
		{"v1.2.0", "1.1.9", 1},
		{"1.10.0", "1.2.0", 1},
		{"2.0.0", "1.99.99", 1},
		{"1.0.0", "2.0.0", -1},
		{"1.0", "1.0.0", 0},
		{"1.0.0.1", "1.0.0", 1},
		{"v1.0.5", "v1.0.4", 1},
	}

	for _, tt := range tests {
		got := CompareVersions(tt.v1, tt.v2)
		if got != tt.expected {
			t.Errorf("CompareVersions(%q, %q) = %d; want %d", tt.v1, tt.v2, got, tt.expected)
		}
	}
}

func TestCheckForUpdates(t *testing.T) {
	// Mock manifest server
	manifest := UpdateManifest{
		Version:     "1.0.5",
		DownloadURL: "https://example.com/SmartPowerERP.exe",
		SHA256:      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		Changelog:   "تحسينات جديدة في الأداء",
		Mandatory:   false,
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(manifest)
	}))
	defer server.Close()

	cfg := &config.Config{}
	svc := NewUpdateService(cfg, nil, nil)
	svc.SetManifestURL(server.URL)
	svc.SetCurrentVersion("1.0.0")

	res, err := svc.CheckForUpdates()
	if err != nil {
		t.Fatalf("CheckForUpdates failed: %v", err)
	}

	if !res.HasUpdate {
		t.Errorf("Expected HasUpdate=true for 1.0.5 > 1.0.0, got false")
	}
	if res.LatestVersion != "1.0.5" {
		t.Errorf("Expected LatestVersion=1.0.5, got %s", res.LatestVersion)
	}
	if res.CurrentVersion != "1.0.0" {
		t.Errorf("Expected CurrentVersion=1.0.0, got %s", res.CurrentVersion)
	}

	// Test when already on latest version
	svc.SetCurrentVersion("1.0.5")
	res2, err := svc.CheckForUpdates()
	if err != nil {
		t.Fatalf("CheckForUpdates failed: %v", err)
	}
	if res2.HasUpdate {
		t.Errorf("Expected HasUpdate=false for 1.0.5 == 1.0.5, got true")
	}
}

func TestDownloadUpdateWithSHA256Verification(t *testing.T) {
	content := []byte("SIMULATED_NEW_BINARY_CONTENT_2026_TEST_SMARTPOWER")
	hasher := sha256.New()
	hasher.Write(content)
	correctHash := hex.EncodeToString(hasher.Sum(nil))

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(content)
	}))
	defer server.Close()

	cfg := &config.Config{}
	svc := NewUpdateService(cfg, nil, nil)

	// 1. Success case with valid SHA256
	filePath, err := svc.DownloadUpdate(context.Background(), server.URL, correctHash)
	if err != nil {
		t.Fatalf("DownloadUpdate with valid hash failed: %v", err)
	}
	defer os.Remove(filePath)

	downloadedBytes, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Failed to read downloaded file: %v", err)
	}
	if string(downloadedBytes) != string(content) {
		t.Errorf("Downloaded content mismatch")
	}

	p := svc.GetProgress()
	if p.Status != "ready" || p.Progress != 100 {
		t.Errorf("Expected status='ready', progress=100, got status=%s, progress=%.1f", p.Status, p.Progress)
	}

	// 2. Failure case with corrupted / mismatched SHA256
	wrongHash := "1111222233334444555566667777888899990000aaaaabbbbccccddddeeeeffff"
	_, err = svc.DownloadUpdate(context.Background(), server.URL, wrongHash)
	if err == nil {
		t.Errorf("Expected error for SHA256 mismatch, got nil")
	}
	pErr := svc.GetProgress()
	if pErr.Status != "error" {
		t.Errorf("Expected status='error' after SHA256 mismatch, got %s", pErr.Status)
	}
}

func TestCriticalDataSafetyGuards(t *testing.T) {
	cfg := &config.Config{}
	svc := NewUpdateService(cfg, nil, nil)

	// Applying update with empty download path should fail safely without affecting disk
	err := svc.ApplyUpdate("")
	if err == nil {
		t.Errorf("Expected ApplyUpdate to fail safely when no file is downloaded")
	}

	// Non-existent downloaded file
	err = svc.ApplyUpdate(filepath.Join(os.TempDir(), "non_existent_binary_file_12345.exe"))
	if err == nil {
		t.Errorf("Expected ApplyUpdate to fail safely for non-existent file")
	}
}

func TestMinVersionEnforcement(t *testing.T) {
	manifest := UpdateManifest{
		Version:     "2.0.0",
		MinVersion:  "1.5.0",
		DownloadURL: "https://example.com/SmartPowerERP.exe",
		Mandatory:   false, // Even if false, current version 1.0.0 < MinVersion 1.5.0 forces mandatory
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(manifest)
	}))
	defer server.Close()

	cfg := &config.Config{}
	svc := NewUpdateService(cfg, nil, nil)
	svc.SetManifestURL(server.URL)
	svc.SetCurrentVersion("1.0.0")

	res, err := svc.CheckForUpdates()
	if err != nil {
		t.Fatalf("CheckForUpdates failed: %v", err)
	}

	if !res.HasUpdate {
		t.Errorf("Expected HasUpdate=true")
	}
	if !res.Mandatory {
		t.Errorf("Expected Mandatory=true because current 1.0.0 < min_version 1.5.0")
	}
}

func TestEventHubUpdateProgressBroadcast(t *testing.T) {
	eh := NewEventHub()
	ch, unsub := eh.Subscribe()
	defer unsub()

	cfg := &config.Config{}
	svc := NewUpdateService(cfg, eh, nil)

	// Trigger progress update
	svc.mu.Lock()
	svc.progress.Status = "downloading"
	svc.progress.Progress = 50.0
	svc.progress.BytesReceived = 5000
	svc.progress.TotalBytes = 10000
	svc.mu.Unlock()
	svc.emitProgressEvent()

	select {
	case event := <-ch:
		if event.Type != "system:update_progress" {
			t.Errorf("Expected event type 'system:update_progress', got '%s'", event.Type)
		}
	default:
		t.Errorf("Expected to receive broadcasted system:update_progress event")
	}
}

