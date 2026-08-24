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
)

// Tokenize returns the deduplicated, sorted token set for the given field
// values. Empty values are skipped.
//
// For each value it emits the full normalized value (exempt from MaxPrefix,
// so a pasted email or phone number matches exactly), and for each
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

		// The whole value, uncapped — this is what makes a pasted email or
		// phone number match. Without it, splitting happens before matching
		// and the paste finds nothing.
		set[normalized] = struct{}{}

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
