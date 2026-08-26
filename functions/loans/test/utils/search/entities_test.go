package search_test

import (
	"fmt"
	"strings"
	"testing"

	"com.loooans.app/utils/search"
)

func TestUserTokens(t *testing.T) {
	tokens := search.UserTokens(
		"Juan", "Santos", "dela Cruz",
		"0917 555 0142",
		"juan.cruz@gmail.com",
	)

	// Name parts, including the middle name and the two-word surname.
	assertContains(t, tokens, "juan")
	assertContains(t, tokens, "santos")
	assertContains(t, tokens, "cruz")
	assertContains(t, tokens, "dela")

	// Phone, in canonical form and by its tail.
	assertContains(t, tokens, "9175550142")
	assertContains(t, tokens, "0142")

	// Email: the whole address, so a paste matches, plus its parts.
	assertContains(t, tokens, "juan.cruz@gmail.com")
	assertContains(t, tokens, "gmail")

	assertSorted(t, tokens)
}

func TestUserTokensToleratesMissingFields(t *testing.T) {
	tokens := search.UserTokens("Ty", "", "", "", "")
	assertContains(t, tokens, "ty")

	if len(search.UserTokens("", "", "", "", "")) != 0 {
		t.Error("a user with no searchable fields should produce no tokens")
	}
}

func TestProductViewTokens(t *testing.T) {
	tokens := search.ProductViewTokens("Acme Lending", "Salary Loan", "Fast cash")

	assertContains(t, tokens, "acme")
	assertContains(t, tokens, "salary")
	assertContains(t, tokens, "fast")
	assertSorted(t, tokens)
}

// The cap has to hold on what the trigger actually writes, not just on
// Tokenize: UserTokens merges two independently capped groups, and the sum of
// two capped sets is not itself capped. The failure this prevents is a lender
// pasting a marketing blurb into tag_line and making that product_views
// document permanently unwritable — every later edit rejected with
// InvalidArgument, propagated out of HandleProductWrittenCore, retried forever.
func TestCompositionsCapTokenCount(t *testing.T) {
	blurb := blurbOf(800)

	cases := []struct {
		name   string
		tokens []string
	}{
		{"ProductViewTokens", search.ProductViewTokens(blurb, blurb, blurb)},
		{"UserTokens", search.UserTokens(blurb, blurb, blurb, "0917 555 0142", blurb+"@example.com")},
	}

	for _, tc := range cases {
		if len(tc.tokens) > search.MaxTokens {
			t.Errorf("%s emitted %d tokens, want at most %d", tc.name, len(tc.tokens), search.MaxTokens)
		}
		assertSorted(t, tc.tokens)
	}

	// Phone tokens are digits, which sort ahead of every letter, so the cap
	// can never truncate a client's own number out of their document.
	assertContains(t, cases[1].tokens, "9175550142")
	assertContains(t, cases[1].tokens, "0142")
}

func blurbOf(words int) string {
	parts := make([]string, words)
	for i := range parts {
		parts[i] = fmt.Sprintf("marketing%04d", i+1)
	}
	return strings.Join(parts, " ")
}

func assertSorted(t *testing.T, tokens []string) {
	t.Helper()
	for i := 1; i < len(tokens); i++ {
		if tokens[i-1] > tokens[i] {
			t.Fatalf("tokens not sorted at %d: %q then %q", i, tokens[i-1], tokens[i])
		}
	}
}
