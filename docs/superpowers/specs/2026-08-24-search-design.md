# Search — design

Design for finstack#56 (originally anatechopc/loooans#56, "implement search").
Brainstormed 2026-08-21 → 2026-08-24.

## Problem

The app-bar search button is a stub. `apps/loans/lib/widgets/layout_widgets.dart:270`
renders an `IconButton` whose `onPressed` only calls
`debugPrint('route location: ...')` — the first line of the original issue's TODO and
nothing after it.

The only real search in the product is `BorrowerSearchWidget` in the Payment Center. It
loads **every** customer for the company (`limit: null`) and filters in Dart with
`.contains()` on each keystroke (`user_bloc.dart:332`). That is acceptable at current
scale and will not survive the growth the maintainer expects (hundreds of thousands of
users, possibly millions).

## Scope

**In v1**

- Text search over **clients** (`users`) and **offers** (`product_views`).
- Filter controls on offer results (company, interest rate, term).
- Role-derived scopes, enforced in query construction.
- Two surfaces: app-bar field with results overlay, and a `/search` page.

**Deferred, with issues filed**

- BigQuery reporting migration — finstack#98.
- Moving remaining client-written view projections to Go triggers — finstack#99.
- Typo tolerance and relevance ranking (needs a real search engine — see *Swap point*).
- A typed `field:value` query DSL. Rejected in favour of filter controls; see *Rejected*.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Scope defaults from route; explicit `products:`-style prefix overrides | The original issue's "no prefix = no search" rule makes the feature invisible to anyone not told the syntax |
| 2 | Indexed prefix search on a denormalized token array | Full-collection reads per keystroke do not survive the expected growth |
| 3 | Role decides which scopes exist at all | A borrower must never be able to construct a clients query |
| 4 | Prefix-expansion token array, prefixes of length 2–12 | Preserves the substring-ish behaviour `.contains()` gives today |
| 5 | v1 includes offer filter **controls**, not a typed DSL | Firestore forces enumerated filter combinations anyway; controls are discoverable |
| 6 | Hybrid surface: overlay + `/search` page | Staff want speed; borrowers want room. One surface serves the other badly |
| 7 | Client result row shows name + mobile | Matches the existing typeahead; needs no data the user document lacks |
| 8 | Search renders as a **field** on wide screens, not an icon | The `⌘K` badge only teaches the shortcut if the field is visible |
| 9 | `Icons.search_rounded` | Matches `Icons.payments_rounded` beside it. The app has 55 base / 42 rounded / **1** outlined icon — there is no outline convention to follow yet |

## Architecture

### 1. Token index (backend)

Two collections gain a `search_tokens` array: `users` and `product_views`.

**Source fields**

| Collection | Fields |
|---|---|
| `users` | `first_name`, `middle_name`, `last_name`, `mobile_number`, `email_address` |
| `product_views` | `company_name`, `loan_type`, `tag_line` |

`product_views` has no product-name field; `loan_type` serves that role, because the
add-product flow offers `CommonProducts` presets plus an "Others" branch where the
lender types their own value. Whether products deserve a real `name` field is a product
question, not a blocker here.

**Tokenization rule** — one Go function, used by every collection so the two cannot drift:

1. Lowercase; strip diacritics.
2. Split the field into whitespace-separated words.
3. For each word emit **both** the de-punctuated joined form and the sub-tokens obtained
   by splitting on runs of non-alphanumeric characters.
4. Prefix-expand every token to lengths **2–12**. Tokens shorter than 2 are indexed whole.
5. Additionally emit the **full normalized field value** as its own token.

```
O'Brien                   -> obrien, o, brien              (+ prefixes)
Mary-Jane                 -> maryjane, mary, jane          (+ prefixes)
juan_cruz-x+tag@gmail.com -> juan_cruz-x+tag@gmail.com     (full)
                             juan, cruz, x, tag, gmail, com (+ prefixes)
David Andrew Francis Duldulao -> 22 prefix entries, plus the full value
```

**Why the bounds are what they are**

- **Lower bound 2, not 3.** Two-letter Filipino surnames — Go, Ty, Uy, Sy, Co — are
  otherwise unsearchable. A floor of 1 would make every user match `"d"`.
- **Upper bound 12.** Bounds array size regardless of how long a name is. Queries longer
  than 12 characters match on the first 12, then refine in Dart.
- **Full value token.** Without it, pasting a complete email or phone number — the most
  likely teller action — returns **nothing**, because the split happens before matching.
  This is the failure mode the rule exists to prevent.

**Phone normalization.** Reuse `NormalizePhoneE164`
(`functions/loans/api/service/phone_service.go:55`, already tested). `0917…`, `+63917…`
and `63917…` must collapse to one canonical form, or a client is findable by one
spelling of their own number and not another. Also index the **last 4 digits** as a
discrete token; staff often have only the tail, and prefix expansion cannot match a suffix.

**Symmetric normalization.** The query passes through the same normalizer as the index.
The query planner branches on input shape: contains `@` → email path; predominantly
digits → E.164 path; otherwise → name path with prefix truncation.

**Ownership.** Both collections' tokens are written **server-side**.

- `users` — extend the existing `userCreated` / `userChanges` triggers.
- `product_views` — move projection ownership into a Go trigger firing on `products`,
  so the trigger emits the whole view document. Today the Flutter client writes it
  (`product_view_firestore_service.dart:72`). Moving ownership rather than bolting tokens
  onto a client-written document also removes a write-then-augment cycle that would
  otherwise need a recursion guard.

**Drift risk.** The normalizer exists in Go (indexing) *and* Dart (query construction).
Divergence breaks search invisibly — nobody sees an error, a client simply cannot be
found. Mitigation: a **golden test-vector file** (JSON, input → expected tokens) asserted
by both the Go and Dart suites, so drift fails CI rather than production.

**Indexes.** Composite indexes must enumerate supported query shapes ahead of time; they
cannot be open-ended. All must respect the `deleted_at` soft-delete convention already
present in every index in `apps/loans/firestore.indexes.json`.

- `users`: `company_id` + `search_tokens` (array-contains) + `user_role` + `deleted_at`
- `product_views`: `search_tokens` plus one index per supported filter combination.
  v1 supports three facets — **company**, **interest rate**, **term** — so the index set
  is the combinations of those three with `search_tokens` and `deleted_at`. Adding a
  fourth facet later means new indexes, not a code change.

**Backfill.** A re-runnable job over existing documents. It will need more than one pass;
assume that rather than discovering it.

### 2. Query layer

```dart
abstract class SearchIndex {
  Future<SearchResults> query(SearchRequest request);
}
```

`FirestoreSearchIndex` implements it now. This is the **swap point**: when prefix
matching is outgrown, a `TypesenseSearchIndex` replaces it without the bloc or UI
changing. It is what makes choosing Firestore today reversible rather than a trap.

**Scope resolution**, strictly ordered:

1. **Role** determines which scopes exist. A `customer` has no clients scope — not hidden
   in the UI, *absent from the resolver*, so no caller can construct one.
2. **Explicit prefix** overrides, but only among scopes the role already permits.
3. **Route** supplies the default. Staff default to clients, borrowers to offers.

| Role | Scopes |
|---|---|
| `customer` | offers, across all companies |
| `teller`, `loanOfficer`, `admin` | clients + products, own `company_id` only |
| `appAdmin` | all |

**Authorization is in query construction, not filtering.** `FirestoreSearchIndex`
injects `company_id == currentUser.companyId` for every staff query. It is never a
caller-supplied parameter, because a caller able to pass it is able to pass the wrong
one. Post-filtering in Dart would be the wrong shape entirely — it would mean the wrong
documents had already been read.

**Two-stage matching.** Firestore returns candidates via `array-contains` on the
truncated term; Dart refines against the full query string. This is what makes the 12
character cap correct rather than lossy.

### 3. Frontend

`apps/loans/lib/features/search/`

| File | Responsibility |
|---|---|
| `bloc/search_bloc.dart` | query, scope, filters, results, status; owns the request-id guard |
| `search_scope_resolver.dart` | role → permitted scopes → prefix override → route default |
| `widget/search_field.dart` | app-bar field with shortcut badge; collapses to icon |
| `widget/search_overlay.dart` | results dropdown, top 5 + "See all" |
| `screen/search_screen.dart` | `/search` route, tabs + chips + full results |
| `widget/search_result_tile.dart` | one row, shared by both surfaces |
| `widget/offer_filter_bar.dart` | filter controls |

**Out-of-order results.** `bloc_concurrency` is **not** a dependency, so there is no
`restartable()` transformer. The bloc carries a monotonically increasing request id and
drops any response that is not the latest. Without this a slow query for `de` lands after
a fast one for `dela cruz` and overwrites correct results with stale ones. This is the
easiest bug to ship here and the hardest to catch by hand.

**Debounce.** Reuse `apps/loans/lib/utils/debounce.dart` (already used at 500ms in
`add_user_widget.dart`). Use ~250ms for typeahead; 500ms feels sluggish. Minimum 2
characters before a query is issued.

**Entry points.** `/`, `/dashboard`, `/users`, `/payment-center` and `/chat` sit inside
the `ShellRoute` and inherit the field via `HomeScreen` → `AppWidgets.defaultAppBar`.
`/clients/:action` and `/loans/:action` are outside the shell and build their own
scaffolds — they get the icon in their own app bars. A global `Cmd/Ctrl+K` is bound above
the router and works on every route regardless of shell membership.

`defaultAppBar` already takes role flags (`showMyLoansButton`, `showAddBorrowerButton`,
`showAddCapitalButton`); the search field follows that pattern.

**Result rows.** Clients: name + mobile. The secondary line shows **whichever contact
field matched** — the email when the email was searched — so a result you did not
obviously search for still explains itself. Offers: `loan_type`, `company_name`,
`interest_rate`, `max_loanable_amount`, `term`, `review_rating_avg`, `review_count`,
every one already on `product_views`.

**Shortcut discoverability.** The badge renders the platform's own key (`⌘K` on macOS,
`Ctrl K` elsewhere) and is hidden entirely on touch — advertising a shortcut to someone
with no keyboard is worse than showing nothing. The shortcut is always an accelerator,
never the only route to a surface.

**Placeholder tracks the resolved scope** — "Search clients…" / "Search offers…" — the
cheapest way to make the context default visible before someone types.

**Empty state hints.** Prefix matching genuinely cannot match mid-word, so "no results"
is sometimes misleading rather than true. The empty state suggests a shorter term or
searching by mobile number.

## Error handling

| Case | Behaviour |
|---|---|
| Query < 2 characters | No query issued; prompt to keep typing |
| Firestore error | Error state in the overlay; does not clear the previous query |
| Stale response | Dropped by request-id guard |
| Missing `search_tokens` (pre-backfill) | Document is unfindable — the backfill's completeness is a correctness requirement, not a nicety |
| Role has no scope for a typed prefix | Prefix treated as literal text, not as a scope |

## Testing

- **Golden token vectors** — shared JSON fixture asserted from both Go and Dart. Covers
  two-letter surnames, hyphens, apostrophes, diacritics, long tokens, full emails, and
  the three phone spellings.
- **Go unit tests** — tokenizer, trigger projection, E.164 reuse.
- **Bloc tests** — scope resolution per role (*a customer can never resolve a clients
  scope* is a test, not a UI convention), request-id ordering under interleaved responses.
- **Widget tests** — overlay and `/search` render the same tile; field collapses on narrow.
- Note finstack#40/#41 — Flutter test infrastructure is still open; this feature may need
  to establish some of its own scaffolding.

## Rollout

Backend first, split PRs, per the project's standing rule.

1. **PR 1 (backend)** — tokenizer + golden vectors, `users` trigger extension,
   `product_views` projection moved to a trigger, indexes, backfill job. No visual
   surface, so it is unaffected by the planned app redesign.
2. **PR 2 (frontend)** — `SearchIndex`, bloc, field, overlay, `/search`, filter controls.

Deploy note: nothing here reaches production until the prod-deploy prerequisites are
resolved — finstack has never deployed Go functions to prod
(`loans-functions-production.yml` triggers on `master`; no such branch exists and the
workflow has zero recorded runs).

## Rejected

- **BigQuery as the search backend.** Proposed during brainstorming. BigQuery is an OLAP
  warehouse: fixed per-query planning overhead measured in hundreds of milliseconds to
  seconds, billing per byte scanned with a per-table floor, and not built for high-QPS
  small lookups. All disqualifying for typeahead. It remains the right tool for
  reporting — finstack#98. The reusable piece is the change-data-capture *pipeline*, not
  the query store: search and reporting have opposite requirements, and one engine
  serving both is bad at both.
- **A typed `field:value` DSL.** Firestore composite indexes must match exact query
  shapes, so an open-ended DSL is not implementable; every allowed combination needs an
  index shipped ahead of time. A DSL would therefore be a typed front-end over an
  enumerated filter set — which is an argument for controls, since nobody discovers
  `interest:10%` unaided.
- **Prefix range on a single normalized name field.** Simplest possible index, but
  surname search stops working — a regression against today's `.contains()`.
- **Typesense/Algolia now.** The correct destination once typo tolerance and ranking
  matter. Premature today; the `SearchIndex` interface keeps the migration cheap.

## Open questions

- Whether `products` should gain a real `name` field, rather than `loan_type` carrying
  that meaning. Product decision; not blocking, and worth its own ticket.
