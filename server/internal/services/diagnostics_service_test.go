package services

import (
	"strings"
	"testing"
)

func TestSanitizeLogs(t *testing.T) {
	rawLog := `2026-09-11 07:00:00 [INFO] Request Authorization: Bearer eyJhbGciOiJIUzI1Ni.secret_payload.123
2026-09-11 07:00:01 [DEBUG] Connecting to postgres://postgres:SecretDBPass123@localhost:15432/smartpower
2026-09-11 07:00:02 [INFO] Login attempt with {"username": "admin", "password": "SuperSecretPassword!"}
2026-09-11 07:00:03 [ERROR] Database connection failed: connection refused`

	sanitized := sanitizeLogs(rawLog)

	if strings.Contains(sanitized, "eyJhbGciOiJIUzI1Ni") {
		t.Errorf("SanitizeLogs failed to redact Bearer token")
	}
	if strings.Contains(sanitized, "SecretDBPass123") {
		t.Errorf("SanitizeLogs failed to redact DB password")
	}
	if strings.Contains(sanitized, "SuperSecretPassword!") {
		t.Errorf("SanitizeLogs failed to redact JSON password")
	}
	if !strings.Contains(sanitized, "Database connection failed") {
		t.Errorf("SanitizeLogs accidentally stripped normal error log")
	}
}
