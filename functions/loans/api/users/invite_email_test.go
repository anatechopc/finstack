package users

import (
	"strings"
	"testing"
)

func TestKindForRole(t *testing.T) {
	cases := map[string]emailKind{
		"customer":        emailKindBorrowerInvite,
		"":                emailKindReset,
		"teller":          emailKindStaffInvite,
		"admin":           emailKindStaffInvite,
		"loanOfficer":     emailKindStaffInvite,
		"reviewModerator": emailKindStaffInvite,
	}
	for role, want := range cases {
		if got := kindForRole(role); got != want {
			t.Errorf("kindForRole(%q) = %v, want %v", role, got, want)
		}
	}
}

func TestInviteContent_BorrowerInvite(t *testing.T) {
	subject, body := inviteContent(emailKindBorrowerInvite, "Leizel", "https://reset.link/abc")

	if subject != "Complete your sign-up to see your loan details" {
		t.Fatalf("unexpected subject: %q", subject)
	}
	for _, want := range []string{
		"Hi Leizel!",
		"track your loan application and details",
		"see your payment schedule and dues",
		"explore other loan providers",
		"Complete my sign-up",
		"https://reset.link/abc", // the CTA link is present
		brandGreen,               // the styled button background
	} {
		if !strings.Contains(body, want) {
			t.Errorf("borrower body missing %q", want)
		}
	}
}

func TestInviteContent_StaffInvite(t *testing.T) {
	subject, body := inviteContent(emailKindStaffInvite, "Juan", "https://reset.link/abc")

	if subject != "You've been added to your Loooans team" {
		t.Fatalf("unexpected subject: %q", subject)
	}
	if !strings.Contains(body, "Set up my account") || !strings.Contains(body, "managing loans") {
		t.Errorf("staff body missing expected copy: %q", body)
	}
	// Staff invite must NOT carry the borrower loan pitch.
	if strings.Contains(body, "explore other loan providers") {
		t.Errorf("staff body leaked borrower pitch")
	}
}

func TestInviteContent_Reset_EmptyName(t *testing.T) {
	subject, body := inviteContent(emailKindReset, "", "https://reset.link/abc")

	if subject != "Reset your Loooans password" {
		t.Fatalf("unexpected subject: %q", subject)
	}
	if !strings.Contains(body, "Hi there!") {
		t.Errorf("empty displayName should greet 'Hi there!', body: %q", body)
	}
	if !strings.Contains(body, "Reset my password") {
		t.Errorf("reset body missing CTA")
	}
}

func TestInviteContent_EscapesDisplayName(t *testing.T) {
	_, body := inviteContent(emailKindBorrowerInvite, "<script>alert(1)</script>", "https://reset.link/abc")
	if strings.Contains(body, "<script>") {
		t.Errorf("displayName was not HTML-escaped: %q", body)
	}
	if !strings.Contains(body, "&lt;script&gt;") {
		t.Errorf("expected escaped displayName in body")
	}
}
