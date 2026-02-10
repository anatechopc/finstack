package users

import (
	utils2 "com.loooans.app/utils"
	"context"
	"firebase.google.com/go/v4/auth"
	"fmt"
	"net/http"
	"strings"
)

func VerifyUserEmail(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("verify_user_email")

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

	tempUserToUpdate := (&auth.UserToUpdate{}).EmailVerified(true)

	_, errUpdatedUser := authClient.UpdateUser(ctx, userId, tempUserToUpdate)

	if errUpdatedUser != nil {
		log.Error("error verify email: " + errUpdatedUser.Error())
		http.Error(w, "Failed to verify email: "+errUpdatedUser.Error(), http.StatusInternalServerError)
		return
	}

	_, errSendMail := utils2.SendEmail("Email verified", createVerifyUserEmailHtmlBody(), []string{fmt.Sprintf("%v", user.Email)})

	if errSendMail != nil {
		http.Error(w, errSendMail.Error(), http.StatusInternalServerError)
	}
}

func createVerifyUserEmailHtmlBody() string {
	/**
	Hi.

	Thank you for registering.
	To continue using the app, you need to have a valid email address.
	Please enter the one time pin below in the device.

	123456

	Please note that the one time pin is valid only for 5 minutes.

	If you did not request for this email, please ignore.
	*/
	return fmt.Sprintf("<h3>Hi.</h3><p>Your email address has been verified.</p><p></br>Best regards,</br></br>Ayooo! team</p>")
}
