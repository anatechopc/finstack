package users

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"time"
)

// setPasswordTokenTTL is how long a set-password / reset link stays valid.
const setPasswordTokenTTL = 24 * time.Hour

// GenerateSetPasswordToken returns a cryptographically-random URL-safe token
// (for the email link) and its SHA-256 hex hash (the only thing persisted, so a
// store leak yields no usable tokens).
func GenerateSetPasswordToken() (raw, hash string, err error) {
	b := make([]byte, 32)
	if _, rErr := rand.Read(b); rErr != nil {
		return "", "", fmt.Errorf("generate token: %w", rErr)
	}
	raw = base64.RawURLEncoding.EncodeToString(b)
	hash = HashSetPasswordToken(raw)
	return raw, hash, nil
}

// HashSetPasswordToken returns the SHA-256 hex of a raw token (used both when
// persisting on send and when looking up on consume).
func HashSetPasswordToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
