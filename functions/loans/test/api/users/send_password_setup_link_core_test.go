package users_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

func TestSendPasswordSetupLinkCore_KnownEmail_Sends(t *testing.T) {
	inviter := &fakes.Inviter{}
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return inviter.Send(ctx, email, "", "")
	}}
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "jane@example.com", deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(inviter.Invites) != 1 || inviter.Invites[0].Email != "jane@example.com" {
		t.Fatalf("expected invite to jane@example.com, got %+v", inviter.Invites)
	}
}

func TestSendPasswordSetupLinkCore_EmptyEmail_NoOp(t *testing.T) {
	inviter := &fakes.Inviter{}
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return inviter.Send(ctx, email, "", "")
	}}
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "  ", deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(inviter.Invites) != 0 {
		t.Fatalf("expected no invite for empty email, got %+v", inviter.Invites)
	}
}

func TestSendPasswordSetupLinkCore_UnknownEmail_NeverLeaks(t *testing.T) {
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return errors.New("there is no user record corresponding to the provided identifier")
	}}
	// Must swallow the error so the caller cannot distinguish existing vs
	// non-existing accounts.
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "ghost@example.com", deps); err != nil {
		t.Fatalf("expected nil error (no account-existence leak), got %v", err)
	}
}
