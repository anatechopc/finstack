package utils_test

import (
	"testing"

	"com.loooans.app/utils"
)

func TestGenerateRandomPassword_LengthAndVariation(t *testing.T) {
	a := utils.GenerateRandomPassword()
	b := utils.GenerateRandomPassword()

	if len(a) != 24 {
		t.Fatalf("expected length 24, got %d (%q)", len(a), a)
	}
	if a == b {
		t.Fatalf("expected two random passwords to differ, both were %q", a)
	}
}
