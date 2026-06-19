package utils

import (
	"com.loooans.app/types"
	"context"
	"fmt"
	"github.com/golang-jwt/jwt/v4"
	"go.uber.org/zap"
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
// returns the UID of the requester
const customTokenAud = "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit"

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
	//log.Debug("idToken")
	//log.Debug(idToken)

	var uid string

	token, errToken := authClient.VerifyIDToken(ctx, idToken)
	if errToken != nil {
		parser := jwt.NewParser(jwt.WithoutClaimsValidation())
		tok, _, errTok := parser.ParseUnverified(idToken, &types.CustomTokenClaims{})

		if errTok != nil {
			log.Error("token parse error: ", zap.String("error", errTok.Error()))
			http.Error(w, errTok.Error(), http.StatusUnauthorized)
			return ""
		}

		if claims, ok := tok.Claims.(*types.CustomTokenClaims); ok {
			// check aud claims
			if !claims.VerifyAudience(customTokenAud, true) {
				log.Error("Invalid audience")
				http.Error(w, "Invalid audience", http.StatusUnauthorized)
				return ""
			}

			//if !claims.VerifyExpiresAt(time.Now(), true) {
			//	log.Error("Token expired")
			//	http.Error(w, "Token expired", http.StatusBadRequest)
			//	return ""
			//}

			if claims.UID == "" {
				log.Error("uid not found")
				http.Error(w, "uid not found", http.StatusUnauthorized)
				return ""
			}

			uid = claims.UID
		} else {
			log.Error("claims parse error")
			http.Error(w, errToken.Error(), http.StatusUnauthorized)
			return ""
		}
	} else {
		uid = token.UID
	}

	return uid
}
