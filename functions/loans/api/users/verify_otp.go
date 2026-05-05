package users

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/api/service"
	utils2 "com.loooans.app/utils"

	"go.uber.org/zap"
)

// Sentinel errors returned by VerifyOtpCore. The HTTP adapter translates each
// of these into a specific 4xx response.
var (
	ErrOtpNotFound = errors.New("otp not found")
	ErrOtpExpired  = errors.New("otp expired")
	ErrOtpInvalid  = errors.New("otp invalid")
)

// verificationBitMobileNumber is the bit set in users.verificationStatus once
// the user successfully completes mobile-number verification.
const verificationBitMobileNumber = 2

const (
	reasonPayment            = "payment"
	reasonMobileVerification = "mobile_verification"
)

// VerifyOtpDeps wires the side-effecting collaborators VerifyOtpCore needs.
// Plain function fields keep the indirection minimal — fakes in tests just
// supply method-bound funcs from a struct that records calls.
type VerifyOtpDeps struct {
	// ReadOtp reads the RTDB OTP entry at otp/{token}. Returns nil/ErrOtpNotFound
	// when the entry does not exist.
	ReadOtp func(ctx context.Context, token string) (map[string]any, error)

	// DeleteOtp removes the RTDB OTP entry at otp/{token}.
	DeleteOtp func(ctx context.Context, token string) error

	// UpdateUser applies a Firestore merge update to users/{uid}. The fields
	// map carries dynamically-typed values; the adapter is responsible for
	// translating any mask-style fields (e.g. verificationStatus_or) into
	// concrete Firestore writes.
	UpdateUser func(ctx context.Context, uid string, fields map[string]any) error

	// Now returns the current time. Injected so tests can pin time.
	Now func() time.Time
}

// TestGenerateOtp re-exports service.GenerateOtp so external tests in
// com.loooans.app/test/api/users (which cannot reach an internal helper) can
// produce a (hash, otp) pair that survives the real service.VerifyOtp check.
func TestGenerateOtp() (string, string, error) {
	return service.GenerateOtp()
}

// VerifyOtpCore validates a one-time PIN against the entry stored in RTDB and
// performs the post-verification side-effect dictated by the entry's reason.
//
// Reasons are read from the persisted entry — never from the request — so a
// caller cannot escalate a payment OTP into a profile mutation by lying about
// what they intend to verify.
func VerifyOtpCore(ctx context.Context, token, receivedOtp string, deps VerifyOtpDeps) (bool, error) {
	otpData, err := deps.ReadOtp(ctx, token)
	if err != nil || otpData == nil {
		return false, ErrOtpNotFound
	}

	expireAt, ok := otpData["expire_at"].(float64)
	if !ok {
		return false, ErrOtpNotFound
	}
	if deps.Now().UTC().UnixMilli() > int64(expireAt) {
		return false, ErrOtpExpired
	}

	verified, errVerify := service.VerifyOtp(token, receivedOtp)
	if errVerify != nil || !verified {
		return false, ErrOtpInvalid
	}

	// Verification succeeded — best-effort delete the entry. We deliberately
	// swallow delete errors: the OTP has already been consumed in the caller's
	// view, and a stale RTDB entry will expire on its own.
	_ = deps.DeleteOtp(ctx, token)

	reason, _ := otpData["reason"].(string)
	switch reason {
	case reasonPayment:
		// no post-action; confirmation lives at the payment site.
	case reasonMobileVerification:
		uid, _ := otpData["userId"].(string)
		if uid == "" {
			return true, nil
		}
		if upErr := deps.UpdateUser(ctx, uid, map[string]any{
			"verificationStatus_or": verificationBitMobileNumber,
			"mobile_verified_at":    deps.Now().UTC(),
		}); upErr != nil {
			return true, upErr
		}
	default:
		// Unknown reason — verification still succeeded; no side effect.
	}

	return true, nil
}

// VerifyOtp is the HTTP adapter that wires real Firebase clients into
// VerifyOtpCore. Mirrors the pattern of the previous VerifyPaymentOtp handler:
// CORS preflight, JWT validation, JSON body parse, then dispatch.
func VerifyOtp(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("verify_otp")
	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	// CORS preflight
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

	// JWT validation
	if uid := utils2.ValidateRequestV2(w, r); uid == "" {
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

	token := parsedBody["token"]
	receivedOtp := parsedBody["otp"]

	if token == "" || receivedOtp == "" {
		http.Error(w, "Missing required fields: token, otp", http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	app, errFirebaseAdmin := utils2.InitializeFirebase(ctx)
	if errFirebaseAdmin != nil {
		log.Error("error initialize firebase admin", zap.String("error", errFirebaseAdmin.Error()))
		http.Error(w, "Firebase admin initialization error", http.StatusInternalServerError)
		return
	}

	rtdb, errDb := app.Database(ctx)
	if errDb != nil {
		log.Error("error realtime db", zap.String("error", errDb.Error()))
		http.Error(w, "Realtime DB error", http.StatusInternalServerError)
		return
	}

	fs, errFs := app.Firestore(ctx)
	if errFs != nil {
		log.Error("error firestore client", zap.String("error", errFs.Error()))
		http.Error(w, "Firestore client error", http.StatusInternalServerError)
		return
	}
	defer fs.Close()

	collectionPrefix := utils2.GetCollectionPrefix()

	deps := VerifyOtpDeps{
		ReadOtp: func(ctx context.Context, t string) (map[string]any, error) {
			var data map[string]any
			if err := rtdb.NewRef("otp/"+t).Get(ctx, &data); err != nil {
				return nil, err
			}
			return data, nil
		},
		DeleteOtp: func(ctx context.Context, t string) error {
			return rtdb.NewRef("otp/" + t).Delete(ctx)
		},
		UpdateUser: func(ctx context.Context, uid string, fields map[string]any) error {
			docRef := fs.Doc(collectionPrefix + "users/" + uid)

			// If the caller passed a verificationStatus_or bit, fold it into
			// the user's existing verificationStatus via OR — preserves any
			// previously-set verification bits (email, etc.).
			update := make(map[string]any, len(fields)+1)
			for k, v := range fields {
				if k == "verificationStatus_or" {
					continue
				}
				update[k] = v
			}

			if maskAny, ok := fields["verificationStatus_or"]; ok {
				var mask int64
				switch m := maskAny.(type) {
				case int:
					mask = int64(m)
				case int64:
					mask = m
				case float64:
					mask = int64(m)
				default:
					return errors.New("verificationStatus_or must be numeric")
				}

				snap, errSnap := docRef.Get(ctx)
				if errSnap != nil {
					return errSnap
				}
				var current int64
				if snap.Exists() {
					if v, ok := snap.Data()["verificationStatus"]; ok {
						switch n := v.(type) {
						case int64:
							current = n
						case int:
							current = int64(n)
						case float64:
							current = int64(n)
						}
					}
				}
				update["verificationStatus"] = current | mask
			}

			update["updated_at"] = time.Now().UTC()

			_, err := docRef.Set(ctx, update, firestore.MergeAll)
			return err
		},
		Now: time.Now,
	}

	verified, err := VerifyOtpCore(ctx, token, receivedOtp, deps)
	if err != nil {
		switch {
		case errors.Is(err, ErrOtpNotFound):
			http.Error(w, "OTP not found", http.StatusBadRequest)
		case errors.Is(err, ErrOtpExpired):
			http.Error(w, "OTP expired", http.StatusBadRequest)
		case errors.Is(err, ErrOtpInvalid):
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]any{"verified": false, "message": "Invalid OTP"})
		default:
			log.Error("verify otp internal error", zap.String("error", err.Error()))
			http.Error(w, "Verify OTP error", http.StatusInternalServerError)
		}
		return
	}

	if !verified {
		// Defensive: VerifyOtpCore should only return verified=false alongside
		// an error, but cover the case explicitly.
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"verified": false, "message": "Invalid OTP"})
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]any{"verified": true})
}
