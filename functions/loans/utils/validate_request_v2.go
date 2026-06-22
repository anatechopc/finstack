package utils

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"go.uber.org/zap"
)

// ValidateRequestV2
//
// Checks the request if it is valid and authorized
// It searches for the Authorization header and checks
// the value, gets the JWT string from the value and
// checks if the JWT is valid thru firebase auth
//
// returns the UID of the requester, or "" (having already written the
// appropriate HTTP error) if the request is unauthorized.
func ValidateRequestV2(w http.ResponseWriter, r *http.Request) string {
	var log *zap.Logger

	if l, err := InitializeLogger("validate_request"); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return ""
	} else {
		log = l
	}

	authorization := r.Header.Get("Authorization")

	if authorization == "" {
		log.Error("Authorization not found")
		http.Error(w, "Authorization not found", http.StatusUnauthorized)
		return ""
	}

	ctx := context.Background()
	app, err := InitializeFirebase(ctx)

	if err != nil {
		log.Error(fmt.Sprintf("Firebase Error: %s", err.Error()))
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return ""
	}

	authClient, errAuthClient := app.Auth(ctx)

	if errAuthClient != nil {
		log.Error(fmt.Sprintf("Firebase Auth error: %s", errAuthClient.Error()))
		http.Error(w, errAuthClient.Error(), http.StatusUnauthorized)
		return ""
	}

	parts := strings.Split(authorization, " ")
	if len(parts) < 2 || parts[1] == "" {
		log.Error("malformed Authorization header")
		http.Error(w, "Malformed Authorization header", http.StatusUnauthorized)
		return ""
	}
	idToken := parts[1]

	token, errToken := authClient.VerifyIDToken(ctx, idToken)
	if errToken != nil {
		log.Error("invalid id token", zap.String("error", errToken.Error()))
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return ""
	}

	return token.UID
}
