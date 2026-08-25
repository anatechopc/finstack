package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
)

// TestSearchTokensForUser_SkipsWhenUnchanged is the important case: the
// trigger fires on its own token write, so it must recognise that nothing
// changed and stop. Without this the trigger recurses.
func TestSearchTokensForUser_SkipsWhenUnchanged(t *testing.T) {
	user := map[string]any{
		"first_name":    "Juan",
		"last_name":     "dela Cruz",
		"mobile_number": "09175550142",
		"email_address": "juan.cruz@gmail.com",
	}

	tokens, needsWrite := triggers.SearchTokensForUser(user)
	if !needsWrite {
		t.Fatal("a user with no tokens yet must be written")
	}

	withTokens := map[string]any{}
	for k, v := range user {
		withTokens[k] = v
	}
	withTokens["search_tokens"] = toAnySlice(tokens)

	if _, needsWrite := triggers.SearchTokensForUser(withTokens); needsWrite {
		t.Error("tokens already current — must not write again")
	}
}

func TestSearchTokensForUser_RewritesOnNameChange(t *testing.T) {
	after := map[string]any{"first_name": "Juan", "last_name": "Santos"}

	tokens, needsWrite := triggers.SearchTokensForUser(after)
	if !needsWrite {
		t.Fatal("a changed surname must produce a write")
	}
	assertHas(t, tokens, "santos")

	// The case every edit to an already-tokenized user actually hits: tokens
	// are present but stale (they still describe the previous surname). Absent
	// tokens and exactly-matching tokens are the easy ends; this is the middle.
	stale, _ := triggers.SearchTokensForUser(map[string]any{"first_name": "Juan", "last_name": "Cruz"})
	after["search_tokens"] = toAnySlice(stale)

	tokens, needsWrite = triggers.SearchTokensForUser(after)
	if !needsWrite {
		t.Fatal("stale tokens must be rewritten, not left in place")
	}
	assertHas(t, tokens, "santos")
}

// TestSearchTokensForUser_NewlyCreatedUser covers the user_created path: a
// brand-new document has no search_tokens field at all yet, so this must
// report needsWrite=true and compute tokens from every indexed field —
// name, mobile, and email alike.
func TestSearchTokensForUser_NewlyCreatedUser(t *testing.T) {
	created := map[string]any{
		"first_name":    "Maria",
		"middle_name":   "Santos",
		"last_name":     "Reyes",
		"mobile_number": "09175550142",
		"email_address": "maria.reyes@gmail.com",
	}

	tokens, needsWrite := triggers.SearchTokensForUser(created)
	if !needsWrite {
		t.Fatal("a newly created user with no search_tokens yet must be written")
	}
	assertHas(t, tokens, "maria")
	assertHas(t, tokens, "reyes")
	assertHas(t, tokens, "santos")
	assertHas(t, tokens, "maria.reyes@gmail.com")
	assertHas(t, tokens, "0142") // last four digits of the mobile number
}

func toAnySlice(values []string) []any {
	out := make([]any, len(values))
	for i, v := range values {
		out[i] = v
	}
	return out
}

func assertHas(t *testing.T, tokens []string, want string) {
	t.Helper()
	for _, token := range tokens {
		if token == want {
			return
		}
	}
	t.Errorf("tokens %q missing %q", tokens, want)
}
