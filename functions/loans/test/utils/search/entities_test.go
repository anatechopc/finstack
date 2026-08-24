package search_test

import (
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

func assertSorted(t *testing.T, tokens []string) {
	t.Helper()
	for i := 1; i < len(tokens); i++ {
		if tokens[i-1] > tokens[i] {
			t.Fatalf("tokens not sorted at %d: %q then %q", i, tokens[i-1], tokens[i])
		}
	}
}
