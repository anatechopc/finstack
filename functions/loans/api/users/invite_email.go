package users

import (
	"context"
	"fmt"

	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
)

// sendPasswordSetupEmail generates a Firebase password-reset link for email and
// sends a branded "set your password" message via Microsoft Graph. Used both
// for the first invite (AddUser) and for resend / forgot-password
// (SendPasswordSetupLink). displayName may be empty (forgot-password path).
//
// PasswordResetLink errors when no account exists for the email; callers in the
// forgot-password path swallow that error to avoid leaking account existence.
func sendPasswordSetupEmail(ctx context.Context, authClient *auth.Client, email, displayName string) error {
	link, err := authClient.PasswordResetLink(ctx, email)
	if err != nil {
		return fmt.Errorf("generate password reset link: %w", err)
	}

	greeting := "Hi!"
	if displayName != "" {
		greeting = fmt.Sprintf("Hi %s!", displayName)
	}

	subject := "Set your Loooans password"
	body := fmt.Sprintf(
		`<p>%s</p>`+
			`<p>An account has been created for you on Loooans. `+
			`Tap the button below to set your password and sign in.</p>`+
			`<p><a href="%s">Set your password</a></p>`+
			`<p>On your first sign-in you'll be asked to verify your email and mobile number.</p>`+
			`<p>If you weren't expecting this, you can ignore this email.</p>`+
			`<p>From: The Loooans team</p>`,
		greeting, link,
	)

	if _, err := utils.SendEmail(subject, body, []string{email}); err != nil {
		return fmt.Errorf("send invite email: %w", err)
	}
	return nil
}
