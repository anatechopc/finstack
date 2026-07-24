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
// registration form hardcodes "Philippines"; extend when new countries are
// onboarded.
var countryToRegion = map[string]string{
	"philippines": "PH",
}

// NormalizePhoneE164 parses a stored mobile number against the user's
// country and returns it in E.164 form ("9175551291" + "Philippines" →
// "+639175551291"). Numbers already carrying a "+" prefix parse
// independently of the region hint, so well-formed legacy values pass
// through even when countryName is empty or unknown.
func NormalizePhoneE164(number, countryName string) (string, error) {
	trimmed := strings.TrimSpace(number)
	region := ""
	if !strings.HasPrefix(trimmed, "+") {
		var ok bool
		region, ok = countryToRegion[strings.ToLower(strings.TrimSpace(countryName))]
		if !ok {
			return "", fmt.Errorf("%w: %q", ErrCountryUnknown, countryName)
		}
	}
	parsed, err := phonenumbers.Parse(trimmed, region)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrPhoneInvalid, err)
	}
	if !phonenumbers.IsValidNumber(parsed) {
		return "", fmt.Errorf("%w: %q is not valid for region %q", ErrPhoneInvalid, trimmed, region)
	}
	return phonenumbers.Format(parsed, phonenumbers.E164), nil
}
