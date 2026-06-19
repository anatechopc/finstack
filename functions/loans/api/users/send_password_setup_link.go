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

// SendPasswordSetupLink emails a set-password / reset link for the given email.
// It backs both the admin "Resend invite" action and the login "Forgot
// password" link, so it is intentionally UNAUTHENTICATED and always responds
// 200 — it never reveals whether an account exists.
//
// TODO(rate-limit): this endpoint is unauthenticated; add per-email/IP rate
// limiting before production to prevent email-bombing.
func SendPasswordSetupLink(w http.ResponseWriter, r *http.Request) {
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
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	deps := SendPasswordSetupLinkDeps{
		SendInvite: func(ctx context.Context, email string) error {
			return sendPasswordSetupEmail(ctx, authClient, email, "")
		},
	}
	if err := HandleSendPasswordSetupLinkCore(ctx, req.Email, deps); err != nil {
		// Core never returns an error today; log defensively and still 200.
		log.Error("send_password_setup_link core error: " + err.Error())
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"message": "ok"})
}
