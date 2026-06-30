package users

import (
	"context"
	"fmt"
	"html"
	"net/url"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
)

// Brand palette (mirrors the Flutter AppColors so the email matches the app).
const (
	brandGreen     = "#16A163" // deep green — button / accents (white text reads well)
	brandGreenLite = "#38DC93" // primary mint — header band
	brandInk       = "#1A1A1A" // near-black body text
	brandMuted     = "#6B7280" // secondary / footer text
	brandBg        = "#F3F4F6" // page background
)

// emailKind selects which audience-tailored copy sendPasswordSetupEmail renders.
type emailKind int

const (
	// emailKindBorrowerInvite is sent when an admin adds a customer/borrower —
	// the marketplace pitch (track your loan, see dues, explore providers).
	emailKindBorrowerInvite emailKind = iota
	// emailKindStaffInvite is sent when an admin adds a team member (staff role).
	emailKindStaffInvite
	// emailKindReset is the neutral set/reset-password message used by the
	// forgot-password / resend link endpoint.
	emailKindReset
)

// kindForRole maps the requested user role to the invite audience. An empty
// role (the forgot-password / resend link endpoint, which has no role) yields
// the neutral reset copy.
func kindForRole(role string) emailKind {
	switch role {
	case "customer":
		return emailKindBorrowerInvite
	case "":
		return emailKindReset
	default:
		// admin / loanOfficer / teller / reviewModerator
		return emailKindStaffInvite
	}
}

// buildSetPasswordLink returns the branded self-hosted set/reset-password URL
// for the given subdomain ("dev."/"stg."/"") and raw token. Points at our own
// hosted page (no Firebase action handler).
func buildSetPasswordLink(subdomain, rawToken string) string {
	return fmt.Sprintf("https://%sloooans.com/set-password?token=%s", subdomain, url.QueryEscape(rawToken))
}

// newSetPasswordTokenDoc builds the Firestore doc persisted when a set-password
// link is issued. The field names MUST match the consumer in set_password.go
// (buildRealSetPasswordDeps → ConsumeToken queries "token_hash" and reads
// "used_at"/"expires_at"/"uid"/"email"); changing a key here silently breaks the
// consume path.
func newSetPasswordTokenDoc(tokenHash, uid, email string, now time.Time) map[string]any {
	return map[string]any{
		"token_hash": tokenHash,
		"uid":        uid,
		"email":      email,
		"created_at": now.UnixMilli(),
		"expires_at": now.Add(setPasswordTokenTTL).UnixMilli(),
		"used_at":    nil,
	}
}

// sendPasswordSetupEmail mints + stores a one-time set-password token and emails
// a branded link to our own self-hosted /set-password page (no Firebase action
// handler). The role selects the audience copy: a borrower gets the
// loan/marketplace invite, a staff member gets the team-onboarding invite, and
// an empty role (forgot-password / resend) gets the neutral reset copy.
// displayName may be empty (the link endpoint passes "").
//
// GetUserByEmail errors when no account exists for the email; callers in the
// forgot-password / resend path swallow that error to avoid leaking account
// existence. AddUser never hits that branch — it just created the user.
func sendPasswordSetupEmail(
	ctx context.Context,
	authClient *auth.Client,
	fs *firestore.Client,
	prefix, subdomain, email, displayName, role string,
) error {
	rec, err := authClient.GetUserByEmail(ctx, email)
	if err != nil {
		return fmt.Errorf("lookup user for set-password email: %w", err)
	}

	raw, hash, err := GenerateSetPasswordToken()
	if err != nil {
		return fmt.Errorf("generate set-password token: %w", err)
	}

	doc := newSetPasswordTokenDoc(hash, rec.UID, email, time.Now().UTC())
	if _, _, err := fs.Collection(prefix+"password_setup_tokens").Add(ctx, doc); err != nil {
		return fmt.Errorf("store set-password token: %w", err)
	}

	link := buildSetPasswordLink(subdomain, raw)
	subject, body := inviteContent(kindForRole(role), displayName, link)
	if _, err := utils.SendEmail(subject, body, []string{email}); err != nil {
		return fmt.Errorf("send invite email: %w", err)
	}
	return nil
}

// inviteContent returns the subject line and full HTML body for the given
// audience. The body shares one branded shell (renderEmail) with per-audience
// heading, lead paragraph, optional bullets, and call-to-action label.
func inviteContent(kind emailKind, displayName, link string) (subject, body string) {
	greetingName := "there"
	if displayName != "" {
		greetingName = displayName
	}
	greeting := fmt.Sprintf("Hi %s!", html.EscapeString(greetingName))

	switch kind {
	case emailKindBorrowerInvite:
		return "Complete your sign-up to see your loan details",
			renderEmail(emailContent{
				greeting: greeting,
				lead:     "You've been invited to Loooans. Finish setting up your account to:",
				bullets: []string{
					"track your loan application and details",
					"see your payment schedule and dues",
					"explore other loan providers",
				},
				ctaLabel: "Complete my sign-up",
				link:     link,
				note:     "On your first sign-in we'll ask you to verify your email and mobile number.",
			})
	case emailKindStaffInvite:
		return "You've been added to your Loooans team",
			renderEmail(emailContent{
				greeting: greeting,
				lead:     "You've been added to your company's Loooans workspace. Set up your account to start managing loans.",
				ctaLabel: "Set up my account",
				link:     link,
				note:     "On your first sign-in we'll ask you to verify your email and mobile number.",
			})
	default: // emailKindReset
		return "Reset your Loooans password",
			renderEmail(emailContent{
				greeting: greeting,
				lead:     "Tap the button below to set a new password and sign in.",
				ctaLabel: "Reset my password",
				link:     link,
				note:     "If you didn't request this, you can safely ignore this email.",
			})
	}
}

// emailContent is the per-audience copy that fills the shared branded shell.
type emailContent struct {
	greeting string
	lead     string
	bullets  []string // optional
	ctaLabel string
	link     string
	note     string
}

// renderEmail wraps the per-audience copy in one branded, table-based HTML
// shell with inline styles (robust across email clients, incl. Gmail). The
// caller-supplied greeting is pre-escaped; lead/bullets/labels are static
// trusted copy; link is the server-built self-hosted /set-password URL
// (buildSetPasswordLink — a url.QueryEscape'd random token, not user input).
func renderEmail(c emailContent) string {
	bullets := ""
	if len(c.bullets) > 0 {
		items := ""
		for _, b := range c.bullets {
			items += fmt.Sprintf(
				`<li style="margin:0 0 8px 0;">%s</li>`, html.EscapeString(b),
			)
		}
		bullets = fmt.Sprintf(
			`<ul style="margin:0 0 24px 0;padding-left:20px;color:%s;font-size:15px;line-height:1.6;">%s</ul>`,
			brandInk, items,
		)
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:%[1]s;">
  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="background:%[1]s;padding:24px 0;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%%;background:#ffffff;border-radius:14px;overflow:hidden;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
        <tr><td style="background:%[2]s;padding:20px 32px;">
          <span style="font-size:22px;font-weight:700;color:%[6]s;letter-spacing:0.5px;">Loooans</span>
        </td></tr>
        <tr><td style="padding:32px;">
          <p style="margin:0 0 16px 0;font-size:18px;font-weight:600;color:%[3]s;">%[7]s</p>
          <p style="margin:0 0 20px 0;font-size:15px;line-height:1.6;color:%[3]s;">%[8]s</p>
          %[9]s
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 28px 0;">
            <tr><td style="border-radius:10px;background:%[4]s;">
              <a href="%[10]s" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:10px;">%[11]s</a>
            </td></tr>
          </table>
          <p style="margin:0 0 4px 0;font-size:13px;line-height:1.6;color:%[5]s;">%[12]s</p>
        </td></tr>
        <tr><td style="padding:20px 32px;border-top:1px solid #EEEEEE;">
          <p style="margin:0;font-size:12px;color:%[5]s;">Sent by the Loooans team. If you weren't expecting this, you can ignore this email.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`,
		brandBg,        // 1 page bg
		brandGreenLite, // 2 header band
		brandInk,       // 3 body text
		brandGreen,     // 4 button bg
		brandMuted,     // 5 muted text
		brandInk,       // 6 wordmark color (dark on mint band)
		c.greeting,     // 7
		c.lead,         // 8
		bullets,        // 9
		c.link,         // 10
		c.ctaLabel,     // 11
		c.note,         // 12
	)
}
