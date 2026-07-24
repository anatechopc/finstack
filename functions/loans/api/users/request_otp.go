package users

import (
	"com.loooans.app/api/service"
	utils2 "com.loooans.app/utils"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"io"
	"net/http"
	"strings"
	"time"
)

// Sentinel errors returned by RequestOtpCore. The HTTP adapter translates
// each of these into a specific 4xx response so the Flutter client can show
// a useful message.
var (
	ErrInvalidObjective     = errors.New("invalid objective")
	ErrUserNotFound         = errors.New("user not found")
	ErrMobileNumberMissing  = errors.New("user has no mobile_number")
	ErrAuthUserMissingEmail = errors.New("auth user has no email")
	// Phone-normalization failures (spec 2026-07-24): the OTP request is
	// rejected rather than queueing an undeliverable SMS.
	ErrAddressMissing = errors.New("user has no address record")
	ErrCountryUnknown = errors.New("country not recognized")
	ErrPhoneInvalid   = errors.New("mobile_number not valid for country")
)

const (
	objectiveEmail        = "email"
	objectiveMobileNumber = "mobile_number"

	otpValidityDuration = 5 * time.Minute
)

// RequestOtpParams is the validated, typed input to RequestOtpCore. The HTTP
// adapter parses the request body and headers and produces this struct.
type RequestOtpParams struct {
	UserID       string // authenticated caller from JWT
	TargetUserID string // user the OTP is for; defaults to UserID when ""
	Objective    string // "email" | "mobile_number"
	Reason       string // optional override; defaults derived from Objective
	Subdomain    string // env-specific subdomain used to build the redirect URL
}

// RequestOtpResult is what the Core hands back to the HTTP adapter. The
// adapter encodes it as the JSON response body.
type RequestOtpResult struct {
	Hash        string
	ExpireAt    int64
	RedirectURL string
}

// RequestOtpDeps wires the side-effecting collaborators RequestOtpCore needs.
// Plain function fields keep the indirection minimal — fakes in tests supply
// method-bound funcs from structs that record calls.
type RequestOtpDeps struct {
	// GenerateOtp returns (hash, otp, error). Hash is the RTDB key; otp is
	// the value sent to the user.
	GenerateOtp func() (hash, otp string, err error)

	// ReadUser loads a Firestore user document by uid. Returns
	// ErrUserNotFound or a transport error.
	ReadUser func(ctx context.Context, uid string) (map[string]any, error)

	// ReadUserAddress returns the `country` value on the user's address
	// doc ({prefix}address where data_id == uid, data_type == 'user'),
	// or ("", nil) when the user has no (non-deleted) address doc.
	ReadUserAddress func(ctx context.Context, uid string) (string, error)

	// GetAuthUserEmail returns the email on file in Firebase Auth for the
	// uid. Returns "" if the user has no email on the auth record. Auth
	// is the source of truth for the email we are trying to verify — the
	// Firestore mirror may be stale or missing the field.
	GetAuthUserEmail func(ctx context.Context, uid string) (string, error)

	// WriteOtp persists the OTP entry at otp/{hash} in RTDB.
	WriteOtp func(ctx context.Context, hash string, entry map[string]any) error

	// SendEmail dispatches an email with the OTP. Returns the upstream
	// error verbatim — no wrapping, so the adapter can decide how much to
	// surface to the client.
	SendEmail func(subject, body string, recipients []string) error

	// Now returns the current time. Injected so tests can pin time.
	Now func() time.Time
}

// RequestOtpCore validates the request, persists an OTP entry in RTDB, and
// (for email) dispatches the OTP to the user's Firebase Auth email. The
// mobile_number path leaves SMS delivery to the gateway that watches RTDB —
// Core only writes the entry.
func RequestOtpCore(ctx context.Context, p RequestOtpParams, deps RequestOtpDeps) (RequestOtpResult, error) {
	if p.Objective != objectiveEmail && p.Objective != objectiveMobileNumber {
		return RequestOtpResult{}, ErrInvalidObjective
	}

	targetUserID := p.TargetUserID
	if targetUserID == "" {
		targetUserID = p.UserID
	}

	reason := p.Reason
	if reason == "" {
		if p.Objective == objectiveEmail {
			reason = reasonEmailVerification
		} else {
			reason = reasonMobileVerification
		}
	}

	hash, otp, err := deps.GenerateOtp()
	if err != nil {
		return RequestOtpResult{}, fmt.Errorf("generate otp: %w", err)
	}

	now := deps.Now().UTC()
	expireAt := now.Add(otpValidityDuration).UnixMilli()

	entry := map[string]any{
		"id":           hash,
		"userId":       targetUserID,
		"otp":          otp,
		"expire_at":    expireAt,
		"created_at":   now.UnixMilli(),
		"updated_at":   now.UnixMilli(),
		"deleted_at":   nil,
		"objective":    p.Objective,
		"reason":       reason,
		"requested_by": p.UserID,
	}

	if p.Objective == objectiveMobileNumber {
		userDoc, err := deps.ReadUser(ctx, targetUserID)
		if err != nil {
			return RequestOtpResult{}, err
		}
		if userDoc == nil {
			return RequestOtpResult{}, ErrUserNotFound
		}
		phone, _ := userDoc["mobile_number"].(string)
		if phone == "" {
			return RequestOtpResult{}, ErrMobileNumberMissing
		}
		country, err := deps.ReadUserAddress(ctx, targetUserID)
		if err != nil {
			return RequestOtpResult{}, err
		}
		normalized, err := service.NormalizePhoneE164(phone, country)
		if err != nil {
			switch {
			case errors.Is(err, service.ErrCountryUnknown):
				if strings.TrimSpace(country) == "" {
					return RequestOtpResult{}, fmt.Errorf("%w: user %s", ErrAddressMissing, targetUserID)
				}
				return RequestOtpResult{}, fmt.Errorf("%w: %q", ErrCountryUnknown, country)
			case errors.Is(err, service.ErrPhoneInvalid):
				return RequestOtpResult{}, fmt.Errorf("%w: %v", ErrPhoneInvalid, err)
			default:
				return RequestOtpResult{}, err
			}
		}
		entry["phone"] = normalized
		entry["message"] = fmt.Sprintf(
			"NEVER SHARE YOUR ONE-TIME PIN. Your Loooans OTP is %s. If you did not request for OTP, please contact support at support@loooans.com immediately.", otp)
		entry["sms_status"] = "pending"
		entry["sent_at"] = nil
		entry["error"] = nil
	}

	if err := deps.WriteOtp(ctx, hash, entry); err != nil {
		return RequestOtpResult{}, err
	}

	if p.Objective == objectiveEmail {
		email, err := deps.GetAuthUserEmail(ctx, targetUserID)
		if err != nil {
			return RequestOtpResult{}, err
		}
		if email == "" {
			return RequestOtpResult{}, ErrAuthUserMissingEmail
		}
		if err := deps.SendEmail("Verify your email — Loooans!", createHtmlBody(otp), []string{email}); err != nil {
			return RequestOtpResult{}, err
		}
	}

	return RequestOtpResult{
		Hash:        hash,
		ExpireAt:    expireAt,
		RedirectURL: fmt.Sprintf("%sloooans.com/verify?vid=%s", p.Subdomain, hash),
	}, nil
}

// RequestOtpValidator authenticates the inbound HTTP request and returns the
// caller's uid, or "" when validation failed (in which case the
// implementation has already written the response).
type RequestOtpValidator func(w http.ResponseWriter, r *http.Request) string

// RequestOtpDepsBuilder constructs RequestOtpDeps for a single request,
// returning a cleanup func that the caller defer-runs (typically closing
// the Firestore client). Returning a non-nil error causes the handler to
// emit a 500 with the error message.
type RequestOtpDepsBuilder func(ctx context.Context) (RequestOtpDeps, func(), error)

// RequestOtpHandler returns a stateless http.HandlerFunc that wires the
// given validator, deps builder, and subdomain function. Extracted so tests
// can stub auth + Firebase wiring with httptest without spinning up real
// infrastructure.
func RequestOtpHandler(
	validate RequestOtpValidator,
	build RequestOtpDepsBuilder,
	getSubdomain func() string,
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log, errLog := utils2.InitializeLogger("request_otp")
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

		userId := validate(w, r)
		if userId == "" {
			return
		}

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

		var parsedBody map[string]string
		if errJson := json.Unmarshal(body, &parsedBody); errJson != nil {
			http.Error(w, errJson.Error(), http.StatusInternalServerError)
			return
		}

		objective, ok := parsedBody["purpose"]
		if !ok || objective == "" {
			http.Error(w, "Cannot generate OTP. Missing field `for`", http.StatusBadRequest)
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

		params := RequestOtpParams{
			UserID:       userId,
			TargetUserID: parsedBody["target_user_id"],
			Objective:    objective,
			Reason:       parsedBody["reason"],
			Subdomain:    getSubdomain(),
		}

		result, err := RequestOtpCore(ctx, params, deps)
		if err != nil {
			switch {
			case errors.Is(err, ErrInvalidObjective):
				http.Error(w, "Request for OTP objective not valid.", http.StatusBadRequest)
			case errors.Is(err, ErrUserNotFound):
				http.Error(w, "User not found.", http.StatusBadRequest)
			case errors.Is(err, ErrMobileNumberMissing):
				http.Error(w, "User has no mobile number on record.", http.StatusBadRequest)
			case errors.Is(err, ErrAuthUserMissingEmail):
				http.Error(w, "User has no email on record.", http.StatusBadRequest)
			default:
				log.Error("request otp error", zap.String("error", err.Error()))
				http.Error(w, err.Error(), http.StatusInternalServerError)
			}
			return
		}

		if encodeErr := json.NewEncoder(w).Encode(map[string]any{
			"redirect_url": result.RedirectURL,
			"token":        result.Hash,
			"expire_at":    result.ExpireAt,
		}); encodeErr != nil {
			log.Error("Send encode error", zap.String("error", encodeErr.Error()))
			http.Error(w, "Send encode error", http.StatusInternalServerError)
		}
	}
}

// buildRealRequestOtpDeps wires the real Firebase clients (Firestore, RTDB,
// Auth) for a single request. The returned cleanup closes the Firestore
// client; RTDB and Auth clients do not require explicit close.
func buildRealRequestOtpDeps(ctx context.Context) (RequestOtpDeps, func(), error) {
	app, err := utils2.InitializeFirebase(ctx)
	if err != nil {
		return RequestOtpDeps{}, nil, fmt.Errorf("firebase admin initialization error: %w", err)
	}

	db, err := app.Database(ctx)
	if err != nil {
		return RequestOtpDeps{}, nil, fmt.Errorf("realtime DB error: %w", err)
	}

	firestoreClient, err := app.Firestore(ctx)
	if err != nil {
		return RequestOtpDeps{}, nil, fmt.Errorf("firestore client error: %w", err)
	}

	collectionPrefix := utils2.GetCollectionPrefix()
	cleanup := func() { _ = firestoreClient.Close() }

	return RequestOtpDeps{
		GenerateOtp: service.GenerateOtp,
		ReadUser: func(ctx context.Context, uid string) (map[string]any, error) {
			snap, err := firestoreClient.Doc(collectionPrefix + "users/" + uid).Get(ctx)
			if err != nil {
				if status.Code(err) == codes.NotFound {
					// Convention: signal "no doc" as (nil, nil); Core
					// maps that to ErrUserNotFound so the HTTP layer can
					// emit a 400 instead of a 500.
					return nil, nil
				}
				return nil, err
			}
			data := snap.Data()
			if data == nil {
				return nil, nil
			}
			return data, nil
		},
		GetAuthUserEmail: func(ctx context.Context, uid string) (string, error) {
			authClient, err := app.Auth(ctx)
			if err != nil {
				return "", err
			}
			u, err := authClient.GetUser(ctx, uid)
			if err != nil {
				return "", err
			}
			return u.Email, nil
		},
		WriteOtp: func(ctx context.Context, hash string, entry map[string]any) error {
			return db.NewRef("otp/" + hash).Set(ctx, entry)
		},
		SendEmail: func(subject, body string, recipients []string) error {
			_, err := utils2.SendEmail(subject, body, recipients)
			return err
		},
		Now: time.Now,
	}, cleanup, nil
}

// RequestOtp is the production-wired HTTP handler that GCF registers. The
// var-binding instead of a func declaration means the handler is built once
// at package load and reused; the underlying closure is safe to share across
// concurrent requests because each request gets its own deps via build().
var RequestOtp = RequestOtpHandler(
	utils2.ValidateRequestV2,
	buildRealRequestOtpDeps,
	utils2.GetSubdomain,
)

// createHtmlBody renders a branded HTML email body containing the OTP code.
// The template uses table-based layout for maximum email-client
// compatibility (Outlook still requires this). Inline styles only — most
// email clients strip <style> blocks.
//
// Brand color: AppColors.green1 (#38DC93).
func createHtmlBody(otp string) string {
	const tpl = `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background-color:#f4f4f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1b1f;">
  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f7;padding:24px 0;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
          <tr>
            <td style="background-color:#38DC93;padding:24px 32px;">
              <div style="color:#1c1b1f;font-size:20px;font-weight:600;letter-spacing:-0.3px;">Loooans!</div>
              <div style="color:#1c1b1f;font-size:13px;opacity:0.75;margin-top:2px;">Your loans marketplace</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px;">
              <h1 style="margin:0 0 16px 0;font-size:22px;font-weight:600;color:#1c1b1f;line-height:1.3;">Verify your email</h1>
              <p style="margin:0 0 24px 0;font-size:15px;line-height:1.5;color:#1c1b1f;">Use the one-time pin below to verify your email address in the Loooans! app.</p>
              <div style="margin:0 0 24px 0;padding:20px;background-color:#f4f4f7;border-radius:8px;text-align:center;">
                <div style="font-size:32px;font-weight:700;letter-spacing:8px;color:#1c1b1f;font-family:'SF Mono','Roboto Mono',Menlo,monospace;">%s</div>
              </div>
              <p style="margin:0 0 16px 0;font-size:13px;line-height:1.5;color:#5f5f63;">This code expires in <strong>5 minutes</strong>.</p>
              <p style="margin:0;font-size:13px;line-height:1.5;color:#5f5f63;">If you didn't request this, you can safely ignore this email.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 32px;border-top:1px solid #ececef;background-color:#fafafb;">
              <p style="margin:0;font-size:12px;line-height:1.5;color:#7c7c80;">© Loooans! — This is an automated message, please do not reply.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
	return fmt.Sprintf(tpl, otp)
}
