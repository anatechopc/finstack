package users

import (
	"com.loooans.app/api/service"
	utils2 "com.loooans.app/utils"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"go.uber.org/zap"
)

func VerifyPaymentOtp(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("verify_payment_otp")
	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	// CORS
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

	// Parse body
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

	// Read OTP from RTDB
	ctx := context.Background()
	app, errFirebaseAdmin := utils2.InitializeFirebase(ctx)
	if errFirebaseAdmin != nil {
		log.Error("error initialize firebase admin", zap.String("error", errFirebaseAdmin.Error()))
		http.Error(w, "Firebase admin initialization error", http.StatusInternalServerError)
		return
	}

	db, errDb := app.Database(ctx)
	if errDb != nil {
		log.Error("error realtime db", zap.String("error", errDb.Error()))
		http.Error(w, "Realtime DB error", http.StatusInternalServerError)
		return
	}

	dbRef := db.NewRef("otp/" + token)
	var otpData map[string]any
	if err := dbRef.Get(ctx, &otpData); err != nil {
		log.Error("error reading otp", zap.String("error", err.Error()))
		http.Error(w, "OTP not found", http.StatusBadRequest)
		return
	}

	if otpData == nil {
		http.Error(w, "OTP not found", http.StatusBadRequest)
		return
	}

	// Check expiry
	expireAt, ok := otpData["expire_at"].(float64)
	if !ok {
		http.Error(w, "Invalid OTP data", http.StatusInternalServerError)
		return
	}

	if time.Now().UTC().UnixMilli() > int64(expireAt) {
		http.Error(w, "OTP expired", http.StatusBadRequest)
		return
	}

	// Verify OTP using the service
	verified, errVerify := service.VerifyOtp(token, receivedOtp)
	if errVerify != nil {
		log.Error("error verifying otp", zap.String("error", errVerify.Error()))
		http.Error(w, "OTP verification error", http.StatusInternalServerError)
		return
	}

	if verified {
		// Delete the OTP entry
		if err := dbRef.Delete(ctx); err != nil {
			log.Error("error deleting otp", zap.String("error", err.Error()))
		}
		json.NewEncoder(w).Encode(map[string]any{"verified": true})
	} else {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]any{"verified": false, "message": "Invalid OTP"})
	}
}
