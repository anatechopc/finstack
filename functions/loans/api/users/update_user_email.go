package users

import (
	utils2 "com.loooans.app/utils"
	"context"
	"encoding/json"
	"firebase.google.com/go/v4/auth"
	"fmt"
	"io"
	"net/http"
	"strings"
)

func UpdateUserEmail(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("update_user_email")

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

	if !utils2.ValidateRequest(w, r) {
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

	var parsedBody map[string]any
	errJson := json.Unmarshal(body, &parsedBody)

	if errJson != nil {
		http.Error(w, errJson.Error(), http.StatusInternalServerError)
		return
	}

	isVerified, isVerifiedOk := parsedBody["is_verified"].(bool)
	emailAddress, emailOk := parsedBody["email_address"].(string)

	if !emailOk {
		http.Error(w, "Email address not found", http.StatusInternalServerError)
		return
	}

	if !isVerifiedOk {
		http.Error(w, "is_verified not found", http.StatusInternalServerError)
		return
	}

	bearer := r.Header.Get("Authorization")
	idToken := strings.Split(bearer, " ")[1]

	ctx := context.Background()
	app, errFirebaseAdmin := utils2.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		log.Error("error initialize firebase admin: " + errFirebaseAdmin.Error())
		http.Error(w, "Firebase admin initialization error: "+errFirebaseAdmin.Error(), http.StatusInternalServerError)
		return
	}

	authClient, errAuth := app.Auth(ctx)

	if errAuth != nil {
		log.Error("error firebase auth: " + errAuth.Error())
		http.Error(w, errAuth.Error(), http.StatusInternalServerError)
		return
	}

	verifiedIdToken, errVerifyIdToken := authClient.VerifyIDToken(ctx, idToken)

	if errVerifyIdToken != nil {
		log.Error("error verify id token: " + errVerifyIdToken.Error())
		http.Error(w, "Id Token verification error: "+errVerifyIdToken.Error(), http.StatusInternalServerError)
		return
	}

	userId := verifiedIdToken.UID

	user, errUser := authClient.GetUser(ctx, userId)

	if errUser != nil {
		log.Error("error get user: " + errUser.Error())
		http.Error(w, "Failed to retrieve user details: "+errUser.Error(), http.StatusInternalServerError)
		return
	}

	tempUserToUpdate := (&auth.UserToUpdate{}).
		EmailVerified(isVerified).
		Email(emailAddress)

	_, errUpdatedUser := authClient.UpdateUser(ctx, userId, tempUserToUpdate)

	if errUpdatedUser != nil {
		log.Error("error verify emailAddress: " + errUpdatedUser.Error())
		http.Error(w, "Failed to verify emailAddress: "+errUpdatedUser.Error(), http.StatusInternalServerError)
		return
	}

	extendedSubject := ""

	if !isVerified {
		extendedSubject = ". Please verify your emailAddress"
	}

	_, errSendMail := utils2.SendEmail(
		fmt.Sprintf("Email updated%s", extendedSubject),
		createUpdateUserEmailHtmlBody(isVerified),
		[]string{fmt.Sprintf("%v", user.Email)})

	if errSendMail != nil {
		http.Error(w, errSendMail.Error(), http.StatusInternalServerError)
	}

	something := make(map[string]any)
	something["message"] = "Successfully updated user email"

	errParse := json.NewEncoder(w).Encode(something)
	if errParse != nil {
		http.Error(w, errParse.Error(), http.StatusBadRequest)
		return
	}
	log.Info("Function executed successfully")
}

func createUpdateUserEmailHtmlBody(isVerified bool) string {
	/**
	Hi.

	Thank you for registering.
	To continue using the app, you need to have a valid email address.
	Please enter the one time pin below in the device.

	123456

	Please note that the one time pin is valid only for 5 minutes.

	If you did not request for this email, please ignore.
	*/

	if isVerified {
		return fmt.Sprintf("<h3>Hi.</h3><p>Your email address has been updated and verified.</p><p></br>Best regards,</br></br>Ayooo! team</p>")
	}

	return fmt.Sprintf("<h3>Hi.</h3><p>Your email address has been updated but it needs to be verified. If you are logged in into Ayooo!, please logout and login again to verify your email..</p><p></br>Best regards,</br></br>Ayooo! team</p>")
}
