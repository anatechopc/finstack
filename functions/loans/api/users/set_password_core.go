package users

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// Sentinel errors returned by HandleSetPasswordCore. The HTTP adapter maps these
// onto status codes; any other (transport) error maps to 500.
var (
	// ErrInvalidSetPasswordToken covers every unusable-token case (absent,
	// expired, or already-used) collapsed into one opaque error so the endpoint
	// never reveals which it was.
	ErrInvalidSetPasswordToken = errors.New("invalid, expired, or already-used token")
	ErrMissingNewPassword      = errors.New("new password is required")
)

// SetPasswordDeps wires the collaborators the core needs, so the business logic
// is unit-testable without Firebase. The real implementations are wired in the
// HTTP adapter (set_password.go).
type SetPasswordDeps struct {
	// ConsumeToken atomically validates tokenHash (exists, not expired, not
	// used), marks it used, and returns the uid + email it was issued for.
	// Returns ErrInvalidSetPasswordToken when the token is unusable.
	ConsumeToken func(ctx context.Context, tokenHash string) (uid, email string, err error)
	// SetPassword sets the account's password and marks its email verified
	// (clicking the emailed link proves inbox control).
	SetPassword func(ctx context.Context, uid, newPassword string) error
}

// SetPasswordResult is returned to the adapter to render the HTTP response.
type SetPasswordResult struct {
	Email string
}

// HandleSetPasswordCore consumes a one-time token and sets the account password
// (and marks email verified). Returns the email so the client can sign in.
func HandleSetPasswordCore(ctx context.Context, token, newPassword string, deps SetPasswordDeps) (SetPasswordResult, error) {
	if strings.TrimSpace(newPassword) == "" {
		return SetPasswordResult{}, ErrMissingNewPassword
	}
	if strings.TrimSpace(token) == "" {
		return SetPasswordResult{}, ErrInvalidSetPasswordToken
	}
	uid, email, err := deps.ConsumeToken(ctx, HashSetPasswordToken(token))
	if err != nil {
		if errors.Is(err, ErrInvalidSetPasswordToken) {
			return SetPasswordResult{}, ErrInvalidSetPasswordToken
		}
		return SetPasswordResult{}, fmt.Errorf("consume token: %w", err)
	}
	if err := deps.SetPassword(ctx, uid, newPassword); err != nil {
		return SetPasswordResult{}, fmt.Errorf("set password: %w", err)
	}
	return SetPasswordResult{Email: email}, nil
}
