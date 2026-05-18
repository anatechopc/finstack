package users_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// stubOtp returns a closure that produces a fixed (hash, otp) pair plus a call
// counter. Tests assert on call count and the values appearing in the entry +
// result.
func stubOtp(hash, otp string) (func() (string, string, error), *int) {
	var calls int
	return func() (string, string, error) {
		calls++
		return hash, otp, nil
	}, &calls
}

// buildDeps wires a stub OTP generator and pinned clock alongside the
// caller-supplied fakes. Centralised so each test only declares the inputs
// it cares about.
func buildDeps(
	now time.Time,
	hash, otp string,
	user *fakes.UserReader,
	authEmail *fakes.AuthEmailReader,
	otpWriter *fakes.OtpWriter,
	emailSender *fakes.EmailSender,
) (users.RequestOtpDeps, *int) {
	gen, calls := stubOtp(hash, otp)
	return users.RequestOtpDeps{
		GenerateOtp:      gen,
		ReadUser:         user.Read,
		GetAuthUserEmail: authEmail.Read,
		WriteOtp:         otpWriter.Write,
		SendEmail:        emailSender.Send,
		Now:              func() time.Time { return now },
	}, calls
}

func TestRequestOtpCore_EmailObjective_ReadsRecipientFromAuth(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)

	userReader := &fakes.UserReader{} // intentionally empty: email path must not need it
	authEmail := &fakes.AuthEmailReader{Emails: map[string]string{
		"user-123": "user@example.com",
	}}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, authEmail, otpWriter, emailSender)

	res, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
		Subdomain: "dev.",
	}, deps)
	if err != nil {
		t.Fatalf("RequestOtpCore returned error: %v", err)
	}

	if len(emailSender.Sends) != 1 {
		t.Fatalf("expected exactly 1 email send, got %d", len(emailSender.Sends))
	}
	send := emailSender.Sends[0]
	if len(send.Recipients) != 1 || send.Recipients[0] != "user@example.com" {
		t.Errorf("expected recipient [user@example.com], got %v", send.Recipients)
	}
	if !strings.Contains(send.Subject, "Verify your email") {
		t.Errorf("unexpected subject: %q", send.Subject)
	}
	if !strings.Contains(send.Body, "111111") {
		t.Errorf("email body missing OTP, got: %s", send.Body)
	}

	// Firestore must NOT be consulted on the email path — this is the
	// regression test for PR #53 where a missing userDetails["email"]
	// caused "<nil>" recipients.
	if len(userReader.ReadCalls) != 0 {
		t.Errorf("expected ReadUser to be skipped on email path, got %d calls: %v", len(userReader.ReadCalls), userReader.ReadCalls)
	}

	if res.Hash != "h-1" {
		t.Errorf("expected result.Hash=h-1, got %q", res.Hash)
	}
	if !strings.Contains(res.RedirectURL, "h-1") {
		t.Errorf("expected redirect URL to contain hash, got %q", res.RedirectURL)
	}
	if !strings.HasPrefix(res.RedirectURL, "dev.") {
		t.Errorf("expected redirect URL to start with subdomain, got %q", res.RedirectURL)
	}
}

func TestRequestOtpCore_EmailObjective_NoAuthEmail_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	authEmail := &fakes.AuthEmailReader{Emails: map[string]string{"user-123": ""}}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, authEmail, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps)
	if !errors.Is(err, users.ErrAuthUserMissingEmail) {
		t.Fatalf("expected ErrAuthUserMissingEmail, got %v", err)
	}
	if len(emailSender.Sends) != 0 {
		t.Errorf("expected no email send on missing-email error, got %d", len(emailSender.Sends))
	}
}

func TestRequestOtpCore_EmailObjective_AuthFetchError_Propagates(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	authFetchErr := errors.New("auth: backend unavailable")
	authEmail := &fakes.AuthEmailReader{Err: authFetchErr}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, authEmail, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps)
	if !errors.Is(err, authFetchErr) {
		t.Fatalf("expected auth fetch error to propagate, got %v", err)
	}
	if len(emailSender.Sends) != 0 {
		t.Errorf("expected no email send when auth fetch fails, got %d", len(emailSender.Sends))
	}
}

func TestRequestOtpCore_MobileObjective_ReadsMobileNumberFromFirestore(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+639171234567"},
	}}
	authEmail := &fakes.AuthEmailReader{}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-mob", "222222", userReader, authEmail, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps)
	if err != nil {
		t.Fatalf("RequestOtpCore returned error: %v", err)
	}

	if len(otpWriter.Writes) != 1 {
		t.Fatalf("expected exactly 1 RTDB write, got %d", len(otpWriter.Writes))
	}
	entry := otpWriter.Writes[0].Entry
	if got, _ := entry["phone"].(string); got != "+639171234567" {
		t.Errorf("expected entry.phone=+639171234567, got %v", entry["phone"])
	}
	if got, _ := entry["sms_status"].(string); got != "pending" {
		t.Errorf("expected entry.sms_status=pending, got %v", entry["sms_status"])
	}
	if msg, _ := entry["message"].(string); !strings.Contains(msg, "222222") {
		t.Errorf("expected SMS message to contain OTP, got %v", entry["message"])
	}

	// Auth must NOT be hit on the mobile path.
	if len(authEmail.ReadCalls) != 0 {
		t.Errorf("expected GetAuthUserEmail to be skipped on mobile path, got %d calls", len(authEmail.ReadCalls))
	}
	if len(emailSender.Sends) != 0 {
		t.Errorf("expected no email send on mobile path, got %d", len(emailSender.Sends))
	}
}

func TestRequestOtpCore_MobileObjective_MissingMobileNumber_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {}, // no mobile_number field
	}}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AuthEmailReader{}, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps)
	if !errors.Is(err, users.ErrMobileNumberMissing) {
		t.Fatalf("expected ErrMobileNumberMissing, got %v", err)
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("expected no RTDB write when mobile_number missing, got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_MobileObjective_UserNotFound_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{} // no users at all
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps)
	if !errors.Is(err, users.ErrUserNotFound) {
		t.Fatalf("expected ErrUserNotFound, got %v", err)
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("expected no RTDB write when user missing, got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_InvalidObjective_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AuthEmailReader{}, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "something_unknown",
	}, deps)
	if !errors.Is(err, users.ErrInvalidObjective) {
		t.Fatalf("expected ErrInvalidObjective, got %v", err)
	}
	if len(otpWriter.Writes) != 0 || len(emailSender.Sends) != 0 {
		t.Errorf("expected no side effects on invalid objective, got %d writes, %d sends", len(otpWriter.Writes), len(emailSender.Sends))
	}
}

func TestRequestOtpCore_DefaultReason_Email(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	got, _ := otpWriter.Writes[0].Entry["reason"].(string)
	if got != "email_verification" {
		t.Errorf("expected default reason email_verification, got %q", got)
	}
}

func TestRequestOtpCore_DefaultReason_Mobile(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+1"},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	got, _ := otpWriter.Writes[0].Entry["reason"].(string)
	if got != "mobile_verification" {
		t.Errorf("expected default reason mobile_verification, got %q", got)
	}
}

func TestRequestOtpCore_ReasonOverride_Persists(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+1"},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
		Reason:    "payment",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	got, _ := otpWriter.Writes[0].Entry["reason"].(string)
	if got != "payment" {
		t.Errorf("expected reason override 'payment' to persist, got %q", got)
	}
}

func TestRequestOtpCore_TargetUserIDOverride(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-456": {"mobile_number": "+2"},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:       "user-123", // caller
		TargetUserID: "user-456", // target (e.g., teller acting for borrower)
		Objective:    "mobile_number",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}

	if len(userReader.ReadCalls) != 1 || userReader.ReadCalls[0] != "user-456" {
		t.Errorf("expected ReadUser to be called with target uid, got %v", userReader.ReadCalls)
	}

	entry := otpWriter.Writes[0].Entry
	if got, _ := entry["userId"].(string); got != "user-456" {
		t.Errorf("expected entry.userId=user-456, got %v", entry["userId"])
	}
	if got, _ := entry["requested_by"].(string); got != "user-123" {
		t.Errorf("expected entry.requested_by=user-123 (caller), got %v", entry["requested_by"])
	}
}

func TestRequestOtpCore_RTDBWriteContents(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	authEmail := &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "hash-xyz", "654321", &fakes.UserReader{}, authEmail, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}

	if otpWriter.Writes[0].Hash != "hash-xyz" {
		t.Errorf("expected write hash=hash-xyz, got %q", otpWriter.Writes[0].Hash)
	}
	entry := otpWriter.Writes[0].Entry
	expectStringField(t, entry, "id", "hash-xyz")
	expectStringField(t, entry, "userId", "user-123")
	expectStringField(t, entry, "otp", "654321")
	expectStringField(t, entry, "objective", "email")
	expectStringField(t, entry, "reason", "email_verification")
	expectStringField(t, entry, "requested_by", "user-123")

	wantExpire := now.Add(5 * time.Minute).UnixMilli()
	if got, _ := entry["expire_at"].(int64); got != wantExpire {
		t.Errorf("expected expire_at=%d (now+5m millis), got %v (%T)", wantExpire, entry["expire_at"], entry["expire_at"])
	}
	wantCreated := now.UnixMilli()
	if got, _ := entry["created_at"].(int64); got != wantCreated {
		t.Errorf("expected created_at=%d, got %v", wantCreated, entry["created_at"])
	}
	if got, _ := entry["updated_at"].(int64); got != wantCreated {
		t.Errorf("expected updated_at=%d, got %v", wantCreated, entry["updated_at"])
	}
}

func TestRequestOtpCore_GenerateOtpCalledExactlyOnce(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	deps, calls := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	if *calls != 1 {
		t.Errorf("expected GenerateOtp called exactly 1 time, got %d", *calls)
	}
}

func TestRequestOtpCore_RTDBWriteFails_PropagatesAndSkipsEmail(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	writeErr := errors.New("rtdb: permission denied")
	otpWriter := &fakes.OtpWriter{Err: writeErr}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps)
	if !errors.Is(err, writeErr) {
		t.Fatalf("expected write error to propagate, got %v", err)
	}
	if len(emailSender.Sends) != 0 {
		t.Errorf("expected no email send when RTDB write failed, got %d", len(emailSender.Sends))
	}
}

// expectStringField asserts the entry has the given key with the given string
// value. Reports a single error line including actual type when the
// assertion fails, so the caller can spot type mismatches (e.g., int vs
// string) without writing the boilerplate manually.
func expectStringField(t *testing.T, entry map[string]any, key, want string) {
	t.Helper()
	got, ok := entry[key].(string)
	if !ok {
		t.Errorf("expected entry[%q] to be string, got %T (%v)", key, entry[key], entry[key])
		return
	}
	if got != want {
		t.Errorf("expected entry[%q]=%q, got %q", key, want, got)
	}
}
