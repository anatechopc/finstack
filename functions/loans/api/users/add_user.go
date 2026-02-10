package users

import (
	"com.loooans.app/types"
	utils2 "com.loooans.app/utils"
	"context"
	"encoding/json"
	"firebase.google.com/go/v4/auth"
	"fmt"
	"io"
	"net/http"
	"os"
)

func AddUser(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils2.InitializeLogger("add_user")

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
	//log.Debug("body: " + string(body))

	//var parsedBody map[string]any
	var parsedBody types.User
	errJson := json.Unmarshal(body, &parsedBody)

	if errJson != nil {
		http.Error(w, errJson.Error(), http.StatusInternalServerError)
		return
	}

	if !utils2.ValidateUser(parsedBody) {
		http.Error(w, "Enter required user details", http.StatusInternalServerError)
		return
	}

	ctx := context.Background()
	app, err := utils2.InitializeFirebase(ctx)

	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	authClient, errAuth := app.Auth(ctx)

	if errAuth != nil {
		http.Error(w, errAuth.Error(), http.StatusInternalServerError)
		return
	}

	log.Info("adding user to auth ")

	tmpUser := (&auth.UserToCreate{}).
		DisplayName(parsedBody.DisplayName).
		Email(parsedBody.Email).
		Password(parsedBody.Password)
	record, errCreateUser := authClient.CreateUser(ctx, tmpUser)

	if errCreateUser != nil {
		http.Error(w, errCreateUser.Error(), http.StatusInternalServerError)
		return
	}

	// send email
	env := os.Getenv("ENVIRONMENT")
	subdomain := ""

	switch env {
	case "development":
		subdomain = "dev."
		break
	case "staging":
		subdomain = "stg."
		break
	}

	emailBody := fmt.Sprintf(`Hi %s!<br><br>Thank you for registering!<br><br>Here is your credentials:<br>Email: %s<br>Password: %s.<br><br>Use your email and password to login into the app. Go to <a href="https://%s.loooans.com/login">Ayooo!</a>`, parsedBody.DisplayName, parsedBody.Email, parsedBody.Password, subdomain)
	_, errSendEmail := utils2.SendEmail("Thank you", emailBody, []string{record.Email})

	if errSendEmail != nil {
		log.Error(fmt.Sprintf("Cannot send email: %s", errSendEmail.Error()))
		http.Error(w, errSendEmail.Error(), http.StatusInternalServerError)
		return
	}

	//json.NewEncoder(w).Encode("didSend true")

	something := make(map[string]any)
	something["message"] = "Successfully added user"
	something["data"] = map[string]any{
		"uid":   record.UID,
		"name":  record.DisplayName,
		"email": record.Email,
	}

	errParse := json.NewEncoder(w).Encode(something)
	if errParse != nil {
		http.Error(w, errParse.Error(), http.StatusBadRequest)
		return
	}
}
