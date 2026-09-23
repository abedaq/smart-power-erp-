package crypto

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"testing"
)

func TestVerifier_ValidSignature(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("Failed to generate keypair: %v", err)
	}

	pubHex := hex.EncodeToString(pub)
	verifier, err := NewVerifierWithKey(pubHex)
	if err != nil {
		t.Fatalf("Failed to create verifier: %v", err)
	}

	cmdType := "RUN_SQL_PATCH"
	hwid := "HWID-TEST-1234-ABCD"
	sqlContent := "UPDATE customers SET status = 'ACTIVE' WHERE id = 101;"

	canonicalMsg := BuildCanonicalMessage(cmdType, hwid, sqlContent)
	sigBytes := ed25519.Sign(priv, canonicalMsg)
	sigHex := hex.EncodeToString(sigBytes)

	if !verifier.VerifySignature(cmdType, hwid, sqlContent, sigHex) {
		t.Errorf("Expected valid signature to verify successfully")
	}

	// Whitespace trimming test
	paddedSQL := "   \n\t" + sqlContent + "  \r\n"
	if !verifier.VerifySignature(cmdType, hwid, paddedSQL, sigHex) {
		t.Errorf("Expected trimmed whitespace in SQL to still verify")
	}
}

func TestVerifier_TamperedPayload(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("Failed to generate keypair: %v", err)
	}

	pubHex := hex.EncodeToString(pub)
	verifier, err := NewVerifierWithKey(pubHex)
	if err != nil {
		t.Fatalf("Failed to create verifier: %v", err)
	}

	cmdType := "RUN_SQL_PATCH"
	hwid := "HWID-TEST-1234-ABCD"
	sqlContent := "UPDATE invoices SET paid_amount = 5000 WHERE id = 10;"

	canonicalMsg := BuildCanonicalMessage(cmdType, hwid, sqlContent)
	sigBytes := ed25519.Sign(priv, canonicalMsg)
	sigHex := hex.EncodeToString(sigBytes)

	// Tampering SQL content
	tamperedSQL := "UPDATE invoices SET paid_amount = 9000 WHERE id = 10;"
	if verifier.VerifySignature(cmdType, hwid, tamperedSQL, sigHex) {
		t.Errorf("Expected tampered SQL to FAIL verification")
	}

	// Tampering HWID (Replay attack on another station)
	wrongHWID := "HWID-DIFFERENT-STATION-9999"
	if verifier.VerifySignature(cmdType, wrongHWID, sqlContent, sigHex) {
		t.Errorf("Expected wrong HWID replay attack to FAIL verification")
	}

	// Tampering Command Type
	if verifier.VerifySignature("FORCE_BACKUP", hwid, sqlContent, sigHex) {
		t.Errorf("Expected wrong command type to FAIL verification")
	}
}

func TestVerifier_MasterKeyIntegrity(t *testing.T) {
	verifier, err := NewVerifier()
	if err != nil {
		t.Fatalf("Failed to load master public key verifier: %v", err)
	}
	if verifier == nil {
		t.Fatalf("Verifier instance is nil")
	}
}
