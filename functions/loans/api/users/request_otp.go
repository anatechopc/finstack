package users

import (
	"com.loooans.app/api/service"
	utils2 "com.loooans.app/utils"
	"context"
	"encoding/json"
	"fmt"
	"go.uber.org/zap"
	"io"
	"net/http"
	"time"
)

func RequestOtp(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("request_otp")

	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	// cors
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
	// cors done

	var userId string

	if uid := utils2.ValidateRequestV2(w, r); uid == "" {
		return
	} else {
		userId = uid
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

	errJson := json.Unmarshal(body, &parsedBody)

	if errJson != nil {
		http.Error(w, errJson.Error(), http.StatusInternalServerError)
		return
	}

	var otpObjective string

	if otpFor, ok := parsedBody["purpose"]; ok && otpFor != "" {
		if otpFor == "email" || otpFor == "mobile_number" {
			otpObjective = otpFor
		} else {
			http.Error(w, "Request for OTP objective not valid.", http.StatusBadRequest)
			return
		}
	} else {
		http.Error(w, "Cannot generate OTP. Missing field `for`", http.StatusBadRequest)
		return
	}

	// Determine target user
	targetUserId := userId
	if tuid, ok := parsedBody["target_user_id"]; ok && tuid != "" {
		targetUserId = tuid
	}

	// Determine reason (defaults based on objective)
	reason := "mobile_verification"
	if otpObjective == "email" {
		reason = "email_verification"
	}
	if r, ok := parsedBody["reason"]; ok && r != "" {
		reason = r
	}

	subdomain := utils2.GetSubdomain()
	collectionPrefix := utils2.GetCollectionPrefix()

	hash, otp, errOtp := service.GenerateOtp()

	if errOtp != nil {
		log.Error("error otp: " + errOtp.Error())
		http.Error(w, "Otp generation error: "+errOtp.Error(), http.StatusInternalServerError)
		return
	}

	ctx := context.Background()
	app, errFirebaseAdmin := utils2.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		log.Error("error initialize firebase admin: " + errFirebaseAdmin.Error())
		http.Error(w, "Firebase admin initialization error: "+errFirebaseAdmin.Error(), http.StatusInternalServerError)
		return
	}

	db, errDb := app.Database(ctx)

	if errDb != nil {
		log.Error("error realtime db: " + errDb.Error())
		http.Error(w, "Realtime DB error: "+errDb.Error(), http.StatusInternalServerError)
		return
	}

	firestoreClient, errFirestoreClient := app.Firestore(ctx)

	if errFirestoreClient != nil {
		log.Error("error firestore client: " + errFirestoreClient.Error())
		http.Error(w, "error firestore client: "+errFirestoreClient.Error(), http.StatusInternalServerError)
		return
	}

	userRef := firestoreClient.Doc(collectionPrefix + "users/" + targetUserId)
	snapshot, errSnapshot := userRef.Get(ctx)

	if errSnapshot != nil {
		log.Error("error firestore user snapshot: " + errSnapshot.Error())
		http.Error(w, "error firestore user snapshot: "+errSnapshot.Error(), http.StatusInternalServerError)
		return
	}

	userDetails := snapshot.Data()

	if userDetails == nil {
		log.Error("User not found")
		http.Error(w, "User not found.", http.StatusInternalServerError)
		return
	}

	dbClient := db.NewRef("otp/" + hash)
	timeNow := time.Now().UTC()
	expireAt := timeNow.Add(time.Minute * 5).UnixMilli()

	otpData := map[string]any{
		"id":           hash,
		"userId":       targetUserId,
		"otp":          otp,
		"expire_at":    expireAt,
		"created_at":   timeNow.UnixMilli(),
		"updated_at":   timeNow.UnixMilli(),
		"deleted_at":   nil,
		"objective":    otpObjective,
		"reason":       reason,
		"requested_by": userId,
	}

	if otpObjective == "mobile_number" {
		phone := userDetails["mobile_number"].(string)
		otpData["phone"] = phone
		otpData["message"] = fmt.Sprintf(
			"NEVER SHARE YOUR ONE-TIME PIN. Your Loooans OTP is %s. If you did not request for OTP, please contact support at support@loooans.com immediately.", otp)
		otpData["sms_status"] = "pending"
		otpData["sent_at"] = nil
		otpData["error"] = nil
	}

	dbSetErr := dbClient.Set(ctx, otpData)

	if dbSetErr != nil {
		log.Error("error realtime db SET: " + dbSetErr.Error())
		http.Error(w, "Realtime DB error SET: "+dbSetErr.Error(), http.StatusInternalServerError)
		return
	}

	if otpObjective == "email" {
		_, errSendMail := utils2.SendEmail("OTP", createHtmlBody(otp, fmt.Sprintf("%sloooans.com/verify?vid=%s", subdomain, hash)), []string{fmt.Sprintf("%v", userDetails["email"])})

		if errSendMail != nil {
			http.Error(w, errSendMail.Error(), http.StatusInternalServerError)
			return
		}

		dataSend := map[string]any{
			"redirect_url": fmt.Sprintf("%sloooans.com/verify?vid=%s", subdomain, hash),
			"token":        hash,
			"expire_at":    expireAt,
		}

		if encodeErr := json.NewEncoder(w).Encode(dataSend); encodeErr != nil {
			log.Error("Send encode error", zap.String("error", encodeErr.Error()))
			http.Error(w, "Send encode error", http.StatusInternalServerError)
			return
		}
	} else if otpObjective == "mobile_number" {
		dataSend := map[string]any{
			"redirect_url": fmt.Sprintf("%sloooans.com/verify?vid=%s", subdomain, hash),
			"token":        hash,
			"expire_at":    expireAt,
		}

		if encodeErr := json.NewEncoder(w).Encode(dataSend); encodeErr != nil {
			log.Error("Send encode error", zap.String("error", encodeErr.Error()))
			http.Error(w, "Send encode error", http.StatusInternalServerError)
			return
		}
	} else {
		log.Error("Invalid OTP objective", zap.String("objective", otpObjective))
		http.Error(w, "Invalid OTP objective", http.StatusBadRequest)
	}
}

func createHtmlBody(otp string, domain string) string {
	/**
	Hi.

	Thank you for registering.
	To continue using the app, you need to have a valid email address.
	Please enter the one time pin below in the device.

	123456

	Please note that the one time pin is valid only for 5 minutes.

	If you did not request for this email, please ignore.
	*/
	return fmt.Sprintf("<h3>Hi.</h3><p>Thank you for registering.</br>To continue using the app, you need to have a valid email address.</br>Please enter the one time pin below in the app.</p><p>%s</p><p>%s</p><p>Please note that the one time pin is valid only for 5 minutes.</p><p>If you did not make this request, please ignore.</p><p></br>Best regards,</br></br>Loooans! team</p>", otp, domain)
}
