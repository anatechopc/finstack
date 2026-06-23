package users_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// setPasswordDeps wires SetPasswordDeps to the two fakes, returning both so
// tests can assert recorded calls.
func setPasswordDeps(consumer *fakes.SetPasswordTokenConsumer, setter *fakes.PasswordSetter) users.SetPasswordDeps {
	return users.SetPasswordDeps{
		ConsumeToken: consumer.Consume,
		SetPassword:  setter.Set,
	}
}

func TestSetPasswordCore_MissingPassword_Rejected(t *testing.T) {
	consumer := &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"}
	setter := &fakes.PasswordSetter{}

	_, err := users.HandleSetPasswordCore(context.Background(), "tok", "  ", setPasswordDeps(consumer, setter))
	if !errors.Is(err, users.ErrMissingNewPassword) {
		t.Fatalf("expected ErrMissingNewPassword, got %v", err)
	}
	// Must not touch the token or auth when the password is missing.
	if len(consumer.Calls) != 0 || len(setter.Sets) != 0 {
		t.Fatalf("must not consume token / set password when password missing: consume=%v set=%v", consumer.Calls, setter.Sets)
	}
}

func TestSetPasswordCore_WeakPassword_RejectedWithoutConsuming(t *testing.T) {
	consumer := &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"}
	setter := &fakes.PasswordSetter{}

	_, err := users.HandleSetPasswordCore(context.Background(), "tok", "short", setPasswordDeps(consumer, setter))
	if !errors.Is(err, users.ErrWeakPassword) {
		t.Fatalf("expected ErrWeakPassword, got %v", err)
	}
	// A too-short password must NOT burn the one-time token.
	if len(consumer.Calls) != 0 || len(setter.Sets) != 0 {
		t.Fatalf("must not consume token / set password for weak password: consume=%v set=%v", consumer.Calls, setter.Sets)
	}
}

func TestSetPasswordCore_EmptyToken_Invalid(t *testing.T) {
	consumer := &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"}
	setter := &fakes.PasswordSetter{}

	_, err := users.HandleSetPasswordCore(context.Background(), "   ", "new-secret", setPasswordDeps(consumer, setter))
	if !errors.Is(err, users.ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken, got %v", err)
	}
	if len(consumer.Calls) != 0 || len(setter.Sets) != 0 {
		t.Fatalf("must not consume token / set password for empty token: consume=%v set=%v", consumer.Calls, setter.Sets)
	}
}

func TestSetPasswordCore_UnusableToken_Surfaced(t *testing.T) {
	// ConsumeToken returns ErrInvalidSetPasswordToken (expired/used/absent); the
	// core surfaces it unchanged and never sets a password.
	consumer := &fakes.SetPasswordTokenConsumer{Err: users.ErrInvalidSetPasswordToken}
	setter := &fakes.PasswordSetter{}

	_, err := users.HandleSetPasswordCore(context.Background(), "tok", "new-secret", setPasswordDeps(consumer, setter))
	if !errors.Is(err, users.ErrInvalidSetPasswordToken) {
		t.Fatalf("expected ErrInvalidSetPasswordToken, got %v", err)
	}
	if len(setter.Sets) != 0 {
		t.Fatalf("must not set password when token is unusable, got %v", setter.Sets)
	}
}

func TestSetPasswordCore_HappyPath_SetsPasswordReturnsEmail(t *testing.T) {
	consumer := &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"}
	setter := &fakes.PasswordSetter{}

	res, err := users.HandleSetPasswordCore(context.Background(), "tok", "new-secret", setPasswordDeps(consumer, setter))
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if res.Email != "jane@example.com" {
		t.Fatalf("expected email jane@example.com, got %q", res.Email)
	}
	// ConsumeToken must be called with the SHA-256 hash of the raw token, not the
	// raw token itself.
	wantHash := users.HashSetPasswordToken("tok")
	if len(consumer.Calls) != 1 || consumer.Calls[0] != wantHash {
		t.Fatalf("expected consume with hash %q, got %v", wantHash, consumer.Calls)
	}
	if len(setter.Sets) != 1 || setter.Sets[0].UID != "uid-1" || setter.Sets[0].NewPassword != "new-secret" {
		t.Fatalf("expected SetPassword(uid-1, new-secret), got %+v", setter.Sets)
	}
}

func TestSetPasswordCore_SetPasswordErrors_Propagated(t *testing.T) {
	consumer := &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"}
	setter := &fakes.PasswordSetter{Err: errors.New("auth down")}

	_, err := users.HandleSetPasswordCore(context.Background(), "tok", "new-secret", setPasswordDeps(consumer, setter))
	if err == nil {
		t.Fatalf("expected error when SetPassword fails")
	}
	// A transport SetPassword failure is NOT the invalid-token sentinel.
	if errors.Is(err, users.ErrInvalidSetPasswordToken) || errors.Is(err, users.ErrMissingNewPassword) {
		t.Fatalf("expected a transport error, got sentinel: %v", err)
	}
}
