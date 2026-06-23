package users

import (
	"context"
	"encoding/json"
	"io"
	"net/http"

	"com.loooans.app/utils"
)

type sendPasswordSetupLinkRequest struct {
	Email string `json:"email"`
}

// SendPasswordSetupLinkDepsBuilder constructs SendPasswordSetupLinkDeps for a
// single request, returning a cleanup func that the caller defer-runs.
// Returning a non-nil error causes the handler to emit a 500.
type SendPasswordSetupLinkDepsBuilder func(ctx context.Context) (SendPasswordSetupLinkDeps, func(), error)

// SendPasswordSetupLinkHandler returns a stateless http.HandlerFunc that wires
// the given deps builder. Extracted so tests can stub Firebase wiring with
// httptest without spinning up real infrastructure. The endpoint is
// intentionally UNAUTHENTICATED (no validator) and always responds 200.
func SendPasswordSetupLinkHandler(build SendPasswordSetupLinkDepsBuilder) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log, errLog := utils.InitializeLogger("send_password_setup_link")
		if errLog != nil {
			http.Error(w, errLog.Error(), http.StatusInternalServerError)
			return
		}

		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "POST")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Max-Age", "3600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		if r.Method != http.MethodPost {
			http.Error(w, "Use POST method", http.StatusBadRequest)
			return
		}

		body, errBody := io.ReadAll(r.Body)
		defer r.Body.Close()
		if errBody != nil {
			http.Error(w, errBody.Error(), http.StatusBadRequest)
			return
		}
		var req sendPasswordSetupLinkRequest
		if err := json.Unmarshal(body, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		ctx := context.Background()
		deps, cleanup, errBuild := build(ctx)
		if errBuild != nil {
			log.Error("error building deps: " + errBuild.Error())
			http.Error(w, errBuild.Error(), http.StatusInternalServerError)
			return
		}
		if cleanup != nil {
			defer cleanup()
		}

		if err := HandleSendPasswordSetupLinkCore(ctx, req.Email, deps); err != nil {
			// Core never returns an error today; log defensively and still 200.
			log.Error("send_password_setup_link core error: " + err.Error())
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"message": "ok"})
	}
}

// buildRealSendPasswordSetupLinkDeps wires the real Firebase Auth client for a
// single request. Cleanup is a no-op (the Auth client needs no explicit close).
func buildRealSendPasswordSetupLinkDeps(ctx context.Context) (SendPasswordSetupLinkDeps, func(), error) {
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return SendPasswordSetupLinkDeps{}, nil, err
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		return SendPasswordSetupLinkDeps{}, nil, err
	}
	return SendPasswordSetupLinkDeps{
		SendInvite: func(ctx context.Context, email string) error {
			// Empty role → neutral reset copy (this endpoint backs both
			// forgot-password and resend-invite; it has no role context).
			return sendPasswordSetupEmail(ctx, authClient, email, "", "")
		},
	}, func() {}, nil
}

// SendPasswordSetupLink emails a set-password / reset link for the given email.
// It backs both the admin "Resend invite" action and the login "Forgot
// password" link, so it is intentionally UNAUTHENTICATED and always responds
// 200 — it never reveals whether an account exists.
//
// TODO(rate-limit): this endpoint is unauthenticated; add per-email/IP rate
// limiting before production to prevent email-bombing.
func SendPasswordSetupLink(w http.ResponseWriter, r *http.Request) {
	SendPasswordSetupLinkHandler(buildRealSendPasswordSetupLinkDeps)(w, r)
}
