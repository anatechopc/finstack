package service_test

import (
	"errors"
	"strings"
	"testing"

	"com.loooans.app/api/service"
)

func TestNormalizePhoneE164(t *testing.T) {
	cases := []struct {
		name    string
		number  string
		country string
		want    string
		wantErr error // nil means success
	}{
		{"bare 10-digit PH", "9175551291", "Philippines", "+639175551291", nil},
		{"national 0-prefixed PH", "09175551291", "Philippines", "+639175551291", nil},
		{"whitespace and case tolerated", " 9175551291 ", "  philippines ", "+639175551291", nil},
		{"already E.164, empty country", "+639175551291", "", "+639175551291", nil},
		{"already E.164, unknown country", "+639175551291", "Narnia", "+639175551291", nil},
		{"unknown country", "9175551291", "Narnia", "", service.ErrCountryUnknown},
		{"empty country", "9175551291", "", "", service.ErrCountryUnknown},
		{"too short for PH", "12345", "Philippines", "", service.ErrPhoneInvalid},
		{"ten digits but not a PH number", "1234567890", "Philippines", "", service.ErrPhoneInvalid},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := service.NormalizePhoneE164(tc.number, tc.country)
			if tc.wantErr != nil {
				if !errors.Is(err, tc.wantErr) {
					t.Fatalf("want error %v, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("want %q, got %q", tc.want, got)
			}
		})
	}
}

// TestNormalizePhoneE164_RejectsNonMobileAndAlpha covers the defects found in
// the 2026-08-12 review, each reproduced against the real library before the
// fix: letters were silently converted to digits (delivering the OTP to an
// unrelated subscriber), landlines passed validation, and malformed
// RFC3966-shaped input panicked the parser.
func TestNormalizePhoneE164_RejectsNonMobileAndAlpha(t *testing.T) {
	cases := []struct {
		name    string
		number  string
		country string
	}{
		// Keypad alpha-to-digit conversion turned this into +639175666267,
		// a valid number belonging to someone else entirely.
		{"uppercase letters", "0917LOOOANS", "Philippines"},
		{"lowercase letters", "0917loooans", "Philippines"},
		{"letters without trunk prefix", "917LOOOANS", "Philippines"},
		// Valid per IsValidNumber, but a fixed line cannot receive an SMS.
		{"landline", "0288887777", "Philippines"},
		// These panicked the parser on the previously pinned v1.1.8.
		{"rfc3966 phone-context", "9175551291;phone-context=x tel:y", "Philippines"},
		{"rfc3966 short", "1;phone-context=+63tel:1", "Philippines"},
		{"rfc3966 alpha", "abc;phone-context=+63tel:12345", "Philippines"},
		{"empty", "", "Philippines"},
		{"whitespace only", "   ", "Philippines"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := service.NormalizePhoneE164(tc.number, tc.country)
			if !errors.Is(err, service.ErrPhoneInvalid) {
				t.Fatalf("want ErrPhoneInvalid, got err=%v result=%q", err, got)
			}
			if got != "" {
				t.Errorf("want empty result on rejection, got %q", got)
			}
			if strings.Contains(err.Error(), tc.number) && tc.number != "" && len(tc.number) > 3 {
				t.Errorf("error text leaked the raw number: %v", err)
			}
		})
	}
}

// TestNormalizePhoneE164_CountryAliases: the profile editor exposes `country`
// as free text, so a user typing "PH" must not be locked out of OTP entirely.
func TestNormalizePhoneE164_CountryAliases(t *testing.T) {
	for _, country := range []string{
		"Philippines", "philippines", "  Philippines  ", "PHILIPPINES",
		"PH", "ph", "Phl", "Pilipinas", "the Philippines",
		"Republic of the Philippines",
	} {
		t.Run(country, func(t *testing.T) {
			got, err := service.NormalizePhoneE164("9175551291", country)
			if err != nil {
				t.Fatalf("country %q should resolve, got %v", country, err)
			}
			if got != "+639175551291" {
				t.Errorf("want +639175551291, got %q", got)
			}
		})
	}
}

func TestNormalizePhoneE164_StillRejectsUnknownCountry(t *testing.T) {
	if _, err := service.NormalizePhoneE164("9175551291", "Narnia"); !errors.Is(err, service.ErrCountryUnknown) {
		t.Fatalf("want ErrCountryUnknown, got %v", err)
	}
}
