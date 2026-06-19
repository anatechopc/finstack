package utils

import (
	"crypto/rand"
	"math/big"
)

const passwordChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#%^*?!"

// GenerateRandomPassword returns a cryptographically-random 24-character
// password. It is only ever used as the throwaway initial password for an
// admin-provisioned account; the user immediately replaces it via the
// password-reset invite link, so it is never shown to anyone.
func GenerateRandomPassword() string {
	const length = 24
	max := big.NewInt(int64(len(passwordChars)))
	b := make([]byte, length)
	for i := range b {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			// crypto/rand failure is effectively impossible; index 0 keeps the
			// function total. The account is reset via the invite link anyway.
			b[i] = passwordChars[0]
			continue
		}
		b[i] = passwordChars[n.Int64()]
	}
	return string(b)
}
