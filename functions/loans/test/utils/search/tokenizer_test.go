package search_test

import (
	"encoding/json"
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

// The producers a golden case may name. Names, values and meaning are fixed by
// the "paths" block of golden_tokens.json, which is what the Dart suite reads.
const (
	pathTokenize    = "tokenize"
	pathPhoneTokens = "phone_tokens"
)

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
	Cases []goldenCase `json:"cases"`
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
	for _, path := range []string{pathTokenize, pathPhoneTokens} {
		if seen[path] == 0 {
			t.Errorf("no golden case exercises path %q — that producer is now unpinned", path)
		}
	}
}

// runGoldenCase dispatches one case to the producer its path names. An
// unrecognized path fails: a case nothing dispatches would assert nothing while
// still counting as coverage.
func runGoldenCase(t *testing.T, tc goldenCase) []string {
	t.Helper()

	switch tc.Path {
	case pathTokenize:
		return search.Tokenize(tc.Input...)
	case pathPhoneTokens:
		if len(tc.Input) != 1 {
			t.Fatalf("%s: path %q takes exactly one input, got %d: %q",
				tc.Name, tc.Path, len(tc.Input), tc.Input)
		}
		return search.PhoneTokens(tc.Input[0])
	default:
		t.Fatalf("%s: unknown path %q — add it to runGoldenCase and to the "+
			"\"paths\" block of golden_tokens.json, or the case asserts nothing", tc.Name, tc.Path)
		return nil
	}
}
