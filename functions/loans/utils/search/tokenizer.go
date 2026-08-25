// Package search builds the token sets stored in the search_tokens array on
// searchable Firestore documents. Indexing (Go, here) and querying (Dart, in
// the app) must agree exactly; testdata/golden_tokens.json pins that contract
// and is asserted from both languages.
package search

import (
	"sort"
	"strings"
	"unicode"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

const (
	// MinPrefix is the shortest prefix emitted. Two, not three, because
	// two-letter Filipino surnames (Go, Ty, Uy, Sy, Co) are common and would
	// otherwise be unsearchable. One would make every user match "d".
	MinPrefix = 2
	// MaxPrefix bounds array size regardless of how long a name is. Queries
	// longer than this match on the first MaxPrefix characters, then refine
	// on the client.
	MaxPrefix = 12
	// MaxFullValue bounds the one token that MaxPrefix does not: the full
	// normalized value. search_tokens is automatically single-field indexed,
	// and Firestore rejects the whole write when an index entry exceeds its
	// size limit — so an absurd first_name or email_address would make every
	// subsequent edit of that user fail, and HandleUserChangedCore propagates
	// that error, taking the name cascade down with it. 256 is far above any
	// real value (RFC 5321 caps an email at 254) so nothing legitimate is
	// truncated; it exists to keep one bad document from being unwritable.
	MaxFullValue = 256
)

// Tokenize returns the deduplicated, sorted token set for the given field
// values. Empty values are skipped.
//
// For each value it emits the full normalized value (exempt from MaxPrefix,
// so a pasted email or phone number matches exactly, and bounded only by the
// far looser MaxFullValue), and for each
// whitespace-separated word both the de-punctuated joined form and the
// sub-tokens obtained by splitting on runs of non-alphanumeric characters.
// Every one of those is prefix-expanded.
func Tokenize(values ...string) []string {
	set := map[string]struct{}{}

	for _, value := range values {
		normalized := Normalize(value)
		if normalized == "" {
			continue
		}

		// The whole value, exempt from MaxPrefix — this is what makes a pasted
		// email or phone number match. Without it, splitting happens before
		// matching and the paste finds nothing. Exempt from MaxPrefix is not
		// the same as unbounded: MaxFullValue keeps it writable.
		set[capFullValue(normalized)] = struct{}{}

		for _, word := range strings.Fields(normalized) {
			parts := strings.FieldsFunc(word, func(r rune) bool {
				return !unicode.IsLetter(r) && !unicode.IsDigit(r)
			})

			joined := strings.Join(parts, "")
			if joined != "" {
				addPrefixes(set, joined)
			}
			for _, part := range parts {
				addPrefixes(set, part)
			}
		}
	}

	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return tokens
}

// Normalize lowercases, folds diacritics, and collapses surrounding
// whitespace. Both the indexer and the query path must apply it.
func Normalize(value string) string {
	folded, _, err := transform.String(
		transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC),
		value,
	)
	if err != nil {
		// Transform only fails on malformed input; the raw value is a safe
		// fallback and still yields usable tokens.
		folded = value
	}
	return strings.ToLower(strings.TrimSpace(folded))
}

// capFullValue truncates the full-value token to MaxFullValue runes. It
// truncates rather than dropping the token: a truncated token still matches a
// query the client truncates the same way, whereas dropping it would make a
// pasted value silently return nothing. Runes, not bytes, so the cap means the
// same thing in Dart.
func capFullValue(normalized string) string {
	runesOf := []rune(normalized)
	if len(runesOf) <= MaxFullValue {
		return normalized
	}
	return string(runesOf[:MaxFullValue])
}

func addPrefixes(set map[string]struct{}, token string) {
	runesOf := []rune(token)
	if len(runesOf) == 0 {
		return
	}
	if len(runesOf) < MinPrefix {
		set[token] = struct{}{}
		return
	}
	limit := len(runesOf)
	if limit > MaxPrefix {
		limit = MaxPrefix
	}
	for i := MinPrefix; i <= limit; i++ {
		set[string(runesOf[:i])] = struct{}{}
	}
}
