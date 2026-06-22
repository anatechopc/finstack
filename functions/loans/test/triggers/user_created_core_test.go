package triggers_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// userCreatedDeps wires the user-created core to the email-reader and
// welcome-sender fakes.
func userCreatedDeps(emails *fakes.AuthEmailReader, sender *fakes.WelcomeEmailSender) triggers.UserCreatedDeps {
	return triggers.UserCreatedDeps{
		GetUserEmail:     emails.Read,
		SendWelcomeEmail: sender.Send,
	}
}

func TestHandleUserCreatedCore_Skip_DoesNothing(t *testing.T) {
	emails := &fakes.AuthEmailReader{Emails: map[string]string{"uid-1": "user@example.com"}}
	sender := &fakes.WelcomeEmailSender{}

	if err := triggers.HandleUserCreatedCore(
		context.Background(), "uid-1", true, userCreatedDeps(emails, sender),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(emails.ReadCalls) != 0 {
		t.Errorf("skip should not read the email, got calls %v", emails.ReadCalls)
	}
	if len(sender.Sent) != 0 {
		t.Errorf("skip should not send any welcome email, got %v", sender.Sent)
	}
}

func TestHandleUserCreatedCore_EmailPresent_SendsWelcome(t *testing.T) {
	emails := &fakes.AuthEmailReader{Emails: map[string]string{"uid-1": "user@example.com"}}
	sender := &fakes.WelcomeEmailSender{}

	if err := triggers.HandleUserCreatedCore(
		context.Background(), "uid-1", false, userCreatedDeps(emails, sender),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(emails.ReadCalls) != 1 || emails.ReadCalls[0] != "uid-1" {
		t.Errorf("expected one email read for uid-1, got %v", emails.ReadCalls)
	}
	if len(sender.Sent) != 1 || sender.Sent[0] != "user@example.com" {
		t.Errorf("expected one welcome email to user@example.com, got %v", sender.Sent)
	}
}

func TestHandleUserCreatedCore_MissingUid_Errors(t *testing.T) {
	emails := &fakes.AuthEmailReader{}
	sender := &fakes.WelcomeEmailSender{}

	err := triggers.HandleUserCreatedCore(
		context.Background(), "", false, userCreatedDeps(emails, sender),
	)
	if err == nil {
		t.Fatal("expected an error for an empty uid")
	}
	if len(emails.ReadCalls) != 0 {
		t.Errorf("missing uid should not read the email, got calls %v", emails.ReadCalls)
	}
	if len(sender.Sent) != 0 {
		t.Errorf("missing uid should not send any welcome email, got %v", sender.Sent)
	}
}

func TestHandleUserCreatedCore_NoEmail_NoSend(t *testing.T) {
	// uid-1 is not in the Emails map, so Read returns "" with a nil error.
	emails := &fakes.AuthEmailReader{}
	sender := &fakes.WelcomeEmailSender{}

	if err := triggers.HandleUserCreatedCore(
		context.Background(), "uid-1", false, userCreatedDeps(emails, sender),
	); err != nil {
		t.Fatalf("an empty email should be a graceful no-op, got err: %v", err)
	}
	if len(sender.Sent) != 0 {
		t.Errorf("no email means no welcome send, got %v", sender.Sent)
	}
}

func TestHandleUserCreatedCore_GetEmailError_Propagates(t *testing.T) {
	emails := &fakes.AuthEmailReader{Err: errors.New("auth: user not found")}
	sender := &fakes.WelcomeEmailSender{}

	err := triggers.HandleUserCreatedCore(
		context.Background(), "uid-1", false, userCreatedDeps(emails, sender),
	)
	if err == nil {
		t.Fatal("expected the GetUserEmail error to propagate")
	}
	if len(sender.Sent) != 0 {
		t.Errorf("should not send a welcome email when the email lookup fails, got %v", sender.Sent)
	}
}

func TestHandleUserCreatedCore_SendError_Propagates(t *testing.T) {
	emails := &fakes.AuthEmailReader{Emails: map[string]string{"uid-1": "user@example.com"}}
	sender := &fakes.WelcomeEmailSender{Err: errors.New("ms-graph: send failed")}

	err := triggers.HandleUserCreatedCore(
		context.Background(), "uid-1", false, userCreatedDeps(emails, sender),
	)
	if err == nil {
		t.Fatal("expected the SendWelcomeEmail error to propagate")
	}
}
