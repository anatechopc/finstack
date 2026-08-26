package search_test

import (
	"testing"

	"com.loooans.app/utils/search"
)

// TestCanonicalPhone: the three spellings a Philippine mobile number is
// written in must collapse to one form, or a client is findable by one
// spelling of their own number and not another.
func TestCanonicalPhone(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{"national 0-prefixed", "09175550142", "9175550142"},
		{"E.164", "+639175550142", "9175550142"},
		{"country code, no plus", "639175550142", "9175550142"},
		{"spaced and punctuated", "0917 555-0142", "9175550142"},
		{"already bare", "9175550142", "9175550142"},
		{"international access code prefix", "0639175550142", "9175550142"},
		{"doubled international access code prefix", "00639175550142", "9175550142"},
		{"empty", "", ""},
		{"no digits", "not a number", ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := search.CanonicalPhone(tc.raw); got != tc.want {
				t.Errorf("CanonicalPhone(%q) = %q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}

// TestPhoneTokens: staff frequently have only the tail of a number, and
// prefix expansion cannot match a suffix, so the last four digits are a
// discrete token.
func TestPhoneTokens(t *testing.T) {
	tokens := search.PhoneTokens("0917 555 0142")

	assertContains(t, tokens, "9175550142") // full canonical form
	assertContains(t, tokens, "91")         // shortest prefix
	assertContains(t, tokens, "917555014")  // mid prefix
	assertContains(t, tokens, "0142")       // last four

	if len(search.PhoneTokens("")) != 0 {
		t.Error("empty input should produce no tokens")
	}
}

func assertContains(t *testing.T, tokens []string, want string) {
	t.Helper()
	for _, token := range tokens {
		if token == want {
			return
		}
	}
	t.Errorf("tokens %q missing %q", tokens, want)
}
