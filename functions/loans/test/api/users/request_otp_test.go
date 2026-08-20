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
	address *fakes.AddressReader,
	authEmail *fakes.AuthEmailReader,
	otpWriter *fakes.OtpWriter,
	emailSender *fakes.EmailSender,
) (users.RequestOtpDeps, *int) {
	gen, calls := stubOtp(hash, otp)
	return users.RequestOtpDeps{
		GenerateOtp:      gen,
		ReadUser:         user.Read,
		ReadUserAddress:  address.Read,
		GetAuthUserEmail: authEmail.Read,
		WriteOtp:         otpWriter.Write,
		SendEmail:        emailSender.Send,
		Now:              func() time.Time { return now },
	}, calls
}

func TestRequestOtpCore_EmailObjective_ReadsRecipientFromAuth(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)

	userReader := &fakes.UserReader{} // intentionally empty: email path must not need it
	addressReader := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	authEmail := &fakes.AuthEmailReader{Emails: map[string]string{
		"user-123": "user@example.com",
	}}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, addressReader, authEmail, otpWriter, emailSender)

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
	if len(addressReader.ReadCalls) != 0 {
		t.Errorf("expected ReadUserAddress to be skipped on email path, got %d calls", len(addressReader.ReadCalls))
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
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, authEmail, otpWriter, emailSender)

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
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, authEmail, otpWriter, emailSender)

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
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	authEmail := &fakes.AuthEmailReader{}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-mob", "222222", userReader, address, authEmail, otpWriter, emailSender)

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
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{}, otpWriter, emailSender)

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
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

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

func TestRequestOtpCore_MobileObjective_ReadUserTransportError_Propagates(t *testing.T) {
	// Distinguishes "user genuinely not found" (Core maps to ErrUserNotFound)
	// from "Firestore network or permission failure" (Core must propagate
	// the underlying error so the HTTP layer emits a 500, not a 400). The
	// adapter's ReadUser maps Firestore codes.NotFound to (nil, nil) before
	// reaching Core, so anything Core sees as err != nil is real transport
	// breakage.
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	transportErr := errors.New("firestore: rpc deadline exceeded")
	userReader := &fakes.UserReader{Err: transportErr}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps)
	if !errors.Is(err, transportErr) {
		t.Fatalf("expected ReadUser transport error to propagate, got %v", err)
	}
	if errors.Is(err, users.ErrUserNotFound) {
		t.Errorf("expected transport error to NOT be masked as ErrUserNotFound — they map to different status codes")
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("expected no RTDB write when ReadUser fails, got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_InvalidObjective_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{}, otpWriter, emailSender)

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
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, otpWriter, &fakes.EmailSender{})

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
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

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
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

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
		"user-456": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-456": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

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
	deps, _ := buildDeps(now, "hash-xyz", "654321", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, authEmail, otpWriter, &fakes.EmailSender{})

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
	deps, calls := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, &fakes.OtpWriter{}, &fakes.EmailSender{})

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
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}, otpWriter, emailSender)

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

func TestRequestOtpCore_GenerateOtpError_PropagatesWrapped(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpErr := errors.New("otp service: backend down")
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}

	deps := users.RequestOtpDeps{
		GenerateOtp:      func() (string, string, error) { return "", "", otpErr },
		ReadUser:         (&fakes.UserReader{}).Read,
		GetAuthUserEmail: (&fakes.AuthEmailReader{}).Read,
		WriteOtp:         otpWriter.Write,
		SendEmail:        emailSender.Send,
		Now:              func() time.Time { return now },
	}

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps)
	if !errors.Is(err, otpErr) {
		t.Fatalf("expected wrapped otp error, got %v", err)
	}
	if !strings.Contains(err.Error(), "generate otp") {
		t.Errorf("expected error message to mention 'generate otp' for context, got %q", err.Error())
	}
	if len(otpWriter.Writes) != 0 || len(emailSender.Sends) != 0 {
		t.Errorf("expected no side effects on otp generation failure, got %d writes, %d sends", len(otpWriter.Writes), len(emailSender.Sends))
	}
}

func TestRequestOtpCore_SendEmailError_Propagates(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	sendErr := errors.New("microsoft sendMail failed: status=400")
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{Err: sendErr}
	authEmail := &fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}
	deps, _ := buildDeps(now, "h-1", "111111", &fakes.UserReader{}, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, authEmail, otpWriter, emailSender)

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "email",
	}, deps)
	if !errors.Is(err, sendErr) {
		t.Fatalf("expected SendEmail error to propagate, got %v", err)
	}
	if len(otpWriter.Writes) != 1 {
		t.Errorf("expected RTDB write to have happened before SendEmail (so OTP is consumable), got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_EmptyTargetUserID_DefaultsToUserID(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:       "user-123",
		TargetUserID: "", // empty — should default to UserID
		Objective:    "mobile_number",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}

	if len(userReader.ReadCalls) != 1 || userReader.ReadCalls[0] != "user-123" {
		t.Errorf("expected ReadUser to default to caller UID when TargetUserID is empty, got %v", userReader.ReadCalls)
	}
	entry := otpWriter.Writes[0].Entry
	if got, _ := entry["userId"].(string); got != "user-123" {
		t.Errorf("expected entry.userId to default to caller UID, got %v", entry["userId"])
	}
	if got, _ := entry["requested_by"].(string); got != "user-123" {
		t.Errorf("expected entry.requested_by to equal caller, got %v", entry["requested_by"])
	}
}

func TestRequestOtpCore_MobileEntry_HasNilNullableFields(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}

	entry := otpWriter.Writes[0].Entry
	// These three are expected to be present in the entry with literal nil
	// — the SMS gateway uses their presence to detect a fresh OTP it has
	// not processed yet. A missing key or a non-nil sentinel would change
	// gateway behavior.
	for _, k := range []string{"deleted_at", "sent_at", "error"} {
		v, present := entry[k]
		if !present {
			t.Errorf("expected entry[%q] to be present with nil value, key missing", k)
			continue
		}
		if v != nil {
			t.Errorf("expected entry[%q]=nil, got %v (%T)", k, v, v)
		}
	}
}

func TestRequestOtpCore_MobileEntry_HasCorrectObjectiveAndReason(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-mob", "654321", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	if _, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps); err != nil {
		t.Fatalf("err: %v", err)
	}

	entry := otpWriter.Writes[0].Entry
	expectStringField(t, entry, "objective", "mobile_number")
	expectStringField(t, entry, "reason", "mobile_verification")
	expectStringField(t, entry, "id", "h-mob")
	expectStringField(t, entry, "otp", "654321")
}

func TestRequestOtpCore_MobileNumberWrongType_ReturnsError(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	// Firestore returned mobile_number as int (e.g., document was created
	// before string coercion was enforced). The type assertion in Core
	// must not panic; instead it must fall through to ErrMobileNumberMissing.
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": 639171234567},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID:    "user-123",
		Objective: "mobile_number",
	}, deps)
	if !errors.Is(err, users.ErrMobileNumberMissing) {
		t.Fatalf("expected ErrMobileNumberMissing for wrong-typed mobile_number, got %v", err)
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("expected no RTDB write on type mismatch, got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_Mobile_NormalizesPhoneToE164(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if err != nil {
		t.Fatalf("RequestOtpCore returned error: %v", err)
	}
	if len(otpWriter.Writes) != 1 {
		t.Fatalf("expected 1 OTP write, got %d", len(otpWriter.Writes))
	}
	if got := otpWriter.Writes[0].Entry["phone"]; got != "+639175551291" {
		t.Errorf("expected normalized phone +639175551291, got %v", got)
	}
	if len(address.ReadCalls) != 1 || address.ReadCalls[0] != "user-123" {
		t.Errorf("expected address read for user-123, got %v", address.ReadCalls)
	}
}

func TestRequestOtpCore_Mobile_LegacyE164PassesThroughWithoutAddress(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+639175551291"},
	}}
	address := &fakes.AddressReader{} // no address doc at all
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if err != nil {
		t.Fatalf("expected legacy +63 number to pass through, got error: %v", err)
	}
	if got := otpWriter.Writes[0].Entry["phone"]; got != "+639175551291" {
		t.Errorf("expected phone +639175551291, got %v", got)
	}
}

func TestRequestOtpCore_Mobile_MissingAddress_ReturnsErrAddressMissing(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{}, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrAddressMissing) {
		t.Fatalf("expected ErrAddressMissing, got %v", err)
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("no OTP entry may be written on failure, got %d writes", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_Mobile_UnknownCountry_ReturnsErrCountryUnknown(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Narnia"}}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrCountryUnknown) {
		t.Fatalf("expected ErrCountryUnknown, got %v", err)
	}
}

func TestRequestOtpCore_Mobile_InvalidNumber_ReturnsErrPhoneInvalid(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "1234567890"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrPhoneInvalid) {
		t.Fatalf("expected ErrPhoneInvalid, got %v", err)
	}
}

func TestRequestOtpCore_Mobile_AddressReadError_Propagates(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	boom := errors.New("firestore unavailable")
	address := &fakes.AddressReader{Err: boom}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, boom) {
		t.Fatalf("expected transport error to propagate, got %v", err)
	}
}

// The OTP SMS body must contain no email address, URL, or other link-like
// token. Philippine carriers filter link-bearing person-to-person SMS, and a
// filtered message is invisible to us: the gateway requests no delivery report,
// so the radio reports RESULT_OK and the entry is recorded sms_status="sent"
// whether or not it ever reaches the handset.
//
// Established empirically on 2026-08-20 by sending six variants through the
// live dev gateway to one handset. Every variant WITHOUT the support address
// arrived (plain text; "Your Loooans OTP is 123456"; the warning prefix; the
// full template minus the address). Both variants WITH it were dropped, as was
// the real OTP sent that morning. The address was the only difference.
//
// This applies to the SMS body only. The email OTP body is unaffected and may
// still carry the support address.
func TestRequestOtpCore_MobileObjective_SmsBodyHasNoLinkTokens(t *testing.T) {
	now := time.Date(2026, 8, 20, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+639171234567"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	authEmail := &fakes.AuthEmailReader{}
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps, _ := buildDeps(now, "h-mob", "222222", userReader, address, authEmail, otpWriter, emailSender)

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

	msg, _ := otpWriter.Writes[0].Entry["message"].(string)
	if msg == "" {
		t.Fatal("SMS body is empty")
	}
	for _, token := range []string{"@", "http", "www.", ".com", ".ph"} {
		if strings.Contains(strings.ToLower(msg), token) {
			t.Errorf("SMS body contains link-like token %q, which PH carriers filter; "+
				"keep support contact details in the email body only. Body: %q", token, msg)
		}
	}
}
