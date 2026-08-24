# Search Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every client and loan offer findable by generating a `search_tokens` array on `users` and `product_views` from Go triggers, backed by Firestore indexes and a re-runnable backfill.

**Architecture:** One shared Go tokenizer produces prefix-expanded tokens from names, emails and phone numbers. Firestore triggers write those tokens server-side so no client version can produce an unsearchable record. A golden test-vector file pins the tokenizer's exact output so the Dart query-side implementation (frontend plan) cannot drift from it.

**Tech Stack:** Go 1.22 (multi-module, `replace` directives), Firebase Admin SDK, Firestore triggers via CloudEvents, `golang.org/x/text` for Unicode normalization.

**Spec:** `docs/superpowers/specs/2026-08-24-search-design.md`

## Global Constraints

- Module path is `com.loooans.app`; sub-modules (`utils`, `triggers`, `api`, `types`) are wired by `replace` directives in `functions/loans/go.mod`. Adding a package under `utils/` needs no new module.
- Tests live in `functions/loans/test/`, mirroring source layout, in `package <name>_test`, table-driven. Follow `test/api/service/phone_service_test.go`.
- Firestore collection paths must use the environment prefix via `utils.GetCollectionPrefix()`. Never hardcode `dev_` or `stg_`.
- Every Firestore query and index must respect the `deleted_at` soft-delete convention.
- Prefix bounds are **min 2, max 12**. Tokens shorter than 2 are indexed whole. The full normalized value is always emitted and is **exempt** from the 12-character cap.
- Phone tokens use digit canonicalization, **not** `NormalizePhoneE164` — that function requires a country read from the user's address and fails with `ErrCountryUnknown` when the address is incomplete, which would silently make those users unfindable. Search needs consistency, not validity.
- Never push to `master`. Backend merges to `develop`.

## File Structure

| File | Responsibility |
|---|---|
| `functions/loans/utils/search/tokenizer.go` | Generic text tokenization: normalize, split, prefix-expand |
| `functions/loans/utils/search/phone.go` | Digit canonicalization and phone tokens |
| `functions/loans/utils/search/entities.go` | Compose per-entity token sets (`UserTokens`, `ProductViewTokens`) |
| `functions/loans/utils/search/testdata/golden_tokens.json` | Shared golden vectors — asserted by Go here and by Dart in the frontend plan |
| `functions/loans/triggers/product_view_projection.go` | Builds the `product_views` document from a `products` write |
| `functions/loans/cmd/backfill_search_tokens/main.go` | Re-runnable backfill |
| `apps/loans/firestore.indexes.json` | Composite indexes |

---

### Task 1: Text tokenizer

**Files:**
- Create: `functions/loans/utils/search/tokenizer.go`
- Create: `functions/loans/utils/search/testdata/golden_tokens.json`
- Modify: `functions/loans/utils/go.mod`
- Test: `functions/loans/test/utils/search/tokenizer_test.go`

**Interfaces:**
- Consumes: nothing
- Produces: `search.Tokenize(values ...string) []string` — returns a deduplicated, lexicographically sorted token slice. `search.MinPrefix = 2`, `search.MaxPrefix = 12`.

- [ ] **Step 1: Add the Unicode dependency**

```bash
cd functions/loans/utils
go get golang.org/x/text@v0.15.0
```

- [ ] **Step 2: Write the failing test**

Create `functions/loans/test/utils/search/tokenizer_test.go`:

```go
package search_test

import (
	"reflect"
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/utils/search/... -run TestTokenize -v`
Expected: FAIL — package `com.loooans.app/utils/search` does not exist.

- [ ] **Step 4: Write the tokenizer**

Create `functions/loans/utils/search/tokenizer.go`:

```go
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd functions/loans && go test ./test/utils/search/... -run TestTokenize -v`
Expected: PASS, all five subtests.

- [ ] **Step 6: Create the golden vector file**

Create `functions/loans/utils/search/testdata/golden_tokens.json`. This file is the
contract between the Go indexer and the Dart query path; the frontend plan asserts
the same file.

```json
{
  "description": "Shared golden vectors for search tokenization. Asserted by Go (functions/loans/test/utils/search) and Dart (apps/loans/test/features/search). If these two disagree, search breaks invisibly - a client simply cannot be found - so any change here must be made in both places in the same PR.",
  "cases": [
    { "input": ["Go"], "tokens": ["go"] },
    { "input": ["Cruz"], "tokens": ["cr", "cru", "cruz"] },
    { "input": ["Peña"], "tokens": ["pe", "pen", "pena"] },
    {
      "input": ["O'Brien"],
      "tokens": ["br", "bri", "brie", "brien", "o", "ob", "obr", "obri", "obrie", "obrien"]
    },
    {
      "input": ["Mary-Jane"],
      "tokens": [
        "ja", "jan", "jane",
        "ma", "mar", "mary", "mary-jane",
        "maryj", "maryja", "maryjan", "maryjane"
      ]
    }
  ]
}
```

- [ ] **Step 7: Write the golden vector test**

Append to `functions/loans/test/utils/search/tokenizer_test.go`:

```go
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
```

Add `encoding/json`, `os` and `strings` to the import block.

- [ ] **Step 8: Run the golden test**

Run: `cd functions/loans && go test ./test/utils/search/... -v`
Expected: PASS. If the `Mary-Jane` case fails, the expected list in the JSON is wrong,
not the tokenizer — recompute it by hand from the rule before changing code.

- [ ] **Step 9: Commit**

```bash
git add functions/loans/utils/search/tokenizer.go \
        functions/loans/utils/search/testdata/golden_tokens.json \
        functions/loans/utils/go.mod functions/loans/utils/go.sum \
        functions/loans/test/utils/search/tokenizer_test.go
git commit -m "feat(search): text tokenizer with shared golden vectors"
```

---

### Task 2: Phone tokens

**Files:**
- Create: `functions/loans/utils/search/phone.go`
- Test: `functions/loans/test/utils/search/phone_test.go`

**Interfaces:**
- Consumes: `search.Tokenize`, `search.MinPrefix`, `search.MaxPrefix` (Task 1)
- Produces: `search.CanonicalPhone(raw string) string`, `search.PhoneTokens(raw string) []string`

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/utils/search/phone_test.go`:

```go
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/utils/search/... -run 'TestCanonicalPhone|TestPhoneTokens' -v`
Expected: FAIL — `CanonicalPhone` and `PhoneTokens` are undefined.

- [ ] **Step 3: Write the implementation**

Create `functions/loans/utils/search/phone.go`:

```go
package search

import (
	"sort"
	"strings"
	"unicode"
)

// lastDigits is how many trailing digits are emitted as a discrete token.
const lastDigits = 4

// CanonicalPhone reduces a phone number to its national significant digits so
// that every spelling of the same number collapses to one token.
//
// This deliberately does NOT use api/service.NormalizePhoneE164: that function
// requires the user's country, read from their address, and fails with
// ErrCountryUnknown when the address is incomplete — which would silently make
// those users unfindable by phone. Search needs consistency, not validity.
func CanonicalPhone(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if unicode.IsDigit(r) {
			digits.WriteRune(r)
		}
	}

	value := digits.String()
	value = strings.TrimPrefix(value, "63")
	value = strings.TrimPrefix(value, "0")
	return value
}

// PhoneTokens returns the token set for a phone number: the canonical form,
// its prefixes, and the last four digits.
func PhoneTokens(raw string) []string {
	canonical := CanonicalPhone(raw)
	if canonical == "" {
		return nil
	}

	set := map[string]struct{}{canonical: {}}
	addPrefixes(set, canonical)

	if len(canonical) >= lastDigits {
		set[canonical[len(canonical)-lastDigits:]] = struct{}{}
	}

	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return tokens
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions/loans && go test ./test/utils/search/... -v`
Expected: PASS, including Task 1's tests.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/utils/search/phone.go \
        functions/loans/test/utils/search/phone_test.go
git commit -m "feat(search): phone canonicalization and tokens"
```

---

### Task 3: Per-entity token composition

**Files:**
- Create: `functions/loans/utils/search/entities.go`
- Test: `functions/loans/test/utils/search/entities_test.go`

**Interfaces:**
- Consumes: `search.Tokenize` (Task 1), `search.PhoneTokens` (Task 2)
- Produces: `search.UserTokens(firstName, middleName, lastName, mobile, email string) []string`, `search.ProductViewTokens(companyName, loanType, tagLine string) []string`

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/utils/search/entities_test.go`:

```go
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/utils/search/... -run 'TestUserTokens|TestProductViewTokens' -v`
Expected: FAIL — `UserTokens` and `ProductViewTokens` are undefined.

- [ ] **Step 3: Write the implementation**

Create `functions/loans/utils/search/entities.go`:

```go
package search

import "sort"

// UserTokens builds the search_tokens array for a users document.
// Email needs no special handling: Tokenize already splits on runs of
// non-alphanumeric characters, which covers "@", ".", "_", "-" and "+".
func UserTokens(firstName, middleName, lastName, mobile, email string) []string {
	return merge(
		Tokenize(firstName, middleName, lastName, email),
		PhoneTokens(mobile),
	)
}

// ProductViewTokens builds the search_tokens array for a product_views
// document. product_views has no name field; loan_type carries that meaning,
// because the add-product flow offers presets plus an "Others" branch where
// the lender types their own value.
func ProductViewTokens(companyName, loanType, tagLine string) []string {
	return Tokenize(companyName, loanType, tagLine)
}

func merge(groups ...[]string) []string {
	set := map[string]struct{}{}
	for _, group := range groups {
		for _, token := range group {
			set[token] = struct{}{}
		}
	}

	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}
	sort.Strings(tokens)
	return tokens
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions/loans && go test ./test/utils/search/... -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/utils/search/entities.go \
        functions/loans/test/utils/search/entities_test.go
git commit -m "feat(search): per-entity token composition"
```

---

### Task 4: Write user tokens from the userChanges trigger

**Files:**
- Modify: `functions/loans/triggers/user_changes.go`
- Modify: `functions/loans/triggers/go.mod` (add the `utils` requirement if absent)
- Test: `functions/loans/test/triggers/user_search_tokens_test.go`

**Interfaces:**
- Consumes: `search.UserTokens` (Task 3)
- Produces: `triggers.SearchTokensForUser(before, after map[string]any) ([]string, bool)` — returns the tokens to write and whether a write is needed. Returning `false` when nothing changed is what prevents the trigger from re-firing on its own write.

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/triggers/user_search_tokens_test.go`:

```go
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

	tokens, needsWrite := triggers.SearchTokensForUser(nil, user)
	if !needsWrite {
		t.Fatal("a user with no tokens yet must be written")
	}

	withTokens := map[string]any{}
	for k, v := range user {
		withTokens[k] = v
	}
	withTokens["search_tokens"] = toAnySlice(tokens)

	if _, needsWrite := triggers.SearchTokensForUser(user, withTokens); needsWrite {
		t.Error("tokens already current — must not write again")
	}
}

func TestSearchTokensForUser_RewritesOnNameChange(t *testing.T) {
	before := map[string]any{"first_name": "Juan", "last_name": "Cruz"}
	after := map[string]any{"first_name": "Juan", "last_name": "Santos"}

	tokens, needsWrite := triggers.SearchTokensForUser(before, after)
	if !needsWrite {
		t.Fatal("a changed surname must produce a write")
	}
	assertHas(t, tokens, "santos")
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/triggers/... -run TestSearchTokensForUser -v`
Expected: FAIL — `SearchTokensForUser` is undefined.

- [ ] **Step 3: Write the implementation**

Append to `functions/loans/triggers/user_changes.go`:

```go
// SearchTokensForUser computes the search_tokens array for a user document and
// reports whether it differs from what the document already carries.
//
// The bool return is load-bearing: this trigger fires on document writes, so
// writing tokens unconditionally would fire it again on its own write. When
// the tokens already match, the caller must skip the write.
func SearchTokensForUser(before, after map[string]any) ([]string, bool) {
	if after == nil {
		return nil, false
	}

	str := func(key string) string {
		value, _ := after[key].(string)
		return value
	}

	tokens := search.UserTokens(
		str("first_name"),
		str("middle_name"),
		str("last_name"),
		str("mobile_number"),
		str("email_address"),
	)

	existing := stringSliceFrom(after["search_tokens"])
	if equalStringSlices(existing, tokens) {
		return nil, false
	}
	return tokens, true
}

func stringSliceFrom(raw any) []string {
	values, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(values))
	for _, value := range values {
		if s, ok := value.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
```

Add `"com.loooans.app/utils/search"` to the file's import block.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions/loans && go test ./test/triggers/... -run TestSearchTokensForUser -v`
Expected: PASS, both tests.

- [ ] **Step 5: Wire it into the trigger's core handler**

In `functions/loans/triggers/user_changes.go`, inside `HandleUserChangedCore`, after
the existing change handling and before returning, add:

```go
	if tokens, needsWrite := SearchTokensForUser(before, after); needsWrite {
		if err := deps.UpdateUser(ctx, uid, map[string]any{
			"search_tokens": tokens,
		}); err != nil {
			// Token staleness degrades search but must not fail the trigger,
			// which also carries changes more important than findability.
			return err
		}
	}
```

Read the existing `UserChangesDeps` definition first and reuse its update func;
if it has no update capability, add one following the shape used by
`VerifyOtpDeps.UpdateUser` in `functions/loans/api/users/verify_otp.go`.

- [ ] **Step 6: Run the full trigger suite**

Run: `cd functions/loans && go test ./test/triggers/... -v`
Expected: PASS. Existing `user_changes_test.go` tests must still pass — if a fake
now needs an `UpdateUser` func, add it to `test/fakes/fakes.go`.

- [ ] **Step 7: Build the whole module**

Run: `cd functions/loans && go build -v ./...`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add functions/loans/triggers/user_changes.go functions/loans/triggers/go.mod \
        functions/loans/triggers/go.sum \
        functions/loans/test/triggers/user_search_tokens_test.go \
        functions/loans/test/fakes/fakes.go
git commit -m "feat(search): write user search tokens from userChanges trigger"
```

---

### Task 5: Own the product_views projection in a trigger

**Files:**
- Create: `functions/loans/triggers/product_view_projection.go`
- Modify: `functions/loans/loooans_cloud_functions.go`
- Modify: `.github/scripts/deploy_functions.sh`
- Test: `functions/loans/test/triggers/product_view_projection_test.go`

**Interfaces:**
- Consumes: `search.ProductViewTokens` (Task 3)
- Produces: `triggers.BuildProductView(product map[string]any, companyName string) map[string]any`, and the `productWritten` CloudEvent entry point.

Today the Flutter client writes `product_views`
(`packages/loans/product_view_repository/lib/src/data/database/product_view_firestore_service.dart:72`).
Moving projection ownership here — rather than adding tokens to a client-written
document — means the trigger emits the whole document, so there is no
write-then-augment cycle and no recursion guard is needed.

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/triggers/product_view_projection_test.go`:

```go
package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
)

func TestBuildProductView(t *testing.T) {
	product := map[string]any{
		"id":                  "prod-1",
		"provider_id":         "company-1",
		"loan_type":           "Salary Loan",
		"term":                "1m",
		"interest_rate":       8.0,
		"max_loanable_amount": 50000.0,
	}

	view := triggers.BuildProductView(product, "Acme Lending")

	if view["product_id"] != "prod-1" {
		t.Errorf("product_id = %v, want prod-1", view["product_id"])
	}
	if view["company_name"] != "Acme Lending" {
		t.Errorf("company_name = %v, want Acme Lending", view["company_name"])
	}
	if view["loan_type"] != "Salary Loan" {
		t.Errorf("loan_type = %v, want Salary Loan", view["loan_type"])
	}

	tokens, ok := view["search_tokens"].([]string)
	if !ok {
		t.Fatalf("search_tokens missing or wrong type: %T", view["search_tokens"])
	}
	assertHas(t, tokens, "salary")
	assertHas(t, tokens, "acme")
}

func TestBuildProductViewToleratesMissingFields(t *testing.T) {
	view := triggers.BuildProductView(map[string]any{"id": "prod-2"}, "")

	if view["product_id"] != "prod-2" {
		t.Errorf("product_id = %v, want prod-2", view["product_id"])
	}
	if _, ok := view["search_tokens"].([]string); !ok {
		t.Error("search_tokens must always be present, even if empty")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/triggers/... -run TestBuildProductView -v`
Expected: FAIL — `BuildProductView` is undefined.

- [ ] **Step 3: Write the projection**

Create `functions/loans/triggers/product_view_projection.go`:

```go
package triggers

import "com.loooans.app/utils/search"

// BuildProductView projects a products document into its product_views
// denormalized read model, including the search tokens.
//
// This projection was previously owned by the Flutter client. Ownership moved
// here so that no client version can write a view document that is missing
// fields or unsearchable. See finstack#99 for the remaining client-written
// projections.
func BuildProductView(product map[string]any, companyName string) map[string]any {
	str := func(key string) string {
		value, _ := product[key].(string)
		return value
	}
	num := func(key string) float64 {
		switch value := product[key].(type) {
		case float64:
			return value
		case int64:
			return float64(value)
		default:
			return 0
		}
	}

	loanType := str("loan_type")
	tagLine := str("tag_line")

	return map[string]any{
		"product_id":          str("id"),
		"company_id":          str("provider_id"),
		"company_name":        companyName,
		"loan_type":           loanType,
		"tag_line":            tagLine,
		"term":                str("term"),
		"interest_rate":       num("interest_rate"),
		"max_loanable_amount": num("max_loanable_amount"),
		"search_tokens":       search.ProductViewTokens(companyName, loanType, tagLine),
	}
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions/loans && go test ./test/triggers/... -run TestBuildProductView -v`
Expected: PASS, both tests.

- [ ] **Step 5: Register the trigger entry point**

In `functions/loans/loooans_cloud_functions.go`, add to the trigger block after
line 46:

```go
	functions.CloudEvent("productWritten", triggers.ProductWritten)
```

Then append `ProductWritten` to `product_view_projection.go`:

```go
// ProductWritten projects every products write into its product_views
// document. Registered as the productWritten CloudEvent entry point.
func ProductWritten(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("product_written")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	// A delete leaves no new value; the view is cleaned up separately.
	if data.GetValue() == nil {
		log.Debug("product deleted, nothing to project")
		return nil
	}

	product := map[string]any{}
	for key, value := range data.GetValue().GetFields() {
		switch typed := value.GetValueType().(type) {
		case *firestoredata.Value_StringValue:
			product[key] = typed.StringValue
		case *firestoredata.Value_IntegerValue:
			product[key] = float64(typed.IntegerValue)
		case *firestoredata.Value_DoubleValue:
			product[key] = typed.DoubleValue
		case *firestoredata.Value_BooleanValue:
			product[key] = typed.BooleanValue
		}
	}

	productId, _ := product["id"].(string)
	if productId == "" {
		log.Error("product has no id, cannot project")
		return errors.New("product has no id")
	}

	app, fbErr := utils.InitializeFirebase(ctx)
	if fbErr != nil {
		return fbErr
	}
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fmt.Errorf("failed to instantiate firestore client: %w", fsErr)
	}
	defer fs.Close()

	prefix := utils.GetCollectionPrefix()

	// company_name is denormalized onto the view so offer search can match it
	// without a join.
	companyName := ""
	if companyId, _ := product["provider_id"].(string); companyId != "" {
		doc, err := fs.Collection(prefix + "companies").Doc(companyId).Get(ctx)
		if err != nil {
			// A missing company must not block the projection; the view is
			// still useful and the next write will pick the name up.
			log.Sugar().Warnf("cannot read company %s: %v", companyId, err)
		} else {
			companyName, _ = doc.Data()["name"].(string)
		}
	}

	view := BuildProductView(product, companyName)

	_, err := fs.Collection(prefix+"product_views").Doc(productId).
		Set(ctx, view, firestore.MergeAll)
	if err != nil {
		return fmt.Errorf("cannot write product_view %s: %w", productId, err)
	}

	return nil
}
```

Add these imports to the file: `context`, `errors`, `fmt`,
`cloud.google.com/go/firestore`, `com.loooans.app/utils`,
`github.com/cloudevents/sdk-go/v2/event`, `github.com/golang/protobuf/proto`,
`github.com/googleapis/google-cloudevents-go/cloud/firestoredata`.

The company name key is `name` — verified against
`packages/core/company_repository/lib/src/model/company_entity.dart:57`, which
declares it unprefixed with no `@JsonKey` override.

- [ ] **Step 6: Add the deploy entry**

In `.github/scripts/deploy_functions.sh`, after the `messageWritten` block
(line 153), add:

```bash
gcloud functions deploy productWritten_$environment --gen2 --service-account="$serviceAccount" --runtime=go126 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=productWritten --trigger-event-filters=type=google.cloud.firestore.document.v1.written --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}products/{productId}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
```

- [ ] **Step 7: Verify the build and full suite**

Run: `cd functions/loans && go build -v ./... && go test ./... -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add functions/loans/triggers/product_view_projection.go \
        functions/loans/loooans_cloud_functions.go \
        .github/scripts/deploy_functions.sh \
        functions/loans/test/triggers/product_view_projection_test.go
git commit -m "feat(search): own product_views projection in a Go trigger"
```

---

### Task 6: Firestore indexes

**Files:**
- Modify: `apps/loans/firestore.indexes.json`

**Interfaces:**
- Consumes: the `search_tokens` field written by Tasks 4 and 5
- Produces: the index set the frontend plan's queries depend on

- [ ] **Step 1: Add the client-search index**

In `apps/loans/firestore.indexes.json`, add to the `indexes` array. Field order
matters — it must match the query built in the frontend plan:

```json
{
  "collectionGroup": "users",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deleted_at", "order": "ASCENDING" },
    { "fieldPath": "company_id", "order": "ASCENDING" },
    { "fieldPath": "user_role", "order": "ASCENDING" },
    { "fieldPath": "search_tokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "updated_at", "order": "DESCENDING" }
  ]
}
```

- [ ] **Step 2: Add the offer-search indexes**

v1 supports three facets — company, interest rate, term — so add the base index
plus one per facet combination that the UI can produce:

```json
{
  "collectionGroup": "product_views",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deleted_at", "order": "ASCENDING" },
    { "fieldPath": "search_tokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "updated_at", "order": "DESCENDING" }
  ]
},
{
  "collectionGroup": "product_views",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deleted_at", "order": "ASCENDING" },
    { "fieldPath": "company_id", "order": "ASCENDING" },
    { "fieldPath": "search_tokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "updated_at", "order": "DESCENDING" }
  ]
},
{
  "collectionGroup": "product_views",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deleted_at", "order": "ASCENDING" },
    { "fieldPath": "term", "order": "ASCENDING" },
    { "fieldPath": "search_tokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "interest_rate", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "product_views",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "deleted_at", "order": "ASCENDING" },
    { "fieldPath": "company_id", "order": "ASCENDING" },
    { "fieldPath": "term", "order": "ASCENDING" },
    { "fieldPath": "search_tokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "interest_rate", "order": "ASCENDING" }
  ]
}
```

- [ ] **Step 3: Validate the JSON**

Run: `python3 -m json.tool apps/loans/firestore.indexes.json > /dev/null && echo OK`
Expected: `OK`. A trailing comma here fails the deploy, not the build.

- [ ] **Step 4: Commit**

```bash
git add apps/loans/firestore.indexes.json
git commit -m "feat(search): composite indexes for client and offer search"
```

---

### Task 7: Backfill job

**Files:**
- Create: `functions/loans/cmd/backfill_search_tokens/main.go`
- Test: `functions/loans/test/cmd/backfill_search_tokens_test.go`

**Interfaces:**
- Consumes: `search.UserTokens`, `search.ProductViewTokens` (Task 3)
- Produces: `backfill.NeedsUpdate(doc map[string]any, want []string) bool`

Existing documents have no `search_tokens` and are therefore invisible to search.
The backfill's completeness is a correctness requirement, not a nicety. It must be
re-runnable — assume more than one pass will be needed rather than discovering it.

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/cmd/backfill_search_tokens_test.go`:

```go
package backfill_test

import (
	"testing"

	backfill "com.loooans.app/cmd/backfill_search_tokens"
)

// Re-runnability is the property under test: a second pass over an
// already-migrated collection must write nothing.
func TestNeedsUpdate(t *testing.T) {
	cases := []struct {
		name string
		doc  map[string]any
		want []string
		out  bool
	}{
		{"missing tokens", map[string]any{}, []string{"cr", "cru", "cruz"}, true},
		{"stale tokens", map[string]any{"search_tokens": []any{"old"}}, []string{"cr"}, true},
		{"current tokens", map[string]any{"search_tokens": []any{"cr", "cru"}}, []string{"cr", "cru"}, false},
		{"both empty", map[string]any{"search_tokens": []any{}}, nil, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := backfill.NeedsUpdate(tc.doc, tc.want); got != tc.out {
				t.Errorf("NeedsUpdate = %v, want %v", got, tc.out)
			}
		})
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions/loans && go test ./test/cmd/... -v`
Expected: FAIL — package does not exist.

- [ ] **Step 3: Write the comparison helper**

`package main` cannot be imported by a test, so the logic lives in an importable
`backfill` package and a thin `main` wraps it.

Create `functions/loans/cmd/backfill_search_tokens/backfill.go`:

```go
// Package backfill populates search_tokens on existing users and product_views
// documents. Safe to re-run: documents whose tokens already match are skipped,
// so a second pass writes nothing.
package backfill

// NeedsUpdate reports whether doc's stored tokens differ from want.
func NeedsUpdate(doc map[string]any, want []string) bool {
	rawValues, _ := doc["search_tokens"].([]any)

	existing := make([]string, 0, len(rawValues))
	for _, raw := range rawValues {
		if value, ok := raw.(string); ok {
			existing = append(existing, value)
		}
	}

	if len(existing) != len(want) {
		return true
	}
	for i := range existing {
		if existing[i] != want[i] {
			return true
		}
	}
	return false
}
```

Create `functions/loans/cmd/backfill_search_tokens/cmd/main.go`:

```go
// Command backfill_search_tokens runs the search-token backfill.
//
//	go run ./cmd/backfill_search_tokens/cmd -collection=users -project=loooans-dev-stg
package main

import (
	"flag"
	"log"

	backfill "com.loooans.app/cmd/backfill_search_tokens"
)

func main() {
	collection := flag.String("collection", "", "users or product_views")
	project := flag.String("project", "", "Firebase project id")
	dryRun := flag.Bool("dry-run", true, "report what would change without writing")
	flag.Parse()

	if err := backfill.Run(*collection, *project, *dryRun); err != nil {
		log.Fatalf("backfill failed: %v", err)
	}
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd functions/loans && go test ./test/cmd/... -v`
Expected: PASS, all four cases.

- [ ] **Step 5: Implement the paged run loop**

Add `Run(collection, project string, dryRun bool) error` to the `backfill` package.
It must: page through the collection with `firestore.Client.Collection(...).
Limit(500).StartAfter(lastDoc)`, compute the wanted tokens per document type
(`search.UserTokens` for `users`, `search.ProductViewTokens` for `product_views`),
skip documents where `NeedsUpdate` is false, batch writes in groups of 500, log a
running count of scanned/updated/skipped, and honour `dryRun` by logging without
writing. Use `utils.GetCollectionPrefix()` for the collection path.

- [ ] **Step 6: Dry-run against development**

Run: `cd functions/loans && go run ./cmd/backfill_search_tokens/cmd -collection=users -project=loooans-dev-stg -dry-run=true`
Expected: a scanned/updated/skipped count, and no writes. Confirm the updated count
matches the number of users you expect to lack tokens.

- [ ] **Step 7: Commit**

```bash
git add functions/loans/cmd/backfill_search_tokens/ \
        functions/loans/test/cmd/backfill_search_tokens_test.go
git commit -m "feat(search): re-runnable backfill for search tokens"
```

---

## Done when

- [ ] `cd functions/loans && go build -v ./...` succeeds
- [ ] `cd functions/loans && go test ./... -v` passes
- [ ] `python3 -m json.tool apps/loans/firestore.indexes.json` succeeds
- [ ] Golden vectors exist and are asserted by Go — the frontend plan asserts the same file
- [ ] Backfill dry-run reports a sane count against `loooans-dev-stg`
- [ ] PR opened against `develop` (never `master`)

## Notes for the executor

- **Do not** reach for `NormalizePhoneE164` in the tokenizer. It needs a country
  from the user's address and fails when that is missing, which would silently
  make those users unfindable. Task 2 explains the alternative.
- The `search_tokens` write in Task 4 fires the same trigger again. The bool
  returned by `SearchTokensForUser` is what stops it. Do not remove it.
- Firestore indexes are deployed separately from functions. Adding the JSON does
  not create them — queries will fail with an index-required error until they are
  deployed and finish building.
