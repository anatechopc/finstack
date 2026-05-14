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
		_, errSendMail := utils2.SendEmail("Verify your email — Loooans!", createHtmlBody(otp), []string{fmt.Sprintf("%v", userDetails["email"])})

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
