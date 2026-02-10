package types

import "github.com/golang-jwt/jwt/v4"

type CustomTokenClaims struct {
	jwt.RegisteredClaims
	UID string `json:"uid,omitempty"`
}
