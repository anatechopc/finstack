package users

import (
	"context"
	"strings"
)

// SendPasswordSetupLinkDeps wires the invite sender for the core.
type SendPasswordSetupLinkDeps struct {
	// SendInvite generates + emails a password-reset link. An error (e.g. no
	// such user) is intentionally swallowed by the core so the endpoint never
	// leaks whether an account exists.
	SendInvite func(ctx context.Context, email string) error
}

// HandleSendPasswordSetupLinkCore best-effort sends a set-password / reset link
// to the given email. It ALWAYS returns nil: an empty email is a no-op, and a
// send error (including "no such user") is swallowed so the endpoint is safe to
// expose unauthenticated without enabling account enumeration.
func HandleSendPasswordSetupLinkCore(ctx context.Context, email string, deps SendPasswordSetupLinkDeps) error {
	email = strings.TrimSpace(email)
	if email == "" {
		return nil
	}
	_ = deps.SendInvite(ctx, email)
	return nil
}
