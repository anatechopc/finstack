package users

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"
)

type setPasswordRequest struct {
	Token       string `json:"token"`
	NewPassword string `json:"newPassword"`
}

// SetPasswordDepsBuilder constructs SetPasswordDeps for a single request,
// returning a cleanup func that the caller defer-runs (typically closing the
// Firestore client). Returning a non-nil error causes the handler to emit a 500.
type SetPasswordDepsBuilder func(ctx context.Context) (SetPasswordDeps, func(), error)

// SetPasswordHandler returns a stateless http.HandlerFunc that wires the given
// deps builder. Extracted so tests can stub Firebase wiring with httptest
// without spinning up real infrastructure. The endpoint is intentionally
// UNAUTHENTICATED (no validator): the one-time token in the body IS the
// credential.
func SetPasswordHandler(build SetPasswordDepsBuilder) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log, errLog := utils.InitializeLogger("set_password")
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
		var req setPasswordRequest
		if err := json.Unmarshal(body, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		ctx := context.Background()
		deps, cleanup, errBuild := build(ctx)
		if errBuild != nil {
			// Log the real cause for operators, but keep the body generic — the
			// caller is unauthenticated and must not see internal wiring errors.
			log.Error("error building deps: " + errBuild.Error())
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if cleanup != nil {
			defer cleanup()
		}

		res, err := HandleSetPasswordCore(ctx, req.Token, req.NewPassword, deps)
		if err != nil {
			// writeSetPasswordError keeps the client-facing reason opaque (a 400
			// for any unusable token); log here so operators can still diagnose.
			log.Error("set_password core error: " + err.Error())
			writeSetPasswordError(w, err)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": map[string]any{
				"email": res.Email,
			},
		})
	}
}

// buildRealSetPasswordDeps wires the real Firebase clients (Auth, Firestore) for
// a single request. The returned cleanup closes the Firestore client.
func buildRealSetPasswordDeps(ctx context.Context) (SetPasswordDeps, func(), error) {
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return SetPasswordDeps{}, nil, err
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		return SetPasswordDeps{}, nil, err
	}
	fs, err := app.Firestore(ctx)
	if err != nil {
		return SetPasswordDeps{}, nil, err
	}

	prefix := utils.GetCollectionPrefix()
	cleanup := func() { _ = fs.Close() }

	return SetPasswordDeps{
		ConsumeToken: func(ctx context.Context, tokenHash string) (string, string, error) {
			var uid, email string
			txErr := fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
				// Look up the single token doc by its hash inside the
				// transaction so the read participates in the same atomic unit
				// as the used_at write — this is what makes the consume
				// single-use under concurrent requests.
				q := fs.Collection(prefix+"password_setup_tokens").
					Where("token_hash", "==", tokenHash).
					Limit(1)
				// Capture the iterator and Stop() it so the underlying RPC
				// stream is released (repo convention; see triggers/*.go).
				it := tx.Documents(q)
				defer it.Stop()
				snap, iErr := it.Next()
				if iErr == iterator.Done {
					return ErrInvalidSetPasswordToken
				}
				if iErr != nil {
					return iErr
				}

				// Evaluate the doc BEFORE any write. A bad/expired/used/malformed
				// doc returns an error here, so tx.Set (the used_at burn) never
				// runs — the one-time link survives. nowMillis is computed once
				// and reused for both the expiry check and the used_at stamp.
				nowMillis := time.Now().UTC().UnixMilli()
				u, e, vErr := evaluateSetPasswordToken(snap.Data(), nowMillis)
				if vErr != nil {
					return vErr // bad/expired/used/malformed → do NOT mark used
				}
				uid, email = u, e

				// Mark used atomically; firestore.MergeAll leaves the other
				// fields untouched. The transaction commit is the point at which
				// concurrent consumers contend — the loser retries, re-reads the
				// now-used doc, and is rejected.
				return tx.Set(snap.Ref, map[string]any{
					"used_at": nowMillis,
				}, firestore.MergeAll)
			})
			if txErr != nil {
				if errors.Is(txErr, ErrInvalidSetPasswordToken) {
					return "", "", ErrInvalidSetPasswordToken
				}
				return "", "", txErr
			}
			return uid, email, nil
		},
		SetPassword: func(ctx context.Context, uid, newPassword string) error {
			// Clicking the emailed link proves inbox control, so mark email
			// verified alongside setting the password.
			update := (&auth.UserToUpdate{}).Password(newPassword).EmailVerified(true)
			_, uErr := authClient.UpdateUser(ctx, uid, update)
			return uErr
		},
	}, cleanup, nil
}

// SetPassword consumes a one-time set-password / reset token and sets the
// account password (and marks email verified). It is intentionally
// UNAUTHENTICATED — the one-time token in the request body IS the credential.
//
// TODO(rate-limit): unauthenticated — add per-IP rate limiting before prod.
func SetPassword(w http.ResponseWriter, r *http.Request) {
	SetPasswordHandler(buildRealSetPasswordDeps)(w, r)
}

// writeSetPasswordError maps core sentinels onto HTTP status codes. Bad input
// and unusable tokens are 400; everything else is a 500.
func writeSetPasswordError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrMissingNewPassword), errors.Is(err, ErrWeakPassword), errors.Is(err, ErrInvalidSetPasswordToken):
		// These sentinels are safe, client-actionable reasons.
		http.Error(w, err.Error(), http.StatusBadRequest)
	default:
		// Any other (transport) error is logged by the caller; keep the body
		// generic so the unauthenticated client never sees internal details.
		http.Error(w, "Internal error", http.StatusInternalServerError)
	}
}

// evaluateSetPasswordToken decides whether a token doc is usable and extracts
// its uid/email. Pure (no Firestore) so the consume decision logic is unit-
// testable. A non-nil error means the token must NOT be consumed (so a bad,
// expired, used, or malformed doc never burns the one-time link).
func evaluateSetPasswordToken(data map[string]any, nowMillis int64) (uid, email string, err error) {
	// Already consumed → reject. used_at is nil/absent until consumed.
	if usedAt, ok := data["used_at"]; ok && usedAt != nil {
		return "", "", ErrInvalidSetPasswordToken
	}
	// Expired OR malformed/missing expiry → reject (fails closed). Checking the
	// ok flag guards against expires_at being stored as a Firestore Timestamp
	// instead of int64 millis (the date-convention footgun) — that would
	// otherwise silently reject every token as "expired".
	expiresAt, ok := toInt64(data["expires_at"])
	if !ok || expiresAt <= nowMillis {
		return "", "", ErrInvalidSetPasswordToken
	}
	// A malformed doc with no uid/email must fail closed — never call
	// UpdateUser with an empty uid (which would 500 AND burn the token).
	uid, _ = data["uid"].(string)
	email, _ = data["email"].(string)
	if uid == "" || email == "" {
		return "", "", ErrInvalidSetPasswordToken
	}
	return uid, email, nil
}

// toInt64 coerces a Firestore numeric field (which the SDK may return as int64
// or float64 depending on how it was written) into int64.
func toInt64(v any) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case int:
		return int64(n), true
	case float64:
		return int64(n), true
	default:
		return 0, false
	}
}
