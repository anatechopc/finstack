package users_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// entry builds a sample OTP entry containing id, userId, otp, expire_at (as
// float64 — matching how the RTDB SDK decodes JSON numbers), and reason.
// extra is merged in last and may override any of the defaults.
func entry(hash, reason string, expireAtMs int64, extra map[string]any) map[string]any {
	e := map[string]any{
		"id":        hash,
		"userId":    "user-123",
		"otp":       "000000",
		"expire_at": float64(expireAtMs),
		"reason":    reason,
	}
	for k, v := range extra {
		e[k] = v
	}
	return e
}

// genOtpForTest produces a (hash, otp) pair using the real OTP service via the
// re-exported users.GenerateOtpForTest helper. Tests that need a valid OTP for
// verification use this so that service.VerifyOtp returns true.
func genOtpForTest(t *testing.T) (string, string) {
	t.Helper()
	hash, otp, err := users.GenerateOtpForTest()
	if err != nil {
		t.Fatalf("GenerateOtpForTest failed: %v", err)
	}
	return hash, otp
}

func TestVerifyOtpCore_MobileVerification_UpdatesUserDoc(t *testing.T) {
	hash, otp := genOtpForTest(t)
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	expireAt := now.Add(5 * time.Minute).UnixMilli()

	reader := &fakes.OtpReader{
		Entries: map[string]map[string]any{
			hash: entry(hash, "mobile_verification", expireAt, map[string]any{"otp": otp}),
		},
	}
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), hash, otp, deps)
	if err != nil {
		t.Fatalf("VerifyOtpCore returned error: %v", err)
	}
	if !verified {
		t.Fatalf("expected verified=true, got false")
	}
	if len(updater.Updates) != 1 {
		t.Fatalf("expected exactly 1 user update, got %d", len(updater.Updates))
	}
	u := updater.Updates[0]
	if u.UID != "user-123" {
		t.Errorf("expected UID=user-123, got %q", u.UID)
	}
	bit, ok := u.Fields["verificationStatus_or"].(int)
	if !ok {
		t.Errorf("expected verificationStatus_or to be int, got %T (%v)", u.Fields["verificationStatus_or"], u.Fields["verificationStatus_or"])
	} else if bit != 2 {
		t.Errorf("expected verificationStatus_or=2, got %d", bit)
	}
	mobileVerifiedAt, ok := u.Fields["mobile_verified_at"].(time.Time)
	if !ok {
		t.Errorf("expected mobile_verified_at to be time.Time, got %T (%v)", u.Fields["mobile_verified_at"], u.Fields["mobile_verified_at"])
	} else if !mobileVerifiedAt.Equal(now) {
		t.Errorf("expected mobile_verified_at=%v, got %v", now, mobileVerifiedAt)
	}
	if len(deleter.DeletedTokens) != 1 || deleter.DeletedTokens[0] != hash {
		t.Errorf("expected exactly one delete of %q, got %v", hash, deleter.DeletedTokens)
	}
}

func TestVerifyOtpCore_PaymentReason_DoesNotUpdateUser(t *testing.T) {
	hash, otp := genOtpForTest(t)
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	expireAt := now.Add(5 * time.Minute).UnixMilli()

	reader := &fakes.OtpReader{
		Entries: map[string]map[string]any{
			hash: entry(hash, "payment", expireAt, map[string]any{"otp": otp}),
		},
	}
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), hash, otp, deps)
	if err != nil {
		t.Fatalf("VerifyOtpCore returned error: %v", err)
	}
	if !verified {
		t.Fatalf("expected verified=true, got false")
	}
	if len(updater.Updates) != 0 {
		t.Errorf("expected zero user updates, got %d: %+v", len(updater.Updates), updater.Updates)
	}
	if len(deleter.DeletedTokens) != 1 {
		t.Errorf("expected exactly one delete, got %d", len(deleter.DeletedTokens))
	}
}

func TestVerifyOtpCore_UnknownReason_VerifiesNoSideEffects(t *testing.T) {
	hash, otp := genOtpForTest(t)
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	expireAt := now.Add(5 * time.Minute).UnixMilli()

	reader := &fakes.OtpReader{
		Entries: map[string]map[string]any{
			hash: entry(hash, "something_unknown", expireAt, map[string]any{"otp": otp}),
		},
	}
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), hash, otp, deps)
	if err != nil {
		t.Fatalf("VerifyOtpCore returned error: %v", err)
	}
	if !verified {
		t.Fatalf("expected verified=true, got false")
	}
	if len(updater.Updates) != 0 {
		t.Errorf("expected zero user updates for unknown reason, got %d", len(updater.Updates))
	}
}

func TestVerifyOtpCore_WrongOtp_ReturnsErrorNoSideEffects(t *testing.T) {
	hash, _ := genOtpForTest(t)
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	expireAt := now.Add(5 * time.Minute).UnixMilli()

	reader := &fakes.OtpReader{
		Entries: map[string]map[string]any{
			hash: entry(hash, "mobile_verification", expireAt, nil),
		},
	}
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), hash, "999999", deps)
	if !errors.Is(err, users.ErrOtpInvalid) {
		t.Fatalf("expected ErrOtpInvalid, got %v", err)
	}
	if verified {
		t.Errorf("expected verified=false, got true")
	}
	if len(deleter.DeletedTokens) != 0 {
		t.Errorf("expected no deletes, got %d", len(deleter.DeletedTokens))
	}
	if len(updater.Updates) != 0 {
		t.Errorf("expected no user updates, got %d", len(updater.Updates))
	}
}

func TestVerifyOtpCore_ExpiredOtp_ReturnsErrorNoSideEffects(t *testing.T) {
	hash, otp := genOtpForTest(t)
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	// expired one minute ago
	expireAt := now.Add(-1 * time.Minute).UnixMilli()

	reader := &fakes.OtpReader{
		Entries: map[string]map[string]any{
			hash: entry(hash, "mobile_verification", expireAt, map[string]any{"otp": otp}),
		},
	}
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), hash, otp, deps)
	if !errors.Is(err, users.ErrOtpExpired) {
		t.Fatalf("expected ErrOtpExpired, got %v", err)
	}
	if verified {
		t.Errorf("expected verified=false, got true")
	}
	if len(deleter.DeletedTokens) != 0 {
		t.Errorf("expected no deletes on expired, got %d", len(deleter.DeletedTokens))
	}
	if len(updater.Updates) != 0 {
		t.Errorf("expected no user updates on expired, got %d", len(updater.Updates))
	}
}

func TestVerifyOtpCore_MissingEntry_ReturnsError(t *testing.T) {
	now := time.Date(2026, 4, 19, 12, 0, 0, 0, time.UTC)
	reader := &fakes.OtpReader{} // empty Entries -> ErrOtpNotFound
	deleter := &fakes.OtpDeleter{}
	updater := &fakes.UserUpdater{}

	deps := users.VerifyOtpDeps{
		ReadOtp:    reader.Read,
		DeleteOtp:  deleter.Delete,
		UpdateUser: updater.Update,
		Now:        func() time.Time { return now },
	}

	verified, err := users.VerifyOtpCore(context.Background(), "no-such-token", "000000", deps)
	if !errors.Is(err, users.ErrOtpNotFound) {
		t.Fatalf("expected ErrOtpNotFound, got %v", err)
	}
	if verified {
		t.Errorf("expected verified=false, got true")
	}
	if len(deleter.DeletedTokens) != 0 {
		t.Errorf("expected no deletes, got %d", len(deleter.DeletedTokens))
	}
	if len(updater.Updates) != 0 {
		t.Errorf("expected no user updates, got %d", len(updater.Updates))
	}
}

func TestVerifyOtpCore_ReasonReadFromRTDB_NotRequest(t *testing.T) {
	// Structural assertion: VerifyOtpCore takes (ctx, token, otp, deps) and
	// returns (bool, error). The reason is sourced from the RTDB entry that
	// ReadOtp returns, NOT from any request-level argument. If the signature
	// changes to accept a reason explicitly, this fails to compile.
	var _ func(ctx context.Context, token, otp string, deps users.VerifyOtpDeps) (bool, error) = users.VerifyOtpCore
}

func TestVerifyOtpCore_UpdateUserError_PropagatesAfterDelete(t *testing.T) {
	hash, otp := genOtpForTest(t)
	otpReader := &fakes.OtpReader{Entries: map[string]map[string]any{
		hash: entry(hash, "mobile_verification", time.Now().Add(time.Minute).UnixMilli(), nil),
	}}
	deleter := &fakes.OtpDeleter{}
	wantErr := errors.New("firestore: write failed")
	updater := &fakes.UserUpdater{Err: wantErr}

	verified, err := users.VerifyOtpCore(context.Background(), hash, otp, users.VerifyOtpDeps{
		ReadOtp: otpReader.Read, DeleteOtp: deleter.Delete, UpdateUser: updater.Update,
		Now: time.Now,
	})
	if !verified {
		t.Fatal("expected verified=true even when UpdateUser fails (OTP was consumed)")
	}
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected propagated wantErr, got %v", err)
	}
	if len(deleter.DeletedTokens) != 1 {
		t.Fatalf("expected delete to have happened before user update")
	}
	if len(updater.Updates) != 1 {
		t.Fatalf("expected one user-update attempt")
	}
}
