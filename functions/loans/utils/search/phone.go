package search

import (
	"sort"
	"strings"
	"unicode"
)

// lastDigits is how many trailing digits are emitted as a discrete token.
const lastDigits = 4

// CanonicalPhone reduces a phone number to its national significant digits so
// that every spelling of the same number collapses to one token.
//
// This deliberately does NOT use api/service.NormalizePhoneE164: that function
// requires the user's country, read from their address, and fails with
// ErrCountryUnknown when the address is incomplete — which would silently make
// those users unfindable by phone. Search needs consistency, not validity.
func CanonicalPhone(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if unicode.IsDigit(r) {
			digits.WriteRune(r)
		}
	}

	value := digits.String()
	value = strings.TrimPrefix(value, "63")
	value = strings.TrimPrefix(value, "0")
	return value
}

// PhoneTokens returns the token set for a phone number: the canonical form,
// its prefixes, and the last four digits.
func PhoneTokens(raw string) []string {
	canonical := CanonicalPhone(raw)
	if canonical == "" {
		return nil
	}

	set := map[string]struct{}{canonical: {}}
	addPrefixes(set, canonical)

	if len(canonical) >= lastDigits {
		set[canonical[len(canonical)-lastDigits:]] = struct{}{}
	}

	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return tokens
}
