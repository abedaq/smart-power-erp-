package licensing

import (
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
