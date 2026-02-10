package utils

import (
	"context"
	"net/http"
	"strings"
)

// ValidateRequest
//
// Checks the request if it is valid and authorized
// It searches for the Authorization header and checks
// the value, gets the JWT string from the value and
// checks if the JWT is valid thru firebase auth
//
// returns true if the request is valid
func ValidateRequest(w http.ResponseWriter, r *http.Request) bool {
	authorization := r.Header.Get("Authorization")

	if authorization == "" {
		http.Error(w, "Authorization not found", http.StatusUnauthorized)
		return false
	}

	ctx := context.Background()
	app, err := InitializeFirebase(ctx)

	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return false
	}

	authClient, errAuthClient := app.Auth(ctx)

	if errAuthClient != nil {
		http.Error(w, errAuthClient.Error(), http.StatusUnauthorized)
		return false
	}

	idToken := strings.Split(authorization, " ")[1]

	_, errToken := authClient.VerifyIDToken(ctx, idToken)

	if errToken != nil {
		http.Error(w, errToken.Error(), http.StatusUnauthorized)
		return false
	}

	return true
}
