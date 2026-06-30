package users

import (
	"errors"
	"testing"
)

// nowMillis is a fixed reference "now" for the evaluator tests.
const evalNowMillis int64 = 1_700_000_000_000

func TestEvaluateSetPasswordToken_ValidDoc_ReturnsUidEmail(t *testing.T) {
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000), // now + 1h
		"uid":        "uid-1",
		"email":      "jane@example.com",
		// used_at absent → not yet consumed.
	}

	uid, email, err := evaluateSetPasswordToken(data, evalNowMillis)
	if err != nil {
		t.Fatalf("expected no error for a valid doc, got %v", err)
	}
	if uid != "uid-1" || email != "jane@example.com" {
		t.Fatalf("expected (uid-1, jane@example.com), got (%q, %q)", uid, email)
	}
}

func TestEvaluateSetPasswordToken_FloatExpiry_Valid(t *testing.T) {
	// Firestore numbers can arrive as float64; toInt64 must accept them.
	data := map[string]any{
		"expires_at": float64(evalNowMillis + int64(60*60*1000)),
		"uid":        "uid-1",
		"email":      "jane@example.com",
	}

	uid, email, err := evaluateSetPasswordToken(data, evalNowMillis)
	if err != nil {
		t.Fatalf("expected no error for a float64 expiry, got %v", err)
	}
	if uid != "uid-1" || email != "jane@example.com" {
		t.Fatalf("expected (uid-1, jane@example.com), got (%q, %q)", uid, email)
	}
}

func TestEvaluateSetPasswordToken_AlreadyUsed_Rejected(t *testing.T) {
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000),
		"uid":        "uid-1",
		"email":      "jane@example.com",
		"used_at":    evalNowMillis - 1000, // present & non-nil → consumed
	}

	uid, email, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for used token, got %v", err)
	}
	if uid != "" || email != "" {
		t.Fatalf("expected empty uid/email on rejection, got (%q, %q)", uid, email)
	}
}

func TestEvaluateSetPasswordToken_Expired_Rejected(t *testing.T) {
	// expires_at <= now → expired.
	data := map[string]any{
		"expires_at": evalNowMillis, // exactly now → rejected (<=)
		"uid":        "uid-1",
		"email":      "jane@example.com",
	}

	_, _, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for expired token, got %v", err)
	}
}

func TestEvaluateSetPasswordToken_MissingExpiry_Rejected(t *testing.T) {
	// No expires_at at all → !ok branch → fail closed.
	data := map[string]any{
		"uid":   "uid-1",
		"email": "jane@example.com",
	}

	_, _, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for missing expiry, got %v", err)
	}
}

func TestEvaluateSetPasswordToken_NonNumericExpiry_Rejected(t *testing.T) {
	// A Firestore Timestamp (or any non-numeric) would arrive as a non-int64
	// type; toInt64 returns ok=false and the evaluator must fail closed rather
	// than treat it as expired-by-default with a usable token.
	type fakeTimestamp struct{ Seconds int64 }
	cases := map[string]any{
		"string": "2026-01-01T00:00:00Z",
		"struct": fakeTimestamp{Seconds: 123},
	}
	for name, expiry := range cases {
		t.Run(name, func(t *testing.T) {
			data := map[string]any{
				"expires_at": expiry,
				"uid":        "uid-1",
				"email":      "jane@example.com",
			}
			_, _, err := evaluateSetPasswordToken(data, evalNowMillis)
			if !errors.Is(err, ErrInvalidSetPasswordToken) {
				t.Fatalf("expected ErrInvalidSetPasswordToken for %s expiry, got %v", name, err)
			}
		})
	}
}

func TestEvaluateSetPasswordToken_MissingUid_RejectedNoUid(t *testing.T) {
	// Valid expiry but no uid → fail closed, and never leak a uid.
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000),
		"email":      "jane@example.com",
		// uid absent
	}

	uid, _, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for missing uid, got %v", err)
	}
	if uid != "" {
		t.Fatalf("expected no uid returned on rejection, got %q", uid)
	}
}

func TestEvaluateSetPasswordToken_EmptyUid_RejectedNoUid(t *testing.T) {
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000),
		"uid":        "",
		"email":      "jane@example.com",
	}

	uid, _, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for empty uid, got %v", err)
	}
	if uid != "" {
		t.Fatalf("expected no uid returned on rejection, got %q", uid)
	}
}

func TestEvaluateSetPasswordToken_MissingEmail_Rejected(t *testing.T) {
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000),
		"uid":        "uid-1",
		// email absent
	}

	_, email, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for missing email, got %v", err)
	}
	if email != "" {
		t.Fatalf("expected no email returned on rejection, got %q", email)
	}
}

func TestEvaluateSetPasswordToken_EmptyEmail_Rejected(t *testing.T) {
	data := map[string]any{
		"expires_at": evalNowMillis + int64(60*60*1000),
		"uid":        "uid-1",
		"email":      "",
	}

	_, _, err := evaluateSetPasswordToken(data, evalNowMillis)
	if !errors.Is(err, ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken for empty email, got %v", err)
	}
}
