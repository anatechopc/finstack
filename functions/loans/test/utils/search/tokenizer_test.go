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

type goldenFile struct {
	Cases []struct {
		Input  []string `json:"input"`
		Tokens []string `json:"tokens"`
	} `json:"cases"`
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

	for _, tc := range golden.Cases {
		t.Run(strings.Join(tc.Input, "+"), func(t *testing.T) {
			got := search.Tokenize(tc.Input...)
			if !reflect.DeepEqual(got, tc.Tokens) {
				t.Errorf("Tokenize(%q)\n got: %q\nwant: %q", tc.Input, got, tc.Tokens)
			}
		})
	}
}
