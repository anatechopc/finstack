package search_test

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"

	"com.loooans.app/utils/search"
)

func TestTokenize(t *testing.T) {
	cases := []struct {
		name  string
		input []string
		want  []string
	}{
		{
			name:  "two letter surname indexed whole",
			input: []string{"Go"},
			want:  []string{"go"},
		},
		{
			name:  "simple name expands to prefixes",
			input: []string{"Cruz"},
			want:  []string{"cr", "cru", "cruz"},
		},
		{
			name:  "apostrophe yields joined and split forms",
			input: []string{"O'Brien"},
			want: []string{
				"br", "bri", "brie", "brien",
				"o",
				"o'brien",
				"ob", "obr", "obri", "obrie", "obrien",
			},
		},
		{
			name:  "diacritics are folded",
			input: []string{"Peña"},
			want:  []string{"pe", "pen", "pena"},
		},
		{
			name:  "long token capped at twelve, full value still emitted",
			input: []string{"Bartholomewson"},
			want: []string{
				"ba", "bar", "bart", "barth", "bartho", "barthol",
				"bartholo", "bartholom", "bartholome", "bartholomew",
				"bartholomews",
				"bartholomewson",
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := search.Tokenize(tc.input...)
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("Tokenize(%q)\n got: %q\nwant: %q", tc.input, got, tc.want)
			}
		})
	}
}

// The full-value token is deliberately exempt from MaxPrefix, which left it
// bounded only by the length of the source field. search_tokens is
// automatically single-field indexed and Firestore refuses a write whose index
// entry is too large, so a pathological first_name or email_address would make
// every later edit of that user fail — and the error propagates out of
// HandleUserChangedCore, so the name cascade fails with it. The value is
// truncated rather than dropped, because a dropped token turns a pasted-value
// search into a silent miss.
func TestTokenize_FullValueTokenIsCapped(t *testing.T) {
	long := strings.Repeat("añ", search.MaxFullValue) // 2*MaxFullValue runes, multi-byte

	for _, token := range search.Tokenize(long) {
		if runes := len([]rune(token)); runes > search.MaxFullValue {
			t.Fatalf("token of %d runes emitted, want at most %d: %q", runes, search.MaxFullValue, token)
		}
	}

	// Truncation, not omission: the capped prefix of the value is present.
	want := string([]rune(search.Normalize(long))[:search.MaxFullValue])
	found := false
	for _, token := range search.Tokenize(long) {
		if token == want {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("no token equals the value truncated to %d runes — the full-value token was dropped, not capped", search.MaxFullValue)
	}

	// A value at the cap is untouched, so nothing real is truncated.
	atCap := strings.Repeat("a", search.MaxFullValue)
	if got := search.Tokenize(atCap); got[len(got)-1] != atCap {
		t.Errorf("a value of exactly %d runes was altered; longest token was %q", search.MaxFullValue, got[len(got)-1])
	}
}

// Normalize collapses internal whitespace runs, it does not only trim the
// ends. A double space is an ordinary paste artefact, and if it survived into
// the full-value token then "Juan  Carlos" and "Juan Carlos" would be two
// different clients as far as a pasted query is concerned.
func TestNormalizeCollapsesInternalWhitespace(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Juan  Carlos", "juan carlos"},
		{"  dela   Cruz\t", "dela cruz"},
		{"Acme\n\nLending", "acme lending"},
		{"already fine", "already fine"},
	}
	for _, tc := range cases {
		if got := search.Normalize(tc.in); got != tc.want {
			t.Errorf("Normalize(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}

	if a, b := search.Tokenize("Juan  Carlos"), search.Tokenize("Juan Carlos"); !reflect.DeepEqual(a, b) {
		t.Errorf("double- and single-spaced spellings diverge:\n %q\nvs %q", a, b)
	}
}

// Token LENGTH was bounded; token COUNT was not. Each element of search_tokens
// costs one index entry per composite index containing it plus two automatic
// single-field entries, and Firestore rejects a write producing more than
// 40,000 entries for one document — so an unbounded array does not bloat, it
// makes the document permanently unwritable and fails productWritten on every
// later edit. See search.MaxWords / search.MaxTokens.
func TestTokenize_WordCountIsCapped(t *testing.T) {
	words := make([]string, 800)
	for i := range words {
		words[i] = fmt.Sprintf("w%04d", i+1)
	}
	tokens := search.Tokenize(strings.Join(words, " "))

	if len(tokens) > search.MaxTokens {
		t.Errorf("%d tokens emitted, want at most %d", len(tokens), search.MaxTokens)
	}

	index := map[string]bool{}
	for _, token := range tokens {
		index[token] = true
	}
	// The budget is MaxWords words, taken in order: the last word inside it is
	// expanded, the first word past it is not.
	if last := fmt.Sprintf("w%04d", search.MaxWords); !index[last] {
		t.Errorf("word %d (%q) was not expanded, but it is inside the %d-word budget", search.MaxWords, last, search.MaxWords)
	}
	if past := fmt.Sprintf("w%04d", search.MaxWords+1); index[past] {
		t.Errorf("word %d (%q) was expanded, but the budget is %d words — the cap is not being applied", search.MaxWords+1, past, search.MaxWords)
	}
}

// MaxWords cannot bound a single pathological *word*: "aaa-aab-aac-…" has no
// whitespace at all, so it costs one word yet emits a sub-token per part.
// MaxTokens is the backstop that makes the array bounded regardless.
func TestTokenize_TokenCountIsCappedForOneLongWord(t *testing.T) {
	var word strings.Builder
	for i := 0; i < 2000; i++ {
		if i > 0 {
			word.WriteByte('-')
		}
		fmt.Fprintf(&word, "%c%c%c", 'a'+i/676, 'a'+(i/26)%26, 'a'+i%26)
	}
	if strings.ContainsAny(word.String(), " \t\n") {
		t.Fatal("the pathological input must be a single word, or it tests MaxWords instead")
	}

	tokens := search.Tokenize(word.String())
	if len(tokens) != search.MaxTokens {
		t.Errorf("one pathological word produced %d tokens, want exactly the cap %d "+
			"(fewer means the input stopped being pathological; more means the cap is gone)",
			len(tokens), search.MaxTokens)
	}
}

// The producers a golden case may name. Names, values and meaning are fixed by
// the "paths" block of golden_tokens.json, which is what the Dart suite reads.
const (
	pathTokenize          = "tokenize"
	pathPhoneTokens       = "phone_tokens"
	pathUserTokens        = "user_tokens"
	pathProductViewTokens = "product_view_tokens"
)

// inputArity is how many arguments each path takes. A case with the wrong
// count is a failure, not a skip: dispatching it anyway would either panic or
// silently assert a different function's contract.
var inputArity = map[string]int{
	pathPhoneTokens:       1,
	pathUserTokens:        5,
	pathProductViewTokens: 3,
}

// goldenCase is one entry of golden_tokens.json.
//
// Path is what makes the file able to express the contract at all. Phone
// tokens do not come from Tokenize — they come from CanonicalPhone +
// PhoneTokens, which canonicalize before expanding — so a file that ran every
// case through Tokenize could only ever pin a third of the tokenizer, and a
// phone row added to it would encode a *wrong* expectation.
type goldenCase struct {
	Name   string   `json:"name"`
	Path   string   `json:"path"`
	Input  []string `json:"input"`
	Tokens []string `json:"tokens"`
}

type goldenFile struct {
	// Limits mirrors the Go constants. It exists so the file can be
	// reimplemented from alone — the Dart suite reads these numbers rather
	// than hardcoding them — which only holds if Go asserts they stay true.
	Limits map[string]int `json:"limits"`
	Cases  []goldenCase   `json:"cases"`
}

// TestGoldenVectors asserts the shared contract with the Dart query path.
// The same file is read by apps/loans/test/features/search/tokenizer_test.dart.
func TestGoldenVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../utils/search/testdata/golden_tokens.json")
	if err != nil {
		t.Fatalf("cannot read golden vectors: %v", err)
	}

	var golden goldenFile
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatalf("cannot parse golden vectors: %v", err)
	}
	if len(golden.Cases) == 0 {
		t.Fatal("golden vector file has no cases")
	}

	seen := map[string]int{}
	for _, tc := range golden.Cases {
		seen[tc.Path]++
		t.Run(tc.Path+"/"+strings.Join(tc.Input, "+"), func(t *testing.T) {
			got := runGoldenCase(t, tc)
			if !reflect.DeepEqual(got, tc.Tokens) {
				t.Errorf("%s: %s(%q)\n got: %q\nwant: %q", tc.Name, tc.Path, tc.Input, got, tc.Tokens)
			}
		})
	}

	// Coverage, not correctness: the failure this whole file exists to prevent
	// is silent, so a path losing its last case must break CI rather than
	// quietly stop being asserted.
	for _, path := range []string{pathTokenize, pathPhoneTokens, pathUserTokens, pathProductViewTokens} {
		if seen[path] == 0 {
			t.Errorf("no golden case exercises path %q — that producer is now unpinned", path)
		}
	}

	// The "limits" block is what a reimplementation reads instead of the Go
	// source. A stale number there is a drift bug that ships silently.
	for name, want := range map[string]int{
		"min_prefix":     search.MinPrefix,
		"max_prefix":     search.MaxPrefix,
		"max_full_value": search.MaxFullValue,
		"max_words":      search.MaxWords,
		"max_tokens":     search.MaxTokens,
	} {
		got, ok := golden.Limits[name]
		if !ok {
			t.Errorf("limits block is missing %q — Dart reads these numbers, so an absent one is silent drift", name)
			continue
		}
		if got != want {
			t.Errorf("limits.%s = %d, Go constant is %d", name, got, want)
		}
	}
}

// runGoldenCase dispatches one case to the producer its path names. An
// unrecognized path fails: a case nothing dispatches would assert nothing while
// still counting as coverage.
func runGoldenCase(t *testing.T, tc goldenCase) []string {
	t.Helper()

	if want, fixed := inputArity[tc.Path]; fixed && len(tc.Input) != want {
		t.Fatalf("%s: path %q takes exactly %d inputs, got %d: %q",
			tc.Name, tc.Path, want, len(tc.Input), tc.Input)
	}

	switch tc.Path {
	case pathTokenize:
		return search.Tokenize(tc.Input...)
	case pathPhoneTokens:
		return search.PhoneTokens(tc.Input[0])
	case pathUserTokens:
		return search.UserTokens(tc.Input[0], tc.Input[1], tc.Input[2], tc.Input[3], tc.Input[4])
	case pathProductViewTokens:
		return search.ProductViewTokens(tc.Input[0], tc.Input[1], tc.Input[2])
	default:
		t.Fatalf("%s: unknown path %q — add it to runGoldenCase and to the "+
			"\"paths\" block of golden_tokens.json, or the case asserts nothing", tc.Name, tc.Path)
		return nil
	}
}
