package utils_test

import (
	"strings"
	"testing"

	"com.loooans.app/utils"
)

// allowedPasswordChars mirrors utils.passwordChars (which is unexported). Every
// rune of a generated password must be a member of this set.
const allowedPasswordChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#%^*?!"

func TestGenerateRandomPassword_LengthAndVariation(t *testing.T) {
	a := utils.GenerateRandomPassword()
	b := utils.GenerateRandomPassword()

	if len(a) != 24 {
		t.Fatalf("expected length 24, got %d (%q)", len(a), a)
	}
	if a == b {
		t.Fatalf("expected two random passwords to differ, both were %q", a)
	}
	for _, r := range a {
		if !strings.ContainsRune(allowedPasswordChars, r) {
			t.Fatalf("password %q contains disallowed rune %q", a, r)
		}
	}
}
