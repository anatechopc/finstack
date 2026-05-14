package users

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/api/service"
	utils2 "com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"

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
	reasonEmailVerification  = "email_verification"
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

	var expireAtMs int64
	switch v := otpData["expire_at"].(type) {
	case float64:
		expireAtMs = int64(v)
	case int64:
		expireAtMs = v
	case int:
		expireAtMs = int64(v)
	default:
		return false, ErrOtpNotFound
	}
	if deps.Now().UTC().UnixMilli() > expireAtMs {
		return false, ErrOtpExpired
	}

	verified, errVerify := service.VerifyOtp(token, receivedOtp)
	if errVerify != nil {
		return false, fmt.Errorf("otp service error: %w", errVerify)
	}
	if !verified {
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
			return false, fmt.Errorf("mobile_verification otp entry missing userId")
		}
		if upErr := deps.UpdateUser(ctx, uid, map[string]any{
			"verificationStatus_or": verificationBitMobileNumber,
			"mobile_verified_at":    deps.Now().UTC(),
		}); upErr != nil {
			return true, upErr
		}
	case reasonEmailVerification:
		uid, _ := otpData["userId"].(string)
		if uid == "" {
			return false, fmt.Errorf("email_verification otp entry missing userId")
		}
		// firebase_email_verified is a sentinel field the adapter interprets
		// as a Firebase Auth Admin SDK UpdateUser call (EmailVerified(true)),
		// not a Firestore write. We rely on Firebase Auth itself as the
		// source of truth for emailVerified; the Flutter app reads it via
		// FirebaseAuth.instance.currentUser?.emailVerified after a reload.
		if upErr := deps.UpdateUser(ctx, uid, map[string]any{
			"firebase_email_verified": true,
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
		http.Error(w, errJson.Error(), http.StatusBadRequest)
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

	authClient, errAuth := app.Auth(ctx)
	if errAuth != nil {
		log.Error("error firebase auth client", zap.String("error", errAuth.Error()))
		http.Error(w, "Firebase auth client error", http.StatusInternalServerError)
		return
	}

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
			// firebase_email_verified is a sentinel — flips the Firebase Auth
			// user's emailVerified flag via Admin SDK. Not a Firestore write.
			if v, ok := fields["firebase_email_verified"].(bool); ok && v {
				update := (&auth.UserToUpdate{}).EmailVerified(true)
				if _, err := authClient.UpdateUser(ctx, uid, update); err != nil {
					return fmt.Errorf("auth UpdateUser EmailVerified: %w", err)
				}
			}

			// Firestore writes — only run the transaction if there's a
			// Firestore-shaped field in the input. Avoids an unnecessary
			// Get+Set when we only touched Firebase Auth.
			_, fsOr := fields["verificationStatus_or"]
			_, fsAt := fields["mobile_verified_at"]
			if !fsOr && !fsAt {
				return nil
			}

			docRef := fs.Doc(collectionPrefix + "users/" + uid)
			now := time.Now().UTC()
			return fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
				snap, err := tx.Get(docRef)
				if err != nil {
					return err
				}
				// Store timestamps as int64 milliseconds since epoch to match
				// the codebase convention (Flutter's json_serializable
				// helpers expect `num` millis). The Firestore Admin SDK
				// would otherwise serialise Go time.Time as a Firestore
				// Timestamp protocol object, breaking client deserialisation.
				update := map[string]any{
					"updated_at": now.UnixMilli(),
				}
				if v, ok := fields["verificationStatus_or"].(int); ok {
					current, _ := snap.Data()["verificationStatus"].(int64)
					update["verificationStatus"] = current | int64(v)
				}
				if t, ok := fields["mobile_verified_at"].(time.Time); ok {
					update["mobile_verified_at"] = t.UnixMilli()
				}
				return tx.Set(docRef, update, firestore.MergeAll)
			})
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
