package users

import (
	"sort"
	"strings"
	"testing"
	"time"
)

func TestBuildSetPasswordLink_Subdomains(t *testing.T) {
	cases := map[string]struct {
		subdomain string
		raw       string
		want      string
	}{
		"dev":  {"dev.", "abc", "https://dev.loooans.com/set-password?token=abc"},
		"stg":  {"stg.", "abc", "https://stg.loooans.com/set-password?token=abc"},
		"prod": {"", "abc", "https://loooans.com/set-password?token=abc"},
	}
	for name, c := range cases {
		if got := buildSetPasswordLink(c.subdomain, c.raw); got != c.want {
			t.Errorf("%s: buildSetPasswordLink(%q,%q) = %q, want %q", name, c.subdomain, c.raw, got, c.want)
		}
	}
}

func TestBuildSetPasswordLink_EscapesToken(t *testing.T) {
	got := buildSetPasswordLink("", "ab/c+d")

	if !strings.HasPrefix(got, "https://loooans.com/set-password?token=") {
		t.Fatalf("unexpected host/path: %q", got)
	}
	// QueryEscape must be applied: '/' → %2F, '+' → %2B, and no raw '/'/'+'
	// should survive in the token segment.
	token := strings.TrimPrefix(got, "https://loooans.com/set-password?token=")
	if !strings.Contains(token, "%2F") {
		t.Errorf("expected '/' to be escaped as %%2F in token, got %q", token)
	}
	if !strings.Contains(token, "%2B") {
		t.Errorf("expected '+' to be escaped as %%2B in token, got %q", token)
	}
	if strings.ContainsAny(token, "/+") {
		t.Errorf("token segment must not contain raw '/' or '+': %q", token)
	}
}

// TestNewSetPasswordTokenDoc_LocksConsumerFields locks the exact field names and
// shape the set_password.go consumer (buildRealSetPasswordDeps → ConsumeToken)
// reads: it queries Where("token_hash","==",hash) and reads used_at / expires_at
// / uid / email. If this test fails because a key changed, the consume path is
// broken — fix the producer, do not loosen the test.
func TestNewSetPasswordTokenDoc_LocksConsumerFields(t *testing.T) {
	now := time.Date(2026, 6, 23, 12, 0, 0, 0, time.UTC)
	doc := newSetPasswordTokenDoc("hash123", "uid456", "user@example.com", now)

	wantKeys := []string{"created_at", "email", "expires_at", "token_hash", "uid", "used_at"}
	gotKeys := make([]string, 0, len(doc))
	for k := range doc {
		gotKeys = append(gotKeys, k)
	}
	sort.Strings(gotKeys)
	if strings.Join(gotKeys, ",") != strings.Join(wantKeys, ",") {
		t.Fatalf("doc keys = %v, want exactly %v", gotKeys, wantKeys)
	}

	// used_at must be absent-equivalent (nil) for a fresh token: the consumer
	// rejects the token only when used_at is present AND non-nil.
	if doc["used_at"] != nil {
		t.Errorf("fresh token used_at = %v, want nil", doc["used_at"])
	}

	// Values round-trip the inputs.
	if doc["token_hash"] != "hash123" {
		t.Errorf("token_hash = %v, want hash123", doc["token_hash"])
	}
	if doc["uid"] != "uid456" {
		t.Errorf("uid = %v, want uid456", doc["uid"])
	}
	if doc["email"] != "user@example.com" {
		t.Errorf("email = %v, want user@example.com", doc["email"])
	}

	// Timestamps are int64 millis since epoch; the TTL is exactly setPasswordTokenTTL.
	createdAt, ok := doc["created_at"].(int64)
	if !ok {
		t.Fatalf("created_at = %T, want int64", doc["created_at"])
	}
	expiresAt, ok := doc["expires_at"].(int64)
	if !ok {
		t.Fatalf("expires_at = %T, want int64", doc["expires_at"])
	}
	if createdAt != now.UnixMilli() {
		t.Errorf("created_at = %d, want %d", createdAt, now.UnixMilli())
	}
	if expiresAt-createdAt != setPasswordTokenTTL.Milliseconds() {
		t.Errorf("expires_at - created_at = %d, want %d (setPasswordTokenTTL)", expiresAt-createdAt, setPasswordTokenTTL.Milliseconds())
	}
}
