package services

import (
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestHash(t *testing.T) {
	h, err := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("BCRYPT_HASH: %s", string(h))

	err = bcrypt.CompareHashAndPassword(h, []byte("admin123"))
	if err != nil {
		t.Fatalf("Compare failed: %v", err)
	}
}