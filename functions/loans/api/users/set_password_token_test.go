package users

import (
	"regexp"
	"testing"
	"time"
)

var hex64 = regexp.MustCompile(`^[0-9a-f]{64}$`)

func TestGenerateSetPasswordToken_ShapeAndConsistency(t *testing.T) {
	raw, hash, err := GenerateSetPasswordToken()
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if raw == "" {
		t.Fatalf("expected non-empty raw token")
	}
	if !hex64.MatchString(hash) {
		t.Fatalf("expected 64-char lowercase hex hash, got %q", hash)
	}
	// The returned hash must be the SHA-256 hex of the returned raw token.
	if got := HashSetPasswordToken(raw); got != hash {
		t.Fatalf("hash mismatch: GenerateSetPasswordToken=%q HashSetPasswordToken(raw)=%q", hash, got)
	}
}

func TestGenerateSetPasswordToken_Unique(t *testing.T) {
	raw1, hash1, err1 := GenerateSetPasswordToken()
	raw2, hash2, err2 := GenerateSetPasswordToken()
	if err1 != nil || err2 != nil {
		t.Fatalf("unexpected errs: %v %v", err1, err2)
	}
	if raw1 == raw2 {
		t.Fatalf("expected two distinct raw tokens, both were %q", raw1)
	}
	if hash1 == hash2 {
		t.Fatalf("expected two distinct hashes, both were %q", hash1)
	}
}

func TestHashSetPasswordToken_Deterministic(t *testing.T) {
	const raw = "fixed-raw-token"
	if HashSetPasswordToken(raw) != HashSetPasswordToken(raw) {
		t.Fatalf("HashSetPasswordToken must be deterministic for the same input")
	}
	if !hex64.MatchString(HashSetPasswordToken(raw)) {
		t.Fatalf("expected a 64-char hex hash")
	}
}

func TestSetPasswordTokenTTL_Is24h(t *testing.T) {
	if setPasswordTokenTTL != 24*time.Hour {
		t.Fatalf("expected 24h TTL, got %v", setPasswordTokenTTL)
	}
}
