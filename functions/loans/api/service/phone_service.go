package service

import (
	"errors"
	"fmt"
	"strings"

	"github.com/nyaruka/phonenumbers"
)

// Errors returned by NormalizePhoneE164. The users package maps these to
// its HTTP-facing sentinels — service cannot import users (import cycle).
var (
	ErrCountryUnknown = errors.New("unknown country")
	ErrPhoneInvalid   = errors.New("invalid phone number")
)

// countryToRegion maps the free-text address `country` value (trimmed,
// lower-cased) to an ISO 3166-1 alpha-2 region for libphonenumber. The
// registration form hardcodes "Philippines", but the profile editor exposes
// the field as free text, so the common variants a user might type are
// accepted rather than locking them out of OTP entirely. Extend when new
// countries are onboarded.
var countryToRegion = map[string]string{
	"philippines":                 "PH",
	"the philippines":             "PH",
	"republic of the philippines": "PH",
	"pilipinas":                   "PH",
	"ph":                          "PH",
	"phl":                         "PH",
}

// dialableChars are the only characters allowed to reach the parser. Letters
// are deliberately excluded: libphonenumber applies keypad alpha-to-digit
// conversion, so "0917LOOOANS" would parse as a different, perfectly valid
// subscriber number and the OTP would be delivered to a stranger. Excluding
// ';' and ':' also keeps RFC3966-shaped input away from the parser.
func isDialable(s string) bool {
	for _, r := range s {
		switch {
		case r >= '0' && r <= '9':
		case r == '+', r == '-', r == ' ', r == '(', r == ')', r == '.':
		default:
			return false
		}
	}
	return true
}

// NormalizePhoneE164 parses a stored mobile number against the user's
// country and returns it in E.164 form ("9175551291" + "Philippines" →
// "+639175551291"). Numbers already carrying a "+" prefix parse
// independently of the region hint, so well-formed legacy values pass
// through even when countryName is empty or unknown.
func NormalizePhoneE164(number, countryName string) (normalized string, err error) {
	// mobile_number is written client-side straight to Firestore, so this
	// parser runs on attacker-controllable input. libphonenumber has panicked
	// on malformed RFC3966-shaped values; a panic here would escape into
	// funcframework and become a 500 for what should be a 400.
	defer func() {
		if r := recover(); r != nil {
			normalized = ""
			err = fmt.Errorf("%w: parser rejected the stored value", ErrPhoneInvalid)
		}
	}()

	trimmed := strings.TrimSpace(number)
	if trimmed == "" {
		return "", fmt.Errorf("%w: no number on record", ErrPhoneInvalid)
	}
	if !isDialable(trimmed) {
		return "", fmt.Errorf("%w: contains characters that are not part of a phone number", ErrPhoneInvalid)
	}

	region := ""
	if !strings.HasPrefix(trimmed, "+") {
		var ok bool
		region, ok = countryToRegion[strings.ToLower(strings.TrimSpace(countryName))]
		if !ok {
			return "", fmt.Errorf("%w: %q", ErrCountryUnknown, countryName)
		}
	}
	parsed, parseErr := phonenumbers.Parse(trimmed, region)
	if parseErr != nil {
		return "", fmt.Errorf("%w: %v", ErrPhoneInvalid, parseErr)
	}
	if !phonenumbers.IsValidNumber(parsed) {
		// Note: the raw number is deliberately not echoed into the error —
		// these strings reach logs and, via the 400 body, end users.
		return "", fmt.Errorf("%w: not a valid number for region %q", ErrPhoneInvalid, region)
	}
	// An OTP is an SMS. A fixed line satisfies IsValidNumber but can never
	// receive one, which is exactly the silent non-delivery this function
	// exists to prevent.
	switch phonenumbers.GetNumberType(parsed) {
	case phonenumbers.MOBILE, phonenumbers.FIXED_LINE_OR_MOBILE:
	default:
		return "", fmt.Errorf("%w: not a mobile number", ErrPhoneInvalid)
	}
	return phonenumbers.Format(parsed, phonenumbers.E164), nil
}
