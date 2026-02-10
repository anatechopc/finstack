package utils

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

func SendEmailHttp(w http.ResponseWriter, r *http.Request) {
	log, errLog := InitializeLogger("send_email_http")

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

	uid := ValidateRequestV2(w, r)

	if uid == "" {
		log.Error("UID not found.")
		return
	}

	defer r.Body.Close()

	var body map[string]interface{}
	errBody := json.NewDecoder(r.Body).Decode(&body)

	if errBody != nil {
		http.Error(w, errBody.Error(), http.StatusBadRequest)
		return
	}

	var action string

	if vAction, ok := body["action"]; ok && vAction != "" {
		action = vAction.(string)
	} else {
		http.Error(w, "Body does not have action field in it", http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	var err error

	if app, appErr := InitializeFirebase(ctx); appErr == nil {
		if authClient, authErr := app.Auth(ctx); authErr == nil {
			if user, userErr := authClient.GetUser(ctx, uid); userErr == nil {
				if sendMailActionErr := SendEmailActions(action, []string{user.Email}); err != nil {
					err = sendMailActionErr
				} else {
					json.NewEncoder(w).Encode("Send email success")
					return
				}
			} else {
				err = userErr
			}
		} else {
			err = authErr
		}
	} else {
		err = appErr
	}

	http.Error(w, fmt.Sprintf("Something went wrong: %s", err.Error()), http.StatusInternalServerError)
}
