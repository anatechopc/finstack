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
	// MaxWords bounds how many whitespace-separated words one composition
	// prefix-expands, counted across all of its values in order.
	//
	// MaxPrefix and MaxFullValue bound each token's LENGTH; nothing bounded
	// how MANY tokens a document produces. Each array element costs one index
	// entry per composite index containing search_tokens, plus the two
	// automatic single-field entries (ASC and DESC), and Firestore rejects any
	// write that would produce more than 40,000 index entries for a single
	// document. So an unbounded array does not merely bloat — it makes the
	// document permanently unwritable: a lender pasting an ~800-word marketing
	// blurb into tag_line emits roughly 8,800 tokens, UpdateView then fails
	// with InvalidArgument, HandleProductWrittenCore propagates it, and
	// productWritten fails on every subsequent edit of that product, forever.
	//
	// Capping input WORDS rather than truncating the finished token set is
	// deliberate. Truncating a sorted set drops by alphabet: it would keep
	// every deep prefix of "acme" and lose the whole of "zenith". Dropping
	// late words instead keeps every word a query is likely to start from,
	// and it is the easier of the two to state — and therefore to mirror in
	// Dart, which is the point of the golden vectors.
	//
	// 64 is far above any real name or tag line and far below the blurb above.
	MaxWords = 64
	// MaxTokens is the hard ceiling on the length of the search_tokens array
	// any composition emits; the sorted set is truncated to it.
	//
	// MaxWords does the semantic work and real data never reaches this. It
	// exists because MaxWords cannot bound a single pathological *word*:
	// "ab-cd-ef-…" with no whitespace is one word whose sub-token count grows
	// with its length. This backstop is what actually guarantees the bound.
	//
	// Arithmetic: index entries ≈ tokens × (composite indexes containing
	// search_tokens + 2). Six such indexes exist today — 2 on users, 4 on
	// product_views — so 2,000 × (6+2) = 16,000 entries, 40% of the 40,000
	// limit, leaving room for twelve more composite indexes before the cap
	// binds. Both numbers are part of the Go↔Dart contract and are stated in
	// the "paths" block of testdata/golden_tokens.json.
	MaxTokens = 2000
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
//
// Only the first MaxWords words are expanded, counted across all values in
// order; every non-empty value still contributes its full-value token. The
// sorted result is then truncated to MaxTokens. See those constants for why.
func Tokenize(values ...string) []string {
	set := map[string]struct{}{}
	budget := MaxWords

	for _, value := range values {
		normalized := Normalize(value)
		if normalized == "" {
			continue
		}

		// The whole value, exempt from MaxPrefix — this is what makes a pasted
		// email or phone number match. Without it, splitting happens before
		// matching and the paste finds nothing. Exempt from MaxPrefix is not
		// the same as unbounded: MaxFullValue keeps it writable.
		//
		// Exempt from MaxWords too: there are at most five values, so the
		// full-value tokens cost nothing measurable and are the ones a pasted
		// query depends on.
		set[capFullValue(normalized)] = struct{}{}

		for _, word := range strings.Fields(normalized) {
			if budget == 0 {
				break
			}
			budget--

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

	return sortedCapped(set)
}

// Normalize lowercases, folds diacritics, and collapses whitespace: the ends
// are trimmed and every internal run becomes a single space. Both the indexer
// and the query path must apply it.
//
// Collapsing internal runs — not merely trimming them — is deliberate.
// "Juan  Carlos" (a double space, an ordinary copy-paste artefact) and
// "Juan Carlos" must produce the same full-value token, or one spelling of the
// same name is unfindable by paste. It is the same class of defect that
// CanonicalPhone's loop-trim handles for numbers, and it is free to fix: the
// backfill has not run, so no search_tokens exist in any environment yet.
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
	return strings.Join(strings.Fields(strings.ToLower(folded)), " ")
}

// sortedCapped flattens a token set into the sorted, count-capped array that
// actually gets written.
func sortedCapped(set map[string]struct{}) []string {
	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return capCount(tokens)
}

// capCount truncates an already-sorted token list to MaxTokens. Truncating the
// sorted list is the backstop, not the primary bound — MaxWords is — so it is
// only ever reached by input no real field contains.
func capCount(sorted []string) []string {
	if len(sorted) <= MaxTokens {
		return sorted
	}
	return sorted[:MaxTokens]
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
