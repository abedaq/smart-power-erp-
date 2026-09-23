package licensing

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"strings"
	"testing"
	"time"
)

func TestGetMachineHWID(t *testing.T) {
	start := time.Now()
	hwid := GetMachineHWID()
	elapsed := time.Since(start)

	t.Logf("Generated HWID: %s in %v", hwid, elapsed)

	if !strings.HasPrefix(hwid, "HWID-") {
		t.Fatalf("Expected HWID to start with 'HWID-', got %s", hwid)
	}

	parts := strings.Split(hwid, "-")
	if len(parts) != 5 {
		t.Fatalf("Expected 5 segments in HWID, got %d in %s", len(parts), hwid)
	}

	if elapsed > 100*time.Millisecond {
		t.Fatalf("HWID generation took too long: %v (expected < 100ms)", elapsed)
	}
}

func TestTokenHMACValidation(t *testing.T) {
	hwid := "HWID-TEST-1234-5678-ABCD"
	payloadStr := "SP-2026-TEST|" + hwid + "|Test Client|1893456000|14|1700000000"
	payloadB64 := base64.StdEncoding.EncodeToString([]byte(payloadStr))

	// 1. Valid Signature with Master Key
	mac := hmac.New(sha256.New, []byte(MasterLicenseSigningSecret))
	mac.Write([]byte(payloadStr))
	validSig := hex.EncodeToString(mac.Sum(nil))
	validToken := payloadB64 + "." + validSig

	payload, err := parseAndValidateToken(validToken, hwid)
	if err != nil {
		t.Fatalf("Expected valid token to pass, got error: %v", err)
	}
	if payload.LicenseKey != "SP-2026-TEST" {
		t.Fatalf("Expected license key SP-2026-TEST, got %s", payload.LicenseKey)
	}

	// 2. Tampered Payload with original signature
	tamperedPayloadStr := "SP-2026-HACKED|" + hwid + "|Hacked Client|2893456000|99|1700000000"
	tamperedPayloadB64 := base64.StdEncoding.EncodeToString([]byte(tamperedPayloadStr))
	tamperedToken := tamperedPayloadB64 + "." + validSig

	_, err = parseAndValidateToken(tamperedToken, hwid)
	if err == nil {
		t.Fatalf("Expected tampered token to fail HMAC verification, but it passed!")
	}

	// 3. Fake Signature
	fakeToken := payloadB64 + ".0000000000000000000000000000000000000000000000000000000000000000"
	_, err = parseAndValidateToken(fakeToken, hwid)
	if err == nil {
		t.Fatalf("Expected fake signature to fail, but it passed!")
	}
}
