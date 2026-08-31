# Search Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give staff and borrowers a working search — an app-bar field with a results overlay, a deep-linkable `/search` page with offer filters, and role-derived scopes enforced at query construction.

**Architecture:** A Dart tokenizer mirrors the Go indexer exactly, pinned by the same golden vector file. A `SearchIndex` interface isolates Firestore so the engine can be swapped later. `SearchBloc` owns debounce and a request-id guard against out-of-order responses. Two surfaces render the same result tile.

**Tech Stack:** Flutter (fvm), `flutter_bloc`, `bloc_test`, `mocktail`, `go_router`, `very_good_analysis`.

**Spec:** `docs/superpowers/specs/2026-08-24-search-design.md`

**Depends on:** `docs/superpowers/plans/2026-08-24-search-backend.md` — **merged** (finstack#104, #105). Composite indexes are **deployed to dev, stg and prod**; the backfill has been run and verified **on dev only**, so stg and prod hold no `search_tokens` on pre-existing documents yet and queries there return only documents written since the triggers shipped. Six indexes back this feature — 2 on `users`, 4 on `product_views` — and the per-environment files `firestore.indexes.{dev,stg,prod}.json` are the source of truth; `firestore.indexes.json` is a scratch artifact `deploy-indexes.sh` overwrites, and edits made there are silently discarded.

## Global Constraints

- Always `fvm flutter`, never bare `flutter`.
- Lint is `very_good_analysis`; trailing commas and `const` are enforced. Run `fvm flutter analyze` before every commit.
- Tests use `bloc_test` + `mocktail`, and `pumpApp` from `apps/loans/test/helpers/pump_app.dart` for widget tests.
- Prefix bounds must match the backend exactly: **min 2, max 12**, full value exempt from the cap. The golden vector file is the contract.
- Phone canonicalization is digits-only — strip non-digits, then a leading `63`, then a leading `0`. Do **not** reimplement E.164 parsing.
- Icons use `Icons.search_rounded`, matching `Icons.payments_rounded` beside it. The app has 55 base / 42 rounded / 1 outlined icon — there is no outline convention to follow.
- Responsive breakpoints come from `getScreenSize(context:)` / `ScreenSize` in `apps/loans/lib/utils/screen_helpers.dart`.
- Never push to `master`.

## File Structure

| File | Responsibility |
|---|---|
| `apps/loans/lib/features/search/search_tokenizer.dart` | Query-side normalization, mirroring the Go indexer |
| `apps/loans/lib/features/search/search_scope.dart` | `SearchScope` enum and parsed-query value type |
| `apps/loans/lib/features/search/search_scope_resolver.dart` | role → permitted scopes → prefix override → route default |
| `apps/loans/lib/features/search/search_index.dart` | `SearchIndex` interface, request/result types |
| `apps/loans/lib/features/search/firestore_search_index.dart` | Firestore implementation; injects `company_id` |
| `apps/loans/lib/features/search/bloc/search_bloc.dart` | query, scope, filters, results; request-id guard |
| `apps/loans/lib/features/search/widget/search_field.dart` | App-bar field with shortcut badge; collapses to icon |
| `apps/loans/lib/features/search/widget/search_overlay.dart` | Top 5 results + "See all" |
| `apps/loans/lib/features/search/widget/search_result_tile.dart` | One row, shared by both surfaces |
| `apps/loans/lib/features/search/widget/offer_filter_bar.dart` | Company / interest / term controls |
| `apps/loans/lib/features/search/screen/search_screen.dart` | `/search` route |

---

### Task 1: Dart tokenizer, pinned to the shared golden vectors

**Files:**
- Create: `apps/loans/lib/features/search/search_tokenizer.dart`
- Test: `apps/loans/test/features/search/search_tokenizer_test.dart`

**Interfaces:**
- Consumes: `functions/loans/utils/search/testdata/golden_tokens.json` (backend plan, Task 1)
- Produces: `SearchTokenizer.normalize(String) → String`, `SearchTokenizer.tokenize(List<String>) → List<String>`, `SearchTokenizer.canonicalPhone(String) → String`, `SearchTokenizer.minPrefix = 2`, `SearchTokenizer.maxPrefix = 12`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_tokenizer_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_tokenizer.dart';

void main() {
  group('SearchTokenizer', () {
    test('two-letter surnames are indexed whole', () {
      expect(SearchTokenizer.tokenize(['Go']), ['go']);
    });

    test('names expand to prefixes from two characters', () {
      expect(SearchTokenizer.tokenize(['Cruz']), ['cr', 'cru', 'cruz']);
    });

    test('canonical phone collapses every spelling', () {
      expect(SearchTokenizer.canonicalPhone('09175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('+639175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('0917 555-0142'), '9175550142');
    });

    // This is the contract with the Go indexer. If it fails, search breaks
    // invisibly - a client simply cannot be found - so fix the mismatch
    // rather than relaxing the assertion.
    test('matches the shared golden vectors', () {
      final file = File(
        '../../functions/loans/utils/search/testdata/golden_tokens.json',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'golden vectors missing - is the backend plan merged?',
      );

      final golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final cases = golden['cases'] as List<dynamic>;
      expect(cases, isNotEmpty);

      for (final entry in cases.cast<Map<String, dynamic>>()) {
        final input = (entry['input'] as List<dynamic>).cast<String>();
        final expected = (entry['tokens'] as List<dynamic>).cast<String>();
        // Compared as SETS, deliberately. Go sorts byte-wise over UTF-8;
        // Dart's List.sort() compares UTF-16 code units. Those orders can
        // diverge for non-BMP codepoints even when the token sets are
        // identical, which would fail this test for no functional reason:
        // Dart never writes tokens, it only builds one query token, so
        // ordering carries no meaning on this side. Membership is the
        // actual contract.
        expect(
          SearchTokenizer.tokenize(input).toSet(),
          expected.toSet(),
          reason: 'tokenization drifted from Go for $input',
        );
      }
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_tokenizer_test.dart`
Expected: FAIL — `search_tokenizer.dart` does not exist.

- [ ] **Step 3: Write the tokenizer**

Create `apps/loans/lib/features/search/search_tokenizer.dart`:

```dart
/// Query-side mirror of the Go indexer in
/// `functions/loans/utils/search/tokenizer.go`.
///
/// These two implementations must agree exactly. Drift breaks search silently:
/// no error surfaces, a client simply stops being findable. The shared golden
/// vectors at `functions/loans/utils/search/testdata/golden_tokens.json` are
/// asserted from both languages so drift fails CI instead of production.
abstract final class SearchTokenizer {
  /// Shortest prefix emitted. Two, not three, because two-letter Filipino
  /// surnames (Go, Ty, Uy, Sy, Co) are common and would otherwise be
  /// unsearchable.
  static const int minPrefix = 2;

  /// Longest prefix emitted. Queries longer than this match on the first
  /// [maxPrefix] characters and are refined in Dart against the full term.
  static const int maxPrefix = 12;

  static final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');
  static final RegExp _nonDigit = RegExp(r'[^0-9]');
  static const String _accented = 'áàâäãåéèêëíìîïóòôöõúùûüñç';
  static const String _plain = 'aaaaaaeeeeiiiiooooouuuunc';

  /// Lowercases, folds diacritics and trims. Both indexing and querying apply
  /// it, so it must match [Normalize] in the Go tokenizer.
  static String normalize(String value) {
    final lowered = value.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final char in lowered.split('')) {
      final index = _accented.indexOf(char);
      buffer.write(index == -1 ? char : _plain[index]);
    }
    return buffer.toString();
  }

  /// Returns the sorted, deduplicated token set for [values].
  static List<String> tokenize(List<String> values) {
    final tokens = <String>{};

    for (final value in values) {
      final normalized = normalize(value);
      if (normalized.isEmpty) continue;

      // The whole value, uncapped - this is what makes a pasted email or
      // phone number match.
      tokens.add(normalized);

      for (final word in normalized.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final parts =
            word.split(_nonAlphanumeric).where((p) => p.isNotEmpty).toList();

        final joined = parts.join();
        if (joined.isNotEmpty) _addPrefixes(tokens, joined);
        for (final part in parts) {
          _addPrefixes(tokens, part);
        }
      }
    }

    return tokens.toList()..sort();
  }

  /// Reduces a phone number to its national significant digits, so that
  /// `09175550142`, `+639175550142` and `9175550142` collapse to one token.
  ///
  /// Deliberately not E.164 parsing: search needs consistency, not validity,
  /// and the E.164 path requires a country the query side does not have.
  static String canonicalPhone(String raw) {
    var digits = raw.replaceAll(_nonDigit, '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  static void _addPrefixes(Set<String> tokens, String token) {
    if (token.isEmpty) return;
    if (token.length < minPrefix) {
      tokens.add(token);
      return;
    }
    final limit = token.length < maxPrefix ? token.length : maxPrefix;
    for (var i = minPrefix; i <= limit; i++) {
      tokens.add(token.substring(0, i));
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/loans && fvm flutter test test/features/search/search_tokenizer_test.dart`
Expected: PASS, all four tests including the golden vectors.

- [ ] **Step 5: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/search_tokenizer.dart \
        apps/loans/test/features/search/search_tokenizer_test.dart
git commit -m "feat(search): Dart tokenizer pinned to shared golden vectors"
```

---

### Task 2: Scope resolution

**Files:**
- Create: `apps/loans/lib/features/search/search_scope.dart`
- Create: `apps/loans/lib/features/search/search_scope_resolver.dart`
- Test: `apps/loans/test/features/search/search_scope_resolver_test.dart`

**Interfaces:**
- Consumes: `UserRole` from `package:user_repository/user_repository.dart`, `Paths` from `package:loooans/app/routing/paths.dart`
- Produces: `enum SearchScope { clients, offers }`, `class ParsedQuery { SearchScope scope; String term; }`, `SearchScopeResolver.scopesFor(UserRole) → Set<SearchScope>`, `SearchScopeResolver.resolve({required UserRole role, required String location, required String rawQuery}) → ParsedQuery`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_scope_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  group('SearchScopeResolver.scopesFor', () {
    // The security-relevant case: a borrower has no clients scope at all.
    // Not hidden in the UI - absent from the resolver, so no caller can
    // construct a clients query even by trying.
    test('a customer can never resolve a clients scope', () {
      expect(
        SearchScopeResolver.scopesFor(UserRole.customer),
        {SearchScope.offers},
      );
    });

    test('staff roles get both scopes', () {
      for (final role in [UserRole.teller, UserRole.loanOfficer, UserRole.admin]) {
        expect(
          SearchScopeResolver.scopesFor(role),
          {SearchScope.clients, SearchScope.offers},
          reason: '$role should have both scopes',
        );
      }
    });
  });

  group('SearchScopeResolver.resolve', () {
    test('staff default to clients', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.paymentCenter,
        rawQuery: 'dela cruz',
      );
      expect(parsed.scope, SearchScope.clients);
      expect(parsed.term, 'dela cruz');
    });

    test('borrowers default to offers', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: Paths.index,
        rawQuery: 'salary',
      );
      expect(parsed.scope, SearchScope.offers);
    });

    test('an explicit prefix overrides the route default', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.paymentCenter,
        rawQuery: 'products: salary',
      );
      expect(parsed.scope, SearchScope.offers);
      expect(parsed.term, 'salary');
    });

    // A prefix naming a scope the role lacks must not escalate. It is text.
    test('a prefix for a forbidden scope is treated as literal text', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: Paths.index,
        rawQuery: 'clients: dela cruz',
      );
      expect(parsed.scope, SearchScope.offers);
      expect(parsed.term, 'clients: dela cruz');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_scope_resolver_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Write the scope types**

Create `apps/loans/lib/features/search/search_scope.dart`:

```dart
/// What a search query is searching over.
enum SearchScope {
  clients('clients'),
  offers('products');

  const SearchScope(this.prefix);

  /// The token a user types to force this scope, as in `products: salary`.
  final String prefix;
}

/// A raw query resolved into a scope and the term to search for.
class ParsedQuery {
  const ParsedQuery({required this.scope, required this.term});

  final SearchScope scope;
  final String term;
}
```

- [ ] **Step 4: Write the resolver**

Create `apps/loans/lib/features/search/search_scope_resolver.dart`:

```dart
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:user_repository/user_repository.dart';

/// Resolves a raw query into a scope, in strict order: role decides which
/// scopes exist at all, an explicit prefix overrides among those, and the
/// route supplies the default.
abstract final class SearchScopeResolver {
  /// Scopes available to [role]. A customer has no clients scope - this is the
  /// authorization boundary, not a UI preference.
  static Set<SearchScope> scopesFor(UserRole role) {
    switch (role) {
      case UserRole.customer:
        return {SearchScope.offers};
      case UserRole.teller:
      case UserRole.loanOfficer:
      case UserRole.admin:
      case UserRole.appAdmin:
        return {SearchScope.clients, SearchScope.offers};
    }
  }

  static ParsedQuery resolve({
    required UserRole role,
    required String location,
    required String rawQuery,
  }) {
    final permitted = scopesFor(role);
    final trimmed = rawQuery.trim();

    for (final scope in SearchScope.values) {
      final marker = '${scope.prefix}:';
      if (!trimmed.toLowerCase().startsWith(marker)) continue;
      // A prefix naming a scope this role lacks must not escalate; fall
      // through and treat the whole string as search text.
      if (!permitted.contains(scope)) break;
      return ParsedQuery(
        scope: scope,
        term: trimmed.substring(marker.length).trim(),
      );
    }

    return ParsedQuery(
      scope: _defaultScope(role, location, permitted),
      term: trimmed,
    );
  }

  static SearchScope _defaultScope(
    UserRole role,
    String location,
    Set<SearchScope> permitted,
  ) {
    if (location.startsWith('/offers') || location == Paths.index) {
      if (permitted.contains(SearchScope.offers)) return SearchScope.offers;
    }
    if (permitted.contains(SearchScope.clients)) return SearchScope.clients;
    return SearchScope.offers;
  }
}
```

If `UserRole` has members beyond those listed, the switch will not compile —
add them to the staff branch or the customer branch deliberately. An exhaustive
switch is the point: a new role must not silently inherit client access.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/search_scope_resolver_test.dart`
Expected: PASS, all six tests.

- [ ] **Step 6: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/search_scope.dart \
        apps/loans/lib/features/search/search_scope_resolver.dart \
        apps/loans/test/features/search/search_scope_resolver_test.dart
git commit -m "feat(search): role-derived scope resolution"
```

---

### Task 3: SearchIndex interface and Firestore implementation

**Files:**
- Create: `apps/loans/lib/features/search/search_index.dart`
- Create: `apps/loans/lib/features/search/firestore_search_index.dart`
- Test: `apps/loans/test/features/search/firestore_search_index_test.dart`

**Interfaces:**
- Consumes: `SearchTokenizer` (Task 1), `SearchScope` (Task 2)
- Produces: `abstract class SearchIndex { Future<SearchResults> query(SearchRequest r); }`, `class SearchRequest`, `class SearchResults`, `class OfferFilters`, `class FirestoreSearchIndex implements SearchIndex`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/firestore_search_index_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';

void main() {
  group('SearchRequest', () {
    // Firestore matches array-contains on a single token, so a multi-word
    // query has to pick one and refine the rest client-side.
    test('queryToken truncates to maxPrefix', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'bartholomewson',
        companyId: 'company-1',
      );
      expect(request.queryToken, 'bartholomews');
    });

    test('queryToken canonicalizes a pasted phone number', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: '0917 555 0142',
        companyId: 'company-1',
      );
      expect(request.queryToken, '9175550142');
    });

    test('queryToken keeps a pasted email whole', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'juan.cruz@gmail.com',
        companyId: 'company-1',
      );
      expect(request.queryToken, 'juan.cruz@gmail.com');
    });

    test('a term shorter than minPrefix is not searchable', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'd',
        companyId: 'company-1',
      );
      expect(request.isSearchable, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/firestore_search_index_test.dart`
Expected: FAIL — `search_index.dart` does not exist.

- [ ] **Step 3: Write the interface and request type**

Create `apps/loans/lib/features/search/search_index.dart`:

```dart
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_tokenizer.dart';

/// Filters applied to offer results. v1 supports exactly these three facets;
/// each additional one needs its own composite index.
class OfferFilters {
  const OfferFilters({this.companyId, this.maxInterestRate, this.term});

  final String? companyId;
  final double? maxInterestRate;
  final String? term;

  bool get isEmpty =>
      companyId == null && maxInterestRate == null && term == null;
}

class SearchRequest {
  const SearchRequest({
    required this.scope,
    required this.term,
    required this.companyId,
    this.filters = const OfferFilters(),
    this.limit = 20,
  });

  final SearchScope scope;
  final String term;

  /// The searching user's company. Injected by the index, never by a caller -
  /// a caller able to pass it is able to pass the wrong one.
  final String companyId;

  final OfferFilters filters;
  final int limit;

  /// The single token sent to Firestore. Longer terms are truncated to
  /// [SearchTokenizer.maxPrefix] and refined client-side; a term that looks
  /// like a phone number is canonicalized so every spelling matches.
  String get queryToken {
    final normalized = SearchTokenizer.normalize(term);

    final digitsOnly = RegExp(r'^[0-9+\s()-]+$');
    if (digitsOnly.hasMatch(normalized) && normalized.trim().isNotEmpty) {
      return SearchTokenizer.canonicalPhone(normalized);
    }

    final first = normalized.split(RegExp(r'\s+')).first;
    final candidate = normalized.contains('@') ? normalized : first;

    return candidate.length > SearchTokenizer.maxPrefix
        ? candidate.substring(0, SearchTokenizer.maxPrefix)
        : candidate;
  }

  bool get isSearchable =>
      SearchTokenizer.normalize(term).length >= SearchTokenizer.minPrefix;
}

class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.matchedField,
  });

  final String id;
  final String title;

  /// The line under the title. Shows whichever contact field matched, so a
  /// result the user did not obviously search for still explains itself.
  final String subtitle;
  final String matchedField;
}

class SearchResults {
  const SearchResults({required this.items, required this.scope});

  final List<SearchResultItem> items;
  final SearchScope scope;

  static const empty = SearchResults(items: [], scope: SearchScope.clients);
}

/// The swap point. `FirestoreSearchIndex` implements this now; a
/// `TypesenseSearchIndex` can replace it without the bloc or UI changing,
/// which is what makes choosing Firestore today reversible.
abstract class SearchIndex {
  Future<SearchResults> query(SearchRequest request);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/firestore_search_index_test.dart`
Expected: PASS, all four tests.

- [ ] **Step 5: Write the Firestore implementation**

Create `apps/loans/lib/features/search/firestore_search_index.dart` implementing
`SearchIndex`. It must:

- Build a `QueryStatement` list per scope, following the pattern in
  `apps/loans/lib/features/users/bloc/user_bloc.dart:332`.
- For `SearchScope.clients`: `company_id == request.companyId`,
  `user_role == UserRole.customer.name`, `search_tokens arrayContains
  request.queryToken`. **`company_id` is injected here, from the authenticated
  user — never read from `SearchRequest` supplied by UI code.**
- For `SearchScope.offers`: `search_tokens arrayContains request.queryToken`,
  plus each non-null `OfferFilters` field.
- Refine the returned candidates in Dart against the **full** `request.term`,
  because the query token was truncated.
- Set `matchedField` to whichever field produced the match, and `subtitle` to
  the email when the email matched, otherwise the mobile number.
- Respect the soft-delete convention used by every existing index.

- [ ] **Step 6: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/search_index.dart \
        apps/loans/lib/features/search/firestore_search_index.dart \
        apps/loans/test/features/search/firestore_search_index_test.dart
git commit -m "feat(search): SearchIndex interface and Firestore implementation"
```

---

### Task 4: SearchBloc with debounce and request-id guard

**Files:**
- Create: `apps/loans/lib/features/search/bloc/search_bloc.dart`
- Create: `apps/loans/lib/features/search/bloc/search_event.dart`
- Create: `apps/loans/lib/features/search/bloc/search_state.dart`
- Test: `apps/loans/test/features/search/search_bloc_test.dart`

**Interfaces:**
- Consumes: `SearchIndex`, `SearchRequest`, `SearchResults` (Task 3), `SearchScopeResolver` (Task 2)
- Produces: `SearchBloc({required SearchIndex searchIndex})`, `QueryChangedEvent(String query, {required String location})`, `FiltersChangedEvent(OfferFilters filters)`, `SearchState(status, scope, term, results, filters)`, `enum SearchStatus { idle, tooShort, loading, results, empty, error }`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';

class MockSearchIndex extends Mock implements SearchIndex {}

class FakeSearchRequest extends Fake implements SearchRequest {}

void main() {
  setUpAll(() => registerFallbackValue(FakeSearchRequest()));

  late MockSearchIndex index;

  setUp(() => index = MockSearchIndex());

  blocTest<SearchBloc, SearchState>(
    'a one-character query is reported as too short and never queries',
    build: () => SearchBloc(searchIndex: index),
    act: (bloc) => bloc.add(const QueryChangedEvent('d', location: '/users')),
    wait: const Duration(milliseconds: 300),
    expect: () => [
      isA<SearchState>().having((s) => s.status, 'status', SearchStatus.tooShort),
    ],
    verify: (_) => verifyNever(() => index.query(any())),
  );

  // The bug this guard exists to prevent: a slow response for "de" landing
  // after a fast one for "dela cruz" and overwriting correct results.
  blocTest<SearchBloc, SearchState>(
    'a stale response is dropped',
    build: () {
      var call = 0;
      when(() => index.query(any())).thenAnswer((_) async {
        call++;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const SearchResults(
            items: [
              SearchResultItem(
                id: 'stale',
                title: 'Stale',
                subtitle: '',
                matchedField: 'name',
              ),
            ],
            scope: SearchScope.clients,
          );
        }
        return const SearchResults(
          items: [
            SearchResultItem(
              id: 'fresh',
              title: 'Fresh',
              subtitle: '',
              matchedField: 'name',
            ),
          ],
          scope: SearchScope.clients,
        );
      });
      return SearchBloc(searchIndex: index);
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('de', location: '/users'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      bloc.add(const QueryChangedEvent('dela cruz', location: '/users'));
    },
    wait: const Duration(milliseconds: 800),
    verify: (bloc) {
      expect(bloc.state.results.items.single.id, 'fresh');
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_bloc_test.dart`
Expected: FAIL — `search_bloc.dart` does not exist.

- [ ] **Step 3: Write the bloc**

Create the three bloc files. The handler below is the load-bearing part — write
it as given. `bloc_concurrency` is not a dependency, so there is no
`restartable()` transformer; the request-id guard is the entire defence against
a slow response for a shorter prefix overwriting a correct one.

```dart
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({required SearchIndex searchIndex})
      : _searchIndex = searchIndex,
        super(const SearchState()) {
    on<QueryChangedEvent>(_onQueryChanged);
    on<FiltersChangedEvent>(_onFiltersChanged);
  }

  final SearchIndex _searchIndex;
  final _debounce = Debounce(milliseconds: 250);

  /// Incremented on every query. A response whose id no longer matches is
  /// discarded — without this, a slow query for "de" lands after a fast one
  /// for "dela cruz" and replaces correct results with stale ones.
  int _requestId = 0;

  Future<void> _onQueryChanged(
    QueryChangedEvent event,
    Emitter<SearchState> emit,
  ) async {
    final role = AuthenticationService.instance.user.userRole;
    final parsed = SearchScopeResolver.resolve(
      role: role,
      location: event.location,
      rawQuery: event.query,
    );

    if (SearchTokenizer.normalize(parsed.term).length <
        SearchTokenizer.minPrefix) {
      emit(state.copyWith(
        status: SearchStatus.tooShort,
        scope: parsed.scope,
        term: parsed.term,
      ));
      return;
    }

    emit(state.copyWith(
      status: SearchStatus.loading,
      scope: parsed.scope,
      term: parsed.term,
    ));

    final id = ++_requestId;

    try {
      final results = await _searchIndex.query(
        SearchRequest(
          scope: parsed.scope,
          term: parsed.term,
          companyId: AuthenticationService.instance.company.id,
          filters: state.filters,
        ),
      );

      // A newer query started while this one was in flight — drop this result.
      if (id != _requestId) return;

      emit(state.copyWith(
        status: results.items.isEmpty
            ? SearchStatus.empty
            : SearchStatus.results,
        results: results,
      ));
    } catch (err) {
      if (id != _requestId) return;
      // Deliberately keeps state.term, so the field is not cleared under the
      // user when a query fails.
      emit(state.copyWith(status: SearchStatus.error));
    }
  }
}
```

Wire the debounce at the widget's `onChanged` (Task 5) using `_debounce.run`, so
the bloc receives one event per pause rather than per keystroke.
`add_user_widget.dart` uses 500ms; 250ms is the right feel for typeahead.

`_onFiltersChanged` stores the new `OfferFilters` on the state and re-dispatches
`QueryChangedEvent` with the current term, so a chip change re-runs the search.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/search_bloc_test.dart`
Expected: PASS, both tests.

- [ ] **Step 5: Register in DI**

Add `SearchBloc` to `apps/loans/lib/app/di/bloc_providers.dart` and
`FirestoreSearchIndex` to `apps/loans/lib/app/di/repository_providers.dart`,
following the existing entries.

- [ ] **Step 6: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/bloc/ apps/loans/lib/app/di/ \
        apps/loans/test/features/search/search_bloc_test.dart
git commit -m "feat(search): SearchBloc with debounce and stale-response guard"
```

---

### Task 5: Search field and result tile

**Files:**
- Create: `apps/loans/lib/features/search/widget/search_field.dart`
- Create: `apps/loans/lib/features/search/widget/search_result_tile.dart`
- Modify: `apps/loans/lib/widgets/layout_widgets.dart:270-281`
- Test: `apps/loans/test/features/search/search_field_test.dart`

**Interfaces:**
- Consumes: `SearchBloc`, `SearchState` (Task 4), `SearchResultItem` (Task 3)
- Produces: `SearchField({required bool showShortcutBadge})`, `SearchResultTile({required SearchResultItem item, required VoidCallback onTap})`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('the tile shows the matched field as its subtitle', (tester) async {
    await tester.pumpApp(
      Scaffold(
        body: SearchResultTile(
          item: const SearchResultItem(
            id: 'user-1',
            title: 'Juan dela Cruz',
            subtitle: 'juan.cruz@gmail.com',
            matchedField: 'email_address',
          ),
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Juan dela Cruz'), findsOneWidget);
    expect(find.text('juan.cruz@gmail.com'), findsOneWidget);
  });

  testWidgets('the tile reports taps', (tester) async {
    var tapped = false;
    await tester.pumpApp(
      Scaffold(
        body: SearchResultTile(
          item: const SearchResultItem(
            id: 'user-1',
            title: 'Juan dela Cruz',
            subtitle: '0917 555 0142',
            matchedField: 'mobile_number',
          ),
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(SearchResultTile));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_field_test.dart`
Expected: FAIL — `search_result_tile.dart` does not exist.

- [ ] **Step 3: Write the result tile**

Create `apps/loans/lib/features/search/widget/search_result_tile.dart`. One row,
used by both the overlay and `/search`: a `ListTile` with a `CircleAvatar` of
initials in `AppColors.green1`, `item.title` as the title and `item.subtitle` as
the subtitle. Follow the visual shape of `BorrowerSearchWidget`'s `itemBuilder`
in `apps/loans/lib/features/payment_center/widget/borrower_search_widget.dart:37`.

- [ ] **Step 4: Write the search field**

Create `apps/loans/lib/features/search/widget/search_field.dart`:

- Wide screens (`getScreenSize(context:) != ScreenSize.compact`): a `TextField`
  with `prefixIcon: Icon(Icons.search_rounded)` and a trailing shortcut badge.
- Compact screens: an `IconButton` with `Icons.search_rounded` and
  `tooltip: 'Search'` — **no badge**. Advertising a shortcut to someone with no
  keyboard is worse than showing nothing.
- Badge text follows the platform: `⌘K` when
  `Theme.of(context).platform == TargetPlatform.macOS`, otherwise `Ctrl K`.
- `decoration.hintText` tracks `state.scope` — `'Search clients…'` or
  `'Search offers…'`.
- Feed `onChanged` into `SearchBloc.add(QueryChangedEvent(value, location:
  GoRouter.of(context).location))`.

- [ ] **Step 5: Replace the stub**

In `apps/loans/lib/widgets/layout_widgets.dart`, replace the `IconButton` at
lines 270–281 — the one whose `onPressed` only calls `debugPrint` — with
`const SearchField()`. Add a `showSearchField` flag to `defaultAppBar`'s
parameters, defaulting to `true`, following the existing flags
(`showMyLoansButton`, `showAddBorrowerButton`, `showAddCapitalButton`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/`
Expected: PASS.

- [ ] **Step 7: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/widget/ apps/loans/lib/widgets/layout_widgets.dart \
        apps/loans/test/features/search/search_field_test.dart
git commit -m "feat(search): app-bar search field replacing the stub"
```

---

### Task 6: Results overlay

**Files:**
- Create: `apps/loans/lib/features/search/widget/search_overlay.dart`
- Test: `apps/loans/test/features/search/search_overlay_test.dart`

**Interfaces:**
- Consumes: `SearchBloc`, `SearchState` (Task 4), `SearchResultTile` (Task 5)
- Produces: `SearchOverlay({required VoidCallback onSeeAll})`, `SearchOverlay.maxItems = 5`

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_overlay_test.dart` asserting three
behaviours, using `pumpApp` and a `MockSearchBloc` built with `bloc_test`'s
`MockBloc`:

```dart
// 1. At most maxItems tiles render even when the state holds more.
expect(find.byType(SearchResultTile), findsNWidgets(SearchOverlay.maxItems));

// 2. "See all" appears only when results exceed maxItems.
expect(find.text('See all 7 results'), findsOneWidget);

// 3. The empty state hints rather than just reporting nothing, because prefix
//    matching genuinely cannot match mid-word.
expect(find.textContaining('Try a shorter term'), findsOneWidget);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_overlay_test.dart`
Expected: FAIL — `search_overlay.dart` does not exist.

- [ ] **Step 3: Write the overlay**

Create `apps/loans/lib/features/search/widget/search_overlay.dart`. A
`BlocBuilder<SearchBloc, SearchState>` in a `Material` with elevation, rendering
per status: `tooShort` → "Keep typing — 2 characters minimum"; `loading` →
skeleton rows; `results` → up to `maxItems` `SearchResultTile`s plus a "See all N
results" row when more exist; `empty` → "No results for X. Try a shorter term, or
search by mobile number"; `error` → a retry affordance that does **not** clear
the term.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/search_overlay_test.dart`
Expected: PASS, all three.

- [ ] **Step 5: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/widget/search_overlay.dart \
        apps/loans/test/features/search/search_overlay_test.dart
git commit -m "feat(search): results overlay with hinting empty state"
```

---

### Task 7: /search screen and offer filters

**Files:**
- Create: `apps/loans/lib/features/search/screen/search_screen.dart`
- Create: `apps/loans/lib/features/search/widget/offer_filter_bar.dart`
- Modify: `apps/loans/lib/app/routing/paths.dart`
- Modify: `apps/loans/lib/app/routing/router.dart:255`
- Test: `apps/loans/test/features/search/search_screen_test.dart`

**Interfaces:**
- Consumes: `SearchBloc` (Task 4), `SearchResultTile` (Task 5), `OfferFilters` (Task 3)
- Produces: `Paths.search = '/search'`, `SearchScreen({required String initialQuery, required SearchScope initialScope, required OfferFilters initialFilters})`

- [ ] **Step 1: Add the path**

In `apps/loans/lib/app/routing/paths.dart`, after `chatRoom`:

```dart
  static const PathTemplate search = '/search';
```

- [ ] **Step 2: Write the failing test**

Create `apps/loans/test/features/search/search_screen_test.dart` asserting:

```dart
// Scope tabs render for a staff user and only the permitted ones for a borrower.
expect(find.text('Clients'), findsOneWidget);
expect(find.text('Offers'), findsOneWidget);

// Filter chips appear only on the offers scope.
expect(find.byType(OfferFilterBar), findsOneWidget);

// Removing a chip dispatches FiltersChangedEvent with that facet cleared.
await tester.tap(find.byKey(const Key('filter_chip_company_remove')));
verify(() => bloc.add(any(that: isA<FiltersChangedEvent>()))).called(1);
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_screen_test.dart`
Expected: FAIL — `search_screen.dart` does not exist.

- [ ] **Step 4: Write the filter bar**

Create `apps/loans/lib/features/search/widget/offer_filter_bar.dart`: a `Wrap` of
`FilterChip`s for company, max interest rate, and term, each with a remove
affordance keyed `filter_chip_<facet>_remove`, plus an "add facet" chip. Only the
three facets in the spec — each additional one needs its own composite index.

- [ ] **Step 5: Write the screen**

Create `apps/loans/lib/features/search/screen/search_screen.dart`: scope tabs
(only those from `SearchScopeResolver.scopesFor`), the search field, the filter
bar when the scope is offers, and the full result list of `SearchResultTile`s.

- [ ] **Step 6: Register the route**

In `apps/loans/lib/app/routing/router.dart`, add inside the `ShellRoute`'s
`routes` list after the `Paths.chat` entry at line 255:

```dart
          GoRoute(
            path: Paths.search,
            builder: (context, state) {
              final params = state.uri.queryParameters;
              return SearchScreen(
                initialQuery: params['q'] ?? '',
                initialScope: params['scope'] == 'offers'
                    ? SearchScope.offers
                    : SearchScope.clients,
                initialFilters: OfferFilters(
                  companyId: params['company'],
                  maxInterestRate: double.tryParse(params['interest'] ?? ''),
                  term: params['term'],
                ),
              );
            },
          ),
```

Reading state from query params is what makes results deep-linkable, which is
most of why the full page exists alongside the overlay.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd apps/loans && fvm flutter test test/features/search/`
Expected: PASS.

- [ ] **Step 8: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/screen/ \
        apps/loans/lib/features/search/widget/offer_filter_bar.dart \
        apps/loans/lib/app/routing/ \
        apps/loans/test/features/search/search_screen_test.dart
git commit -m "feat(search): /search screen with offer filter controls"
```

---

### Task 8: Reach the screens outside the shell

**Files:**
- Modify: `apps/loans/lib/features/users/screens/loan_client_detail.dart`
- Modify: `apps/loans/lib/app/routing/router.dart` (shortcut wrapper)
- Test: `apps/loans/test/features/search/search_shortcut_test.dart`

**Interfaces:**
- Consumes: `SearchOverlay` (Task 6), `Paths.search` (Task 7)
- Produces: `SearchShortcutWrapper({required VoidCallback onActivate, required Widget child})`

`/`, `/dashboard`, `/users`, `/payment-center`, `/chat` and `/search` sit inside the
`ShellRoute` and inherit the field through `HomeScreen` →
`AppWidgets.defaultAppBar`. `/clients/:action` and `/loans/:action` build their own
scaffolds and need the affordance added directly.

- [ ] **Step 1: Write the failing test**

Create `apps/loans/test/features/search/search_shortcut_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('Ctrl+K opens search from any route', (tester) async {
    var opened = false;
    await tester.pumpApp(
      SearchShortcutWrapper(
        onActivate: () => opened = true,
        child: const Scaffold(body: SizedBox()),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/search/search_shortcut_test.dart`
Expected: FAIL — `search_shortcut_wrapper.dart` does not exist.

- [ ] **Step 3: Write the shortcut wrapper**

Create `apps/loans/lib/features/search/widget/search_shortcut_wrapper.dart` using
`Shortcuts` + `Actions` with `SingleActivator(LogicalKeyboardKey.keyK, control:
true)` and `SingleActivator(LogicalKeyboardKey.keyK, meta: true)` so both
platforms work, invoking `onActivate`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/loans && fvm flutter test test/features/search/search_shortcut_test.dart`
Expected: PASS.

- [ ] **Step 5: Wrap the router**

In `apps/loans/lib/app/routing/router.dart`, wrap the router's builder output in
`SearchShortcutWrapper`, with `onActivate` navigating to `Paths.search`. Binding
above the router is what makes it work regardless of shell membership.

- [ ] **Step 6: Add the icon to the out-of-shell staff screens**

In `apps/loans/lib/features/users/screens/loan_client_detail.dart`, add to that
screen's own `AppBar.actions`:

```dart
IconButton(
  tooltip: 'Search',
  icon: const Icon(Icons.search_rounded),
  onPressed: () => GoRouter.of(context).go(Paths.search),
),
```

Do the same for the `/loans/:action` screen. The shortcut stays an accelerator —
every surface keeps a visible affordance, so nothing is keyboard-only.

- [ ] **Step 7: Run the full suite**

Run: `cd apps/loans && fvm flutter test`
Expected: PASS.

- [ ] **Step 8: Analyze and commit**

```bash
cd apps/loans && fvm flutter analyze
git add apps/loans/lib/features/search/widget/search_shortcut_wrapper.dart \
        apps/loans/lib/app/routing/router.dart \
        apps/loans/lib/features/users/screens/loan_client_detail.dart \
        apps/loans/test/features/search/search_shortcut_test.dart
git commit -m "feat(search): global shortcut and out-of-shell entry points"
```

---

## Done when

- [ ] `cd apps/loans && fvm flutter analyze` is clean
- [ ] `cd apps/loans && fvm flutter test` passes
- [ ] The Dart golden-vector test passes against the **same** file the Go suite asserts
- [ ] A borrower cannot resolve a clients scope — covered by test, not by UI
- [ ] Manual check on development: type a client name, a full pasted email, and a pasted phone number in all three spellings
- [ ] PR opened against `develop` (never `master`)

## Notes for the executor

- The **request-id guard in Task 4** is the easiest bug to ship here and the
  hardest to notice: without it, a slow response for a shorter prefix silently
  overwrites correct results. Do not simplify it away.
- `company_id` is injected inside `FirestoreSearchIndex` from the authenticated
  user. If you find yourself passing it down from a widget, the authorization
  boundary has been broken.
- Search returns nothing until the backend plan is merged, deployed, and the
  backfill has run. An empty result during development is far more likely to be
  a missing backfill than a bug in this code.
- If a query fails with an index-required error, the composite index from the
  backend plan's Task 6 has not been deployed or is still building.


---

# Amendment: 2026-08-26 — Frontend Plan vs. Shipped Backend

**Read this before executing any task in `docs/superpowers/plans/2026-08-24-search-frontend.md`. Where this amendment and the plan disagree, the amendment wins.**

The frontend plan was written at the same time as the backend plan, *before* the backend was implemented. The backend then went through a hard review that changed the tokenizer contract, restructured the golden-vector file, added three new limits, moved a field from the product to the company, and deliberately left one filter unindexed. The plan was never updated. Everything below is the delta.

Authorities, in order: `functions/loans/utils/search/*.go` and `testdata/golden_tokens.json` (the Go↔Dart contract) → `apps/loans/firestore.indexes.*.json` (what is queryable) → `.superpowers/sdd/2026-08-24-search-backend/progress.md` (the rulings ledger) → `docs/superpowers/specs/2026-08-24-search-design.md` (binding, but stale in two named places).

**State of the world:** backend merged; dev indexes deployed 2026-08-26 (`progress.md:675-681`, 64→70, all six READY); dev backfill complete and verified end-to-end (a clients query and an offers query both ran successfully against `loooans-dev-stg`). **Staging and production are NOT deployed and have NOT been backfilled.**

---

## BLOCKERS

### B1. The golden file was restructured — the Dart harness must dispatch on `path`

**Plan says** (Task 1 Step 1, lines 94-113): reads `golden['cases']` and runs every case through `SearchTokenizer.tokenize(input).toSet()`.

**What shipped:** `golden_tokens.json` now has `description` / `schema` / `limits` / `paths` blocks, and every case carries a `path` naming its producer. 18 cases across 4 paths: `tokenize` 11, `phone_tokens` 4, `user_tokens` 2, `product_view_tokens` 1 (`progress.md:707-709`). `golden_tokens.json:5` — *"A case with an unknown or missing path is a test failure, not a skip."* Go dispatches on it: `tokenizer_test.go:279-300` (`runGoldenCase`), `:189-195` (`inputArity`), `:250-254` (fails if any path loses its last case), `:256-273` (asserts the `limits` block against the Go constants).

Run the plan verbatim and **8 of 18 cases fail**: 6 because they are dispatched to the wrong producer (4 `phone_tokens` + 2 `user_tokens`), and 2 more from the `normalize` defect in B4 (`"Juan  Carlos"` and the `product_view_tokens` `"Fast  cash"` case). `product_view_tokens` dispatches correctly only by accident — `ProductViewTokens` *is* `Tokenize` (`entities.go:22-24`) — so it passes today while asserting nothing about the routing. Dispatch it explicitly anyway.

**Do not** "fix" this by filtering to `path == 'tokenize'`. That is exactly the hole the restructure closed (`progress.md:563-586`, Critical C1).

**Do instead** — replace the whole golden test with a path-dispatching harness. This depends on B2 (the three new producers), B3 (`canonicalPhone` loop), B4 (`normalize` collapse) and I1/I2 (the limits constants); it does not go green until all of those land.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_tokenizer.dart';

/// Mirrors the `paths` block of golden_tokens.json and `runGoldenCase`
/// in functions/loans/test/utils/search/tokenizer_test.go:279-300.
const String pathTokenize = 'tokenize';
const String pathPhoneTokens = 'phone_tokens';
const String pathUserTokens = 'user_tokens';
const String pathProductViewTokens = 'product_view_tokens';

/// tokenize is variadic and deliberately unconstrained, matching
/// tokenizer_test.go:189-195.
const Map<String, int> inputArity = <String, int>{
  pathPhoneTokens: 1,
  pathUserTokens: 5,
  pathProductViewTokens: 3,
};

List<String> runGoldenCase(String? path, List<String> input) {
  final arity = inputArity[path];
  if (arity != null && input.length != arity) {
    fail('path "$path" takes exactly $arity inputs, got ${input.length}: $input');
  }
  switch (path) {
    case pathTokenize:
      return SearchTokenizer.tokenize(input);
    case pathPhoneTokens:
      return SearchTokenizer.phoneTokens(input[0]);
    case pathUserTokens:
      return SearchTokenizer.userTokens(
          input[0], input[1], input[2], input[3], input[4]);
    case pathProductViewTokens:
      return SearchTokenizer.productViewTokens(input[0], input[1], input[2]);
    default:
      // golden_tokens.json:5 - unknown or missing path is a FAILURE, not a
      // skip. A case nothing dispatches asserts nothing while looking like
      // coverage.
      fail('unknown golden path "$path" - add it here AND to the "paths" '
          'block of golden_tokens.json in the same PR');
  }
}

void main() {
  // Relative to the package root; `flutter test` runs with cwd = apps/loans.
  final file = File(
    '../../functions/loans/utils/search/testdata/golden_tokens.json',
  );

  group('SearchTokenizer golden vectors', () {
    late Map<String, dynamic> golden;
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      expect(file.existsSync(), isTrue,
          reason: 'golden vectors missing - is the backend merged?');
      golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (golden['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);
    });

    // Dart reads these numbers instead of the Go source, so an absent or
    // changed one is silent drift. Mirrors tokenizer_test.go:256-273.
    // Per-key, not whole-map equality: Go flags missing/mismatched keys but
    // tolerates extras, and a sixth limit added later should not redden Dart
    // CI before Dart needs it.
    test('limits block matches the Dart constants', () {
      final limits =
          (golden['limits'] as Map<String, dynamic>).cast<String, int>();
      expect(limits['min_prefix'], SearchTokenizer.minPrefix);
      expect(limits['max_prefix'], SearchTokenizer.maxPrefix);
      expect(limits['max_full_value'], SearchTokenizer.maxFullValue);
      expect(limits['max_words'], SearchTokenizer.maxWords);
      expect(limits['max_tokens'], SearchTokenizer.maxTokens);
    });

    test('every case matches the producer its path names', () {
      for (final entry in cases) {
        final path = entry['path'] as String?;
        final input = (entry['input'] as List<dynamic>).cast<String>();
        final expected = (entry['tokens'] as List<dynamic>).cast<String>();
        // ORDERED list, per golden_tokens.json:7 - "deduplicated and sorted
        // ascending. Compare as an ordered list." Go uses reflect.DeepEqual
        // on the slice (tokenizer_test.go:241). See M5 for why this
        // supersedes the earlier sets ruling.
        expect(
          runGoldenCase(path, input),
          expected,
          reason: '${entry['name']}\n$path($input) drifted from Go',
        );
      }
    });

    // Coverage, not correctness: the failure this file prevents is silent, so
    // a path losing its last case must break CI. Mirrors
    // tokenizer_test.go:250-254.
    test('all four producers are still exercised', () {
      final seen = cases.map((c) => c['path'] as String?).toSet();
      expect(
        seen,
        containsAll(<String>[
          pathTokenize,
          pathPhoneTokens,
          pathUserTokens,
          pathProductViewTokens,
        ]),
      );
    });
  });
}
```

**Also amend Step 4 (line 220)** from *"Expected: PASS, all four tests including the golden vectors"* to: *"Expected: PASS — the three hand-written unit tests plus three golden-vector tests (limits block, per-case dispatch across all 18 cases, path coverage)."*

**Note on CI:** `.github/workflows/loans-app-development.yml` triggers only on `apps/loans/**` and `packages/**`. A change to `functions/loans/.../golden_tokens.json` does **not** run the Dart test. Consider adding that path to the app workflow's filters — out of scope for this plan, but worth raising.

---

### B2. `SearchTokenizer` is missing three of the four producers

**Plan says** (line 52): *"Produces: `SearchTokenizer.normalize(String) → String`, `SearchTokenizer.tokenize(List<String>) → List<String>`, `SearchTokenizer.canonicalPhone(String) → String`, `SearchTokenizer.minPrefix = 2`, `SearchTokenizer.maxPrefix = 12`"*.

**What shipped:** four producers, and `canonicalPhone` is not one of them (it is a helper, and the runtime query-side entry point at plan line 556 — **keep it**).

- `PhoneTokens` (`phone.go:41-58`) = canonical + its prefixes + the **last 4 digits as a discrete token** (`lastDigits = 4`, `phone.go:9`), sorted and capped; **nil when the canonical form is empty** (`phone.go:43-45`).
- `UserTokens` (`entities.go:11-17`) = `merge(Tokenize(firstName, middleName, lastName, email), PhoneTokens(mobile))` — the four name/email values in ONE `tokenize` call so they share one `maxWords` budget; mobile through `PhoneTokens` only.
- `ProductViewTokens` (`entities.go:22-24`) = `Tokenize(companyName, loanType, tagLine)` — one call.
- `merge` (`entities.go:29-38`) unions then **re-applies the token cap**: *"the sum of two capped groups is not itself capped."*

`golden_tokens.json:22-24` documents all three in enough detail to reimplement from the file alone.

**Do instead** — add to line 52's Produces list and to the class body (lines 136-214):

```dart
  /// Last-4 tail token length. NOT in the golden `limits` block - the value
  /// comes from the paths.phone_tokens prose (golden_tokens.json:22) and
  /// phone.go:9. Hardcode it here and nowhere else.
  static const int _lastDigits = 4;

  /// Mirrors PhoneTokens (phone.go:41-58). Never route a phone number through
  /// [tokenize]: it does none of the canonicalization.
  static List<String> phoneTokens(String raw) {
    final canonical = canonicalPhone(raw);
    // phone.go:43-45 returns nil. Omitting this guard emits a spurious ''
    // token into every mobile-less user via userTokens.
    if (canonical.isEmpty) return const <String>[];
    final tokens = <String>{canonical};
    _addPrefixes(tokens, canonical);
    if (canonical.length >= _lastDigits) {
      tokens.add(canonical.substring(canonical.length - _lastDigits));
    }
    return _sortedCapped(tokens);
  }

  /// Mirrors UserTokens (entities.go:11-17). The four name/email fields share
  /// ONE tokenize() call - and therefore one maxWords budget; mobile goes
  /// through phoneTokens. Swapping that routing is the exact drift the
  /// user_tokens golden cases pin.
  static List<String> userTokens(String firstName, String middleName,
      String lastName, String mobile, String email) {
    final merged = <String>{
      ...tokenize([firstName, middleName, lastName, email]),
      ...phoneTokens(mobile),
    };
    return _sortedCapped(merged);
  }

  /// Mirrors ProductViewTokens (entities.go:22-24). NOTE the third argument is
  /// tag_line, which is a COMPANY field, not a product field - the projection
  /// reads it via LoadCompany (product_view_projection.go:199-202, and
  /// :187-190 lists it in companyDerivedKeys).
  static List<String> productViewTokens(
          String companyName, String loanType, String tagLine) =>
      tokenize([companyName, loanType, tagLine]);

  /// entities.go:29-38 - the sum of two capped groups is not itself capped.
  static List<String> _sortedCapped(Set<String> tokens) {
    final sorted = tokens.toList()..sort();
    return sorted.length <= maxTokens ? sorted : sorted.sublist(0, maxTokens);
  }
```

**State in Task 1 why these exist**, or a later reviewer deletes them as dead code: *the Dart app never writes `search_tokens` — `SearchRequest.queryToken` builds a single query token. These three producers exist solely so the shared golden file can be asserted from Dart, which is what `golden_tokens.json:2` says the file is for.*

---

### B3. `canonicalPhone` must loop, not trim once

**Plan says** (Global Constraint line 21): *"Phone canonicalization is digits-only — strip non-digits, then a leading `63`, then a leading `0`."* Implementation (lines 196-201): two sequential `if`s.

**What shipped:** `phone.go:26-36` loops until neither prefix remains — `for { switch { case HasPrefix("63"): trim; case HasPrefix("0"): trim; default: return } }`. `golden_tokens.json:22` states the contract: *"Strips non-digits, then **repeatedly** trims a leading 63 or 0 until neither remains, then prefix-expands the canonical form and emits its last 4 digits as a discrete token. Never route a phone number through 'tokenize': it does none of that."*

Traced: `0639175550142` → plan yields `639175550142`, Go yields `9175550142`. `00639175550142` → plan yields `0639175550142`, Go yields `9175550142`. This is the exact bug Go itself shipped until `fd65833` (`progress.md:141-155`), and `golden_tokens.json:145-154` is the case added specifically to catch it (`progress.md:584-586`). The plan's own three assertions (lines 75-79) all **pass** with the buggy version, so nothing in the plan catches it.

**Runtime consequence:** `SearchRequest.queryToken` (line 556) sends the result as an `array-contains` token. `0639175550142` is in no document's token set → zero results, no error.

**Do instead** — replace lines 196-201:

```dart
  static String canonicalPhone(String raw) {
    var digits = raw.replaceAll(_nonDigit, '');
    // Loop, not two ifs. phone.go:27-36 repeats until neither prefix remains;
    // 0639... needs two passes and 00639... needs three. Terminates because
    // every branch strictly shortens the string, and '' starts with neither.
    while (true) {
      if (digits.startsWith('63')) {
        digits = digits.substring(2);
      } else if (digits.startsWith('0')) {
        digits = digits.substring(1);
      } else {
        return digits;
      }
    }
  }
```

**Amend Global Constraint line 21** to: *"Phone canonicalization is digits-only — strip non-digits, then **repeatedly** trim a leading `63` or a leading `0` until neither remains (a loop, not one pass per prefix: `0639175550142` needs two trims and `00639175550142` needs three). Check `63` before `0`, matching `functions/loans/utils/search/phone.go:27-36`; the binding wording is `golden_tokens.json:22`. The index also stores the **last 4 digits of the canonical form** as a discrete token (`phone.go:50-52`). Do **not** reimplement E.164 parsing."*

**Amend the doc comment at lines 191-192** to list all four spellings, and **extend the unit test at lines 75-79** so this has a local guard independent of the golden harness:

```dart
      expect(SearchTokenizer.canonicalPhone('0639175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('00639175550142'), '9175550142');
```

**Also amend the design spec** at `docs/superpowers/specs/2026-08-24-search-design.md:99`, which carries the same stale one-pass sentence. (`:96` already states the last-4 rule correctly and needs no change.)

*Out of scope, noted so it is not blessed: Go strips non-digits with `unicode.IsDigit` (`phone.go:20-24`), which preserves non-ASCII Nd digits; the plan's `_nonDigit = RegExp(r'[^0-9]')` strips them. No golden case pins it, no real input produces it.*

---

### B4. `normalize` must collapse internal whitespace, not just trim

**Plan says** (lines 151-161): *"/// Lowercases, folds diacritics and trims."* with `final lowered = value.toLowerCase().trim();`.

**What shipped:** `tokenizer.go:151` — `return strings.Join(strings.Fields(strings.ToLower(folded)), " ")`. The ends are trimmed **and every internal whitespace run collapses to one space**, documented as deliberate at `tokenizer.go:131-140` and asserted by `TestNormalizeCollapsesInternalWhitespace` (`tokenizer_test.go:108-124`). `golden_tokens.json:20`: *"An implementation that only trims the ends passes every single-word case here and fails the double-space cases - which is exactly why they exist."* Those cases are `golden_tokens.json:94-103` (`["Juan  Carlos"]` → full value `juan carlos`) and `:209-225` (`product_view_tokens` with `"Fast  cash"` → `fast cash`). This was ruled at `progress.md:665-669` (PR #104 B1(b)) — the code was changed rather than the comment softened.

**Consequence is not a runtime bug:** Dart never writes tokens, and `queryToken` takes `.split(RegExp(r'\s+')).first`, so a double-spaced query still produces the right token. What breaks is Task 1 Step 4 — two golden cases fail in both directions (the expected member missing, an unexpected one present), so the plan cannot be executed to a green state.

**Do instead** — replace lines 151-161. **Keep `toLowerCase()` before the fold**: `_accented` (line 148) holds only lowercase precomposed characters, so folding first leaves `Ñ`/`Á` untouched and the subsequent lowercase reintroduces the diacritic.

```dart
  /// Lowercases, folds diacritics, trims the ends, AND collapses every
  /// internal run of whitespace to a single space. Both indexing and querying
  /// apply it, so it must match [Normalize] in the Go tokenizer
  /// (functions/loans/utils/search/tokenizer.go:141-152, whose last line is
  /// `strings.Join(strings.Fields(strings.ToLower(folded)), " ")`).
  ///
  /// Collapsing, not merely trimming: on the Go side that makes "Juan  Carlos"
  /// index the same full-value token as "Juan Carlos". Dart never writes
  /// tokens, so nothing here is silently wrong at runtime - but the shared
  /// golden vectors assert the collapse from both languages. Do not "fix" a
  /// failure there by editing the golden file.
  static String normalize(String value) {
    final lowered = value.toLowerCase(); // trim() folded into the collapse
    final buffer = StringBuffer();
    for (final char in lowered.split('')) {
      final index = _accented.indexOf(char);
      buffer.write(index == -1 ? char : _plain[index]);
    }
    return buffer
        .toString()
        .split(_whitespaceRun)
        .where((p) => p.isNotEmpty)
        .join(' ');
  }
```

Add beside `_nonAlphanumeric`/`_nonDigit` (lines 146-147):

```dart
  static final RegExp _whitespaceRun = RegExp(r'\s+');
```

Add the Dart-side unit tests mirroring `tokenizer_test.go:108-124`:

```dart
    expect(SearchTokenizer.normalize('Juan  Carlos'), 'juan carlos');
    expect(SearchTokenizer.normalize('  dela   Cruz\t'), 'dela cruz');
    expect(SearchTokenizer.normalize('Acme\n\nLending'), 'acme lending');
    expect(SearchTokenizer.normalize('already fine'), 'already fine');
```

*Footnote, no action: Dart's `\s` and Go's `unicode.IsSpace` differ at the margins (U+0085 is whitespace to Go but not Dart's `\s`; U+FEFF the reverse). No golden case exercises either.*

---

### B5. `queryToken` must not truncate a pasted email to `maxPrefix`

**Plan says** (lines 559-565): `final candidate = normalized.contains('@') ? normalized : first;` then truncate to `maxPrefix`. **The plan's own test at lines 482-489 asserts `queryToken == 'juan.cruz@gmail.com'`** — 19 characters. The code returns `juan.cruz@gm`. The plan contradicts itself.

**What shipped:** `juan.cruz@gm` matches nothing, and cannot. `tokenizer.go:114-124` splits each word on non-alphanumerics via `FieldsFunc`, so `@` and `.` are consumed before prefixes are taken; the tokens for that address are the full value plus prefixes of `juancruzgmail...` and of each split part (`golden_tokens.json:156-170` pins exactly this — `juancruzgm`, `juancruzgma`, `juancruzgmai`, `gm/gma/gmai/gmail`, `co/com`, and no `juan.cruz@gm`). The full-value token is exempt from `MaxPrefix` precisely so a paste matches exactly (`tokenizer.go:78-82`, `:106`; spec `:90-93` — without it, a pasted address *"returns **nothing**"*).

**Do instead** — send a pasted value whole, capped the way the indexer caps it. Test the `@` on the **word actually being sent**, not the whole term, or a multi-word term containing an address emits a token no full-value token equals.

```dart
  /// The single token sent to Firestore. A name term is truncated to
  /// [SearchTokenizer.maxPrefix] and refined client-side. A value containing
  /// '@' is sent WHOLE, capped only at [SearchTokenizer.maxFullValue] runes:
  /// '@' and '.' are consumed by the word split before prefixes are taken
  /// (tokenizer.go:114-124), so the full-value token is the only one a paste
  /// can match. A phone-shaped term is canonicalized instead.
  String get queryToken {
    final normalized = SearchTokenizer.normalize(term);

    final digitsOnly = RegExp(r'^[0-9+\s()-]+$');
    if (digitsOnly.hasMatch(normalized) && normalized.isNotEmpty) {
      return SearchTokenizer.canonicalPhone(normalized);
    }

    // normalize() collapses internal whitespace runs (B4), so a single-space
    // split is sufficient here.
    final first = normalized.split(' ').first;

    if (first.contains('@')) return SearchTokenizer.capFullValue(first);

    return first.length > SearchTokenizer.maxPrefix
        ? first.substring(0, SearchTokenizer.maxPrefix)
        : first;
  }
```

**Keep the test at lines 482-489 unchanged** — it states the correct contract. `capFullValue` and `maxFullValue` are defined in **I1** below, which is a prerequisite.

---

### B6. `AuthenticationService.instance.company` throws for `customer` and `appAdmin` — delete `companyId` from `SearchRequest`

**Plan says** (line 799): `companyId: AuthenticationService.instance.company.id,` — evaluated unconditionally on every `QueryChangedEvent`, for every role. `SearchRequest.companyId` is `required` and non-nullable (lines 533, 543).

**What shipped:** `apps/loans/lib/services/authentication_service.dart:42-53` —

```dart
  Company get company {
    if (user.userRole.index > UserRole.customer.index) { ... return _company!; }
    throw Exception('Cannot get company for role ${user.userRole.label}');
  }
```

Enum order (`packages/core/user_repository/lib/src/model/user_role.dart:2-30`): appAdmin(0), customer(1), admin(2), loanOfficer(3), teller(4), reviewModerator(5). `0 > 1` and `1 > 1` are both false — **the getter throws for `appAdmin` AND for `customer`**. `session_loader.dart:36-40` confirms it never hydrates `_company` for those two roles. The throw lands inside the plan's own `try` (line 794) and is swallowed into `SearchStatus.error` at line 817 — so **every borrower search and every appAdmin search is a permanent, silent error state**, on the borrower's only scope.

The plan already states the right rule three times and then violates it: line 541-542 (*"Injected by the index, never by a caller"*), lines 619-620 (bold), line 1251, plus spec `:167-171` (*"It is never a caller-supplied parameter"*).

**Do instead** — remove `companyId` from `SearchRequest` entirely:

1. Delete `required this.companyId,` (line 533) and `final String companyId;` + its doc comment (lines 541-543).
2. Delete `companyId: 'company-1',` from the four Task 3 fixtures (lines 468, 477, 486, 495) — they assert only `queryToken`/`isSearchable`.
3. Delete the `companyId:` argument at line 799.
4. `FirestoreSearchIndex` resolves it internally, **branching on role first** (see B7 for the query shapes):

```dart
    final role = AuthenticationService.instance.user.userRole;
    final companyId = UserRole.companyManagedRoles.contains(role)
        ? AuthenticationService.instance.company.id
        : null;   // customer and appAdmin: no company predicate
```

`UserRole.companyManagedRoles` (`user_role.dart:36-41`) is admin/loanOfficer/teller/reviewModerator — exactly the set that satisfies `index > customer.index`. **Do not gate on `hasCompany` alone** (`authentication_service.dart:40`): it is a null check while the getter gates on role, so it can be true while `company` still throws.

5. Add Task 4 tests asserting a `customer` and an `appAdmin` query reach `index.query` and do **not** emit `SearchStatus.error`. Nothing in the plan covers the two broken roles today.

See also **B7** (the two clients query shapes) and **B12** (the bloc's auth reads make the existing Task 4 tests throw).

---

### B7. appAdmin's clients query has no branch — and the unscoped index shipped for it

**Plan says** (Task 3 Step 5, lines 617-620): one clients shape, unconditionally — *"`company_id == request.companyId`, `user_role == UserRole.customer.name`, `search_tokens arrayContains request.queryToken`."*

**What shipped:** two indexes, in all three env files. `apps/loans/firestore.indexes.dev.json:663-688` = `search_tokens CONTAINS, company_id, deleted_at, user_role, last_name ASC`; `:689-710` = the same **minus `company_id`**. The second was added deliberately as ruling I2 (`progress.md:597-601`): *"appAdmin's unscoped clients search had no usable index. Spec grants appAdmin all scopes → no company_id predicate → the shipped index cannot serve it (Firestore will not use a composite index unless every field is constrained)."* Spec `:165` grants `appAdmin` all scopes. Under the plan that index is permanently dead and appAdmin either queries with a company it does not have or crashes (B6).

**Do instead** — replace the single bullet at 617-620 with two:

- **`SearchScope.clients`, roles `teller`/`loanOfficer`/`admin`/`reviewModerator`:** `search_tokens arrayContains request.queryToken`, `company_id == <injected from AuthenticationService.instance.company.id>`, `user_role == UserRole.customer.name` — plus the `deleted_at isNull: true` and `orderBy('last_name')` that `userRepository.load()` adds for free (`user_firestore_service.dart:116`, `:142`). Served by `firestore.indexes.dev.json:663`.
- **`SearchScope.clients`, role `appAdmin`:** the same statements **minus `company_id`**. Served by the unscoped index at `firestore.indexes.dev.json:689`. appAdmin has no company; this branch must never read `AuthenticationService.company`.

Route the clients query through `userRepository.load()` with `QueryStatement`s (the `user_bloc.dart:332` pattern the plan already cites), **not** a raw `CollectionReference` — the indexes are cut to `load()`'s exact shape.

**Also amend line 1251-1253**, which reads as universal: *"`company_id` is injected inside `FirestoreSearchIndex` from the authenticated user, **for staff roles only** — appAdmin is unscoped by design (ruling I2), and customer never reaches the clients scope. Passing `company_id` down from a widget still breaks the boundary."*

---

### B8. `OfferFilters.maxInterestRate` builds an illegal query — finstack#103

**Plan says** (lines 516-517): *"v1 supports exactly these three facets; each additional one needs its own composite index"*, `final double? maxInterestRate;` (line 522); Task 3 Step 5 line 622 *"plus each non-null `OfferFilters` field"*; Task 7 builds a max-interest-rate `FilterChip` (lines 1075-1078) and parses `params['interest']` (line 1103).

**What shipped:** `packages/loans/product_view_repository/lib/src/data/database/product_view_firestore_service.dart:119-121` opens every query with `root.where('deleted_at', isNull: true).orderBy('updated_at', descending: true)` **before** the statements loop at `:131-148`, and exposes no way to change the sort. An inequality whose first `orderBy` is a different field is rejected. And **no `interest_rate` field appears in any index file, in any environment** — deliberately (`progress.md:472-476`: *"an index for a query that cannot be issued is pure write-amplification cost"*). The cross-plan defect was filed naming this exact plan line: `progress.md:495-502` — *"The frontend plan must be amended before its SearchIndex task is executed"* — as **finstack#103** (`progress.md:622`).

The four shipped `product_views` search indexes are the company × term combinations only: `(search_tokens, deleted_at, updated_at DESC)`, `(+company_id)`, `(+term)`, `(+company_id, +term)`. **Two indexed facets, not three.**

**Do instead — pick one and write it into the plan.** All three sites must change together: the class (516-527), Step 5 (:622), the filter bar (:1075-1078), the route param (:1103), and the file table (:39).

- **(a) Drop the facet from v1 (recommended).** Remove `maxInterestRate` from `OfferFilters`, the chip list, and the route parsing. Also amend the **spec** at `2026-08-24-search-design.md:134-137`, `:24` and `:189`, which name three facets — the spec is the authority the plan derives from, so this cannot be decided inside the plan alone. Record interest rate as deferred to finstack#103. The residual company+term combinations are fully served by the four shipped indexes in dev, stg and prod.
- **(b) Keep it as a Dart-side refinement.** Keep the chip, drop the Firestore predicate, apply `maxInterestRate` in the client-side refinement the plan already specifies at `:623-624`. No index, no new query path, no package PR. **Write the honest cost into the plan:** it filters only within the fetched page, so counts can under-report.
- **(c) Dedicated query path.** Add a `searchOffers` method on `ProductViewFirestoreService` (not on `FirestoreSearchIndex` — `grep -rn FirebaseFirestore apps/loans/lib` returns zero hits; the app layer never builds Firestore queries, and the `dev_`/`stg_` collection prefix lives in `BaseFirestoreService.root`), ordering by `interest_rate` first, exposed through `ProductViewRepository`. That is a `packages/loans/product_view_repository` PR landing **before** the frontend one. Then add **four** new index shapes per environment (interest rate combines with the existing facets), inequality field last, to `firestore.indexes.{dev,stg,prod}.json` — **not** `firestore.indexes.json`, which is a scratch artifact (see M8) — and deploy dev manually before executing the task. Note this changes that facet's ordering from recency to cheapest-first, making offers results inconsistent between facet states.

**Correct the comment at 516-517 either way**: v1 supports two indexed facets, company and term, in all four combinations.

---

### B9. `scopesFor` omits `reviewModerator` — the switch will not compile

**Plan says** (lines 367-377): five cases — customer, teller, loanOfficer, admin, appAdmin. Note at 419-421: *"If `UserRole` has members beyond those listed, the switch will not compile — add them to the staff branch or the customer branch deliberately."*

**What shipped:** `user_role.dart:30` declares a sixth member, `reviewModerator`. `apps/loans/pubspec.yaml:7` pins `sdk: "^3.5.0"`, so a non-exhaustive switch over an enum is a **compile-time error** (`non_exhaustive_switch_statement`) — Task 2 Step 5 and Step 6 both fail on the plan's own code. Neither the spec's role table (`:161-166`) nor the ledger rules on what scopes a review moderator gets.

**The ruling to write down:** grant it the staff branch. `apps/loans/lib/features/main/screen/main_screen.dart:338` already renders `LoanClientsScreen` gated on `!isCustomer()` and nothing else, with no route guard in `router.dart` — a reviewModerator can already browse client records today. Denying clients scope in search would make search stricter than the screen it searches, which is an inconsistency, not a security improvement. (`loan_clients_screen.dart:253` excludes reviewModerator from the *Add loan* button, but that gates a write and groups it with `teller`, which the plan grants full clients scope — it does not settle the read question.)

```dart
    case UserRole.teller:
    case UserRole.loanOfficer:
    case UserRole.admin:
    case UserRole.appAdmin:
    case UserRole.reviewModerator:  // matches main_screen.dart:338, which shows
      // LoanClientsScreen to every non-customer. Search must not be stricter
      // than the screen it searches.
      return {SearchScope.clients, SearchScope.offers};
```

If the intended product decision is in fact to deny reviewModerator client access, that is a change to `main_screen.dart:338` as well and belongs in its own task — do not smuggle it in as a search-scope default.

**Fix the test at lines 267-275 durably**, not by appending one name — it already omits `appAdmin`, which the switch *does* handle:

```dart
    for (final role in UserRole.values.where((r) => r != UserRole.customer)) {
      expect(SearchScopeResolver.scopesFor(role),
          {SearchScope.clients, SearchScope.offers});
    }
```

**Replace the note at 419-421** with a criterion: *"A new `UserRole` must be added to this switch explicitly. Default to the customer branch — clients scope is client-PII access and is granted deliberately, with a test naming the role. Before granting it, confirm the role already reaches `LoanClientsScreen` (`main_screen.dart:338` gates on `!isCustomer()`); search must be neither broader nor narrower than that screen."*

**Also amend the spec's role table** (`2026-08-24-search-design.md:161-166`) to carry the sixth role.

---

### B10. `SearchResultItem` cannot carry an offer row, and `item.id` is undefined for offers

**Plan says:** `class SearchResultItem { final String id; final String title; final String subtitle; final String matchedField; }` (lines 571-586); the tile is *"a `ListTile` with a `CircleAvatar` of initials … `item.title` as the title and `item.subtitle` as the subtitle"* (lines 925-929); Task 3 Step 5's only mapping rule is client-shaped — *"`subtitle` to the email when the email matched, otherwise the mobile number"* (lines 625-626). A grep of all 1258 lines for `loan_type|interest_rate|review_rating|review_count|max_loanable|ProductView|product_view|tag_line` returns **nothing**. The offers row has no data mapping, no source collection, and no tile layout anywhere in the plan.

**What shipped:** spec `:210-214` requires offer rows to show `loan_type`, `company_name`, `interest_rate`, `max_loanable_amount`, `term`, `review_rating_avg`, `review_count`. All seven are on the document: `product_view_projection.go:206` (`company_name`), `:208` (`loan_type`), `:209` (`term` — a **String**), `:213-214` (`interest_rate`, `max_loanable_amount` as float64), `:145-151` (`review_count` int64, `review_rating_avg` float64). The entity carries all of them plus `tagLine` and `companyProfilePhotoUrl` (`product_view_entity.dart:61-62, 64-65, 67-71, 76-77, 79, 82, 85, 95, 98`), and `ProductViewRepository.load()` already hands back fully populated models.

Separately, **`item.id` has no defined meaning**, and the natural reading is wrong for offers. `ProductViewEntity.id` is the document id (`product_view_projection.go:126-127`; `product_view_firestore_service.dart:24, 34, 55` address `root.doc(data.id)`), but only trigger-*created* views are keyed on the product id (`:96`). The projection's header (`:48-59`) records that *"Legacy documents were created with auto-generated IDs carrying product_id as a field"* and that lookup is by the `product_id` FIELD so those ids are never rewritten — and `BuildProductViewUpdate` (`:162-179`) never writes `id`, so the backfill did not repair them either. Per `progress.md:277-278` essentially all pre-existing offers are legacy. Every consumer selects by `productView.productId`: `loan_offers_widget.dart:404-407`, `choose_loan_section.dart:100`, `product_bloc.dart:80-92`. A view-doc id addresses a nonexistent `products/{autoId}`; `product_firestore_service.dart:39-45` does `doc.data()!`, the throw is caught at `product_bloc.dart:772-776`, and the user gets `ProductState.error('Canot select product: …')`.

**Do instead:**

1. **Make the item a sum type.** Both repositories are already app deps (`apps/loans/pubspec.yaml:74-75, 89-90`):

```dart
sealed class SearchResultItem {
  const SearchResultItem({required this.matchedField});
  final String matchedField;
}

class ClientResultItem extends SearchResultItem {
  const ClientResultItem({required this.user, required super.matchedField});
  final User user;
}

class OfferResultItem extends SearchResultItem {
  const OfferResultItem({required this.productView, required super.matchedField});
  final ProductView productView;
}
```

2. **State per-scope id semantics in Task 3 Step 5.** Clients: the `users` document id (`== user.id`). Offers: **`product_id` from the view's field, never the `product_views` document id** — cite `product_view_projection.go:48-59` and `:126-127` for why.

3. **Name the source collection for offers** — `product_views`. The enum's `offers('products')` (line 335) is the *typed prefix keyword a user types*, not a collection name; reading `products` finds no `search_tokens` at all.

4. **Specify the offers mapping and layout.** Title = `loan_type` (`product_views` has no product-name field; spec `:60-63`). Subtitle = `company_name`. Trailing metadata = `interest_rate`, `max_loanable_amount`, `term`, `review_rating_avg`, `review_count`. Field-type notes so formatting code casts correctly: **`term` is a `String`**, not a number (the numeric period is `max_period`, not on the display list). **`review_rating_avg` is `0.0` whenever `review_count` is `0`** (`product_view_projection.go:145-151` seeds zeroes rather than dividing by zero) — render "no reviews yet", not an honest-looking zero-star rating. Leading widget: the offer row should use `companyProfilePhotoUrl` (`product_view_projection.go:243`; `ImageUrl?` at `product_view_entity.dart:67-71`) with a company-initials fallback, following the shipped pattern at `loan_offer_item.dart:146-165` and `String.initials(limit: 2)` (`extensions.dart:224-238`) — **not** `User.initials`, and **not** `ImageUrl.url` unguarded (`image_url.dart:27-37` throws when both `thumbnail` and `original` are null; every shipped call site null-checks first).

5. **`tag_line` is a token source, not a display field.** Offer tokens come from exactly `company_name`, `loan_type`, `tag_line` (`entities.go:22-24`; spec `:60`), and `tag_line` is a **COMPANY** field (`product_view_projection.go:199-202`, `:187-192`), nullable, written as an explicit `nil` when the company has none (`:238-242`; `String? tagLine` at `product_view_entity.dart:64-65`). Refine offer candidates against **all three**, let `matchedField` be any of the three, and decide what a tag-line-only match shows (surface the tag line as subtitle, or exclude tag_line from refinement) — otherwise that row cannot explain itself, which is the failure spec `:210-212` exists to prevent.

6. **Define the tap destination — the plan defines none for either scope.** `ProductBloc` is a global provider (`bloc_providers.dart:38`), so `context.read` is safe anywhere, but `ProductState.selected` is only rendered by `loan_offers_widget.dart:79`/`:149`. Tapping an offer from the overlay on `/payment-center` would select a product with nothing mounted to show it. Specify: **navigate to the offers surface first, then `selectProduct(item.productView.productId, productView: item.productView)`**. Do the same for clients (presumably `loan_client_detail`, which Task 8 already touches at `:1135`).

7. **Restate the invalidated blocks**: the `const SearchResultItem` fixtures at lines 699-715 and 881-905, and the Interfaces lines at 861-862, 978, 1040.

---

### B11. The `/search` deep link mints a scope outside the resolver — and `initialScope` is dead

**Plan says** (lines 1092-1108): `initialScope: params['scope'] == 'offers' ? SearchScope.offers : SearchScope.clients,`; Interfaces at 1041.

**Two problems.** First, this is the one place a scope is chosen without `SearchScopeResolver`, contradicting spec Decision 3 (`:41`) and the plan's own claim at 257-259; `router.dart:51-100` has no role gate (grep for `role`/`UserRole` over all 383 lines: zero hits). Second — and this is what actually breaks — **`initialScope` has no consumer**. It appears only at 1041 and 1098-1100. `SearchBloc` exposes only `QueryChangedEvent` and `FiltersChangedEvent` (line 651); there is no `ScopeChangedEvent`, and `_onQueryChanged` re-resolves the scope through `SearchScopeResolver.resolve` on **every** event (lines 769-774, 796-798). So a deep link's scope silently never applies, and the scope **tabs** at 1082-1084 have no dispatch path either — tapping "Offers" changes nothing. That breaks the plan's own justification at 1111-1112 (*"Reading state from query params is what makes results deep-linkable"*).

*(No privilege escalation follows: for a customer `scopesFor` returns `{offers}` and `_defaultScope` returns offers for `/search`; the index injects the company predicate; and B6's crash fires first. But a `SearchScope.clients` handed to a screen whose tabs render only `{offers}` is a selected-value-outside-the-option-set — a plausible first-frame assertion for every borrower.)*

**Do instead:**

1. Add `ScopeChangedEvent(SearchScope scope)` to the event list (line 651) and a `SearchScope? _pinnedScope` on the bloc. In `_onQueryChanged`, keep `SearchScopeResolver.resolve` as the source of truth but honour the pin **only** when `SearchScopeResolver.scopesFor(role).contains(_pinnedScope)` — the same permitted-set intersection the resolver applies to a typed prefix (lines 390-392). An impermissible pin is dropped, not honoured.
2. Change the router (1092-1108) to pass `String? initialScopeParam = params['scope']` — a raw hint, never a `SearchScope`. Update Interfaces line 1041 to `SearchScreen({required String initialQuery, String? initialScopeParam, required OfferFilters initialFilters})`.
3. `SearchScreen` maps that String through `SearchScope.values.firstWhereOrNull((s) => s.prefix == param)` and dispatches `ScopeChangedEvent` only when non-null. **Note the vocabulary mismatch:** `SearchScope.offers.prefix` is `'products'` (line 334) while the deep link tests `'offers'`. Pick one canonical spelling and use it in both places, or `?scope=offers` silently means clients.
4. This also gives the Task 7 Step 5 tabs their missing dispatch.
5. Tests to add at Task 7 Step 2 — assert real behaviour: *a customer opening `/search?scope=clients` issues an offers query* **and** *a staff user opening `/search?scope=offers` issues an offers query* (the second fails on the plan as written and is the one that catches the live bug).

*Cheaper alternative if scope pinning is out of v1 scope: delete `initialScope` from 1041 and the ternary from 1098-1100 entirely, drop the scope tabs from 1082-1084, and note that `/search` scope follows role and route only. Do not leave a constructor parameter no code reads.*

---

### B12. The bloc reads `AuthenticationService.instance` inside the handler — both Task 4 tests throw

**Plan says** (line 769, the first statement of `_onQueryChanged`, **outside** the `try` at 794): `final role = AuthenticationService.instance.user.userRole;`. The tests at 676-732 build `SearchBloc(searchIndex: index)` with no authentication setup at all.

**What shipped:** `authentication_service.dart:16-22` — `User get user { if (_user == null) { throw Exception('Please login'); } return _user!; }`, and `:96-100` lazily constructs an empty service, so a fresh `flutter test` isolate always has `_user == null`. bloc 8.1.4 rethrows from the handler (`bloc.dart:229-233`) without awaiting (`:238`), and bloc_test 9.1.7 rethrows because neither test declares `errors:` (`bloc_test.dart:243-245`). **Both tests abort with `Exception: Please login` before `expect` is evaluated.** Task 4 Step 4's "Expected: PASS, both tests" and Done-when line 1240 are unreachable.

This also violates `apps/loans/CLAUDE.md:30` — *"Must Never … Use `AuthenticationService.instance` directly in BLoCs — use the injected `authService` field instead."* The tempting one-line repair (seed the singleton in `setUp`, as `chat_room_screen_test.dart:23` does) turns the tests green while shipping a rule-violating bloc.

**Do instead** — follow the repo's own template, `ReviewsBloc` (`reviews_bloc.dart:18-37`; same shape in `bank_details_bloc.dart:15,29` and `payment_submission_bloc.dart:24,41`):

```dart
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(BuildContext context)
      : this.withDependencies(
          searchIndex: context.read<SearchIndex>(),
          authService: AuthenticationService.instance,
        );

  SearchBloc.withDependencies({
    required SearchIndex searchIndex,
    required AuthenticationService authService,
  })  : _searchIndex = searchIndex,
        authService = authService,
        super(const SearchState()) { ... }

  final AuthenticationService authService;
```

Then line 769 becomes `final role = authService.user.userRole;` — still read **per event**, so it only throws post-login where a search is possible.

**Do NOT** hoist the identity into the constructor or read it at the DI registration site. `AppBlocProviders` is mounted at `app/view/app.dart:17`, wrapping `MaterialApp.router` — above the login route — so a non-lazy read throws `Please login` at app start, and a lazy one freezes role/company across logout/login (`authentication_service.dart:101-104` nulls `_user`/`_company` on a bloc that outlives it).

Update both blocTests to `SearchBloc.withDependencies(searchIndex: index, authService: auth)` with `class _MockAuth extends Mock implements AuthenticationService {}` and a stubbed `user`, matching `reviews_bloc_test.dart:13-14` and `payment_submission_bloc_test.dart:21`. **Amend the Step 3 prose at 748-750** (*"write it as given"*) — as given it breaks `CLAUDE.md:30`.

---

## IMPORTANT

### I1. Add `maxFullValue = 256` — the full value is exempt from `maxPrefix`, not unbounded

**Plan says** (line 171): `// The whole value, uncapped - this is what makes a pasted email or phone number match.` then `tokens.add(normalized);`. Global Constraint line 20: *"full value exempt from the cap."*

**What shipped:** `tokenizer.go:106` stores `capFullValue(normalized)`, truncated to `MaxFullValue = 256` **runes** (`:34`, `:180-186`). `tokenizer.go:100-101` says it outright: *"Exempt from MaxPrefix is not the same as unbounded: MaxFullValue keeps it writable."* Reason at `:29-38`: `search_tokens` is auto single-field indexed, an oversized index entry makes Firestore reject the whole write. `golden_tokens.json:14` publishes `max_full_value: 256`; `:19` — *"exempt from max_prefix, truncated only past max_full_value runes."* Go pins truncation-not-omission with multi-byte input at `tokenizer_test.go:75-102`.

**Do instead:**

```dart
  /// Longest full-value token. Not a prefix bound: the full value is exempt
  /// from [maxPrefix], but not unbounded. Go truncates it at
  /// tokenizer.go:180, so a mirror that does not truncate emits a different
  /// token for any value past this length.
  static const int maxFullValue = 256;

  /// Runes, not UTF-16 code units - tokenizer.go:178-179: "Runes, not bytes,
  /// so the cap means the same thing in Dart." Never use substring here.
  static String capFullValue(String normalized) {
    final runes = normalized.runes.toList();
    if (runes.length <= maxFullValue) return normalized;
    return String.fromCharCodes(runes.take(maxFullValue));
  }
```

and in `tokenize`, replace line 173:

```dart
      // The whole value - exempt from maxPrefix, which is what makes a pasted
      // email or phone number match. Exempt is not unbounded: Go truncates at
      // maxFullValue RUNES (tokenizer.go:180). Truncated, never dropped: a
      // truncated token still matches a query truncated the same way; a
      // dropped one turns a paste into a silent miss.
      tokens.add(capFullValue(normalized));
```

Add `maxFullValue` to the Produces line (52). Add a Dart mirror of `TestTokenize_FullValueTokenIsCapped` (`tokenizer_test.go:75-102`), keeping all three of its assertions with a multi-byte input such as `'añ' * maxFullValue`: no emitted token exceeds `maxFullValue` runes; the value truncated to exactly `maxFullValue` runes **is present**; a value of exactly `maxFullValue` runes is returned untouched. **No golden case exercises this** — the longest input in the file is 25 runes — so without that test the cap is unpinned.

### I2. Add `maxWords = 64` and `maxTokens = 2000`, and implement them

**Plan says:** neither constant appears anywhere in 1258 lines. The word loop (175-186) has no budget; the return (line 188) is `tokens.toList()..sort()` with no count cap.

**What shipped** (both added after the plan was written — `progress.md:711-713`):

- **`MaxWords = 64`** (`tokenizer.go:57`): only the first 64 whitespace-separated words of a **composition** are prefix-expanded, counted across all values in order — `budget := MaxWords` is declared **outside** the values loop (`:90`) and consumed at `:108-112`. Every non-empty value still contributes its full-value token regardless of budget (`:106`).
- **`MaxTokens = 2000`** (`tokenizer.go:72`): the **sorted** set is truncated to its first 2000 entries (`capCount`, `:168-173`), and `merge` re-applies it after unioning (`entities.go:29-38`).

`golden_tokens.json:15-16` publishes both; `:21` states the rule in one sentence. **No golden case exercises either cap** — the largest case is three words, the widest composition spends 5 of 64 — so Go covers them with dedicated tests instead: `tokenizer_test.go:132-155` (`TestTokenize_WordCountIsCapped`) and `:160-178` (`TestTokenize_TokenCountIsCappedForOneLongWord`).

**Do instead** — add both constants (and to the Produces line), then implement:

```dart
  /// Words one composition prefix-expands, counted across its values in
  /// order. Full-value tokens are exempt. tokenizer.go:57, :90, :108-112.
  static const int maxWords = 64;

  /// Hard ceiling on the emitted array; the sorted set is truncated to it.
  /// tokenizer.go:72, :168-173.
  static const int maxTokens = 2000;
```

In `tokenize`: declare `var budget = maxWords;` **outside** the values loop; inside the word loop `break` when it hits 0 and decrement per word — keeping `if (word.isEmpty) continue;` **before** the decrement (Go's `strings.Fields` never yields an empty word; Dart's `split(RegExp(r'\s+'))` can, and decrementing first would shift the boundary on padded input). Return `_sortedCapped(tokens)` (defined in B2) rather than `tokens.toList()..sort()`.

Add the two unit tests the golden file cannot express, mirroring `tokenizer_test.go:132-178`: 800 words `"w0001"…` → `"w0064"` expanded and `"w0065"` not, total ≤ 2000; and one pathological hyphenated word → exactly 2000 tokens.

**Rewrite Global Constraint line 20** to: *"Bounds must match the backend exactly and come from the `limits` block of the golden vector file, which is the contract: `min_prefix` 2, `max_prefix` 12, `max_full_value` 256, `max_words` 64, `max_tokens` 2000. The full value is exempt from `max_prefix` only — it is still truncated at `max_full_value` runes. The Dart constants are `static const` and the golden test asserts them against the `limits` block."*

*Note: `_addPrefixes` (lines 203-213) also slices by UTF-16 code units where Go slices runes (`tokenizer.go:189-203`); see M3/M4 for the full rune audit.*

### I3. Last-4 phone search: `0142` canonicalizes to `142` and matches nothing

**Plan says** (lines 551-557): any term matching `^[0-9+\s()-]+$` goes through `canonicalPhone`.

**What shipped:** `PhoneTokens` emits the last 4 digits of the **canonical** form as a discrete token (`phone.go:9`, `:50-52`), exactly because *"staff often have only the tail, and prefix expansion cannot match a suffix"* (spec `:95-97`). For `09175550142` the indexed tail token is `0142` (`golden_tokens.json:116-125`). But `canonicalPhone('0142')` strips the leading zero → `142`, which is in no token set and cannot be — every prefix token is a prefix of `9175550142`. Silent zero results for the exact workflow the tail token exists for. Same for a tail starting `63`. (`progress.md:156-158` accepted last-4 collisions on the assumption that *"the Dart query path refines client-side against the full term"* — it does not reach the token at all.)

**Do not** "fix" this by sending short digit strings verbatim: `0917` is both a plausible tail and the first four characters of essentially every PH mobile number. Sending it verbatim fixes the tail and breaks the prefix (`0917` → currently `917`, a real indexed prefix).

**Do instead** — emit both candidates and query with `arrayContainsAny`:

- Change `String get queryToken` to `List<String> get queryTokens`. In the digits branch compute `digits = normalized.replaceAll(RegExp(r'[^0-9]'), '')` and `canonical = SearchTokenizer.canonicalPhone(normalized)`; return `{canonical, if (digits.length == SearchTokenizer.lastDigits) digits}.where((t) => t.isNotEmpty).toList()`. **Guard the empty canonical**: `6300` canonicalizes to `''` — never send `''`; fall back to a single-value list. The non-digit branch returns a single-element list unchanged.
- Change Task 3 Step 5's `search_tokens arrayContains request.queryToken` to `arrayContainsAny request.queryTokens`, and update the bloc/index test doubles.
- **No new index is required** — every `search_tokens` entry is `"arrayConfig": "CONTAINS"` (`firestore.indexes.dev.json:668-669` and siblings), which serves `array-contains-any`; two values is far under the 30-value cap. `QueryStatement.arrayContainsAny` is already forwarded by both services (`user_firestore_service.dart:127-128, 182-183`; `product_view_firestore_service.dart:137, 184`). **State this in the plan so nobody adds an index.**
- Expose `SearchTokenizer.lastDigits = 4` on the Produces line (52) and note that the last-4 token is the **only** suffix-reachable token — a 5- or 6-digit tail is not indexed and legitimately returns nothing.

Tests at 473-480: `'0142'` → tokens include `'0142'` **and** `'142'`; `'0917'` → includes `'917'` (prefix path not regressed); `'1420'` → single value (digits == canonical); `'0917 555 0142'` and `'9175550142'` → single `'9175550142'` (the existing assertion stays green).

### I4. `isSearchable` measures the raw term, not the token that is sent

**Plan says** (lines 567-568): `bool get isSearchable => SearchTokenizer.normalize(term).length >= SearchTokenizer.minPrefix;`

**What shipped:** the phone branch strips a leading `63`/`0`, so the value actually sent can be shorter than the value measured. `'63'` and `'+63'` normalize to ≥ 2 characters, pass the gate, and issue `array-contains ''` — a legal query that can never match (`Tokenize` skips empty values at `tokenizer.go:94-96`; `PhoneTokens` returns nil on empty canonical at `phone.go:43-45`). The digits regex also admits punctuation-only terms: `'()'`, `'--'`, `'++'`, `'(0)'` all canonicalize to `''`. `'09'` → `'9'`, a 1-character token no real number's prefix expansion emits (`PhoneTokens` expands from `minPrefix`). The UI then shows `empty` ("No results for X") instead of `tooShort`.

Note: **`isSearchable` is dead code as the plan stands** — the bloc duplicates the predicate inline at 776-777 and never calls it. Fixing 567-568 alone changes nothing.

**Do instead:**

1. Line 567-568 → `bool get isSearchable => queryToken.isNotEmpty && SearchTokenizer.normalize(term).length >= SearchTokenizer.minPrefix;` (with I3 applied, `queryTokens.isNotEmpty`). Keep the term-length half — the spec's rule is on the query (`:198-199`, `:232`), and `_addPrefixes` legitimately emits sub-`minPrefix` tokens whole (`tokenizer.go:193-196`), so a strict `token.length >= minPrefix` would wrongly reject `'+639'` and `'a bcd'`.
2. Replace the bloc's inline check at 776-777: build the `SearchRequest` first (after B6, it takes no `companyId`), then gate on `request.isSearchable`. One definition, measured on the value actually sent.
3. Require `FirestoreSearchIndex.query` to `return SearchResults.empty` when `!request.isSearchable`, so the invariant lives at the send site.
4. Tests beside 491-498: `'63'`, `'+63'`, `'09'`, `'()'` → false; `'091'` → true. Plus a Task 4 test mirroring the `'d'` test at 676-685: term `'63'` emits `tooShort` and `verifyNever(() => index.query(any()))`.
5. Line 1008's copy ("Keep typing — 2 characters minimum") is wrong for a user who typed the three characters `'+63'`. Generalise to "Keep typing".

### I5. Client-side refinement drops correct phone matches

**Plan says** (lines 623-624): *"Refine the returned candidates in Dart against the **full** `request.term`, because the query token was truncated."*

**Two things are wrong for the phone path.** (1) The phone branch returns before the `maxPrefix` truncation (lines 551-557), so the stated reason does not apply — and that early return is **correct**: `PhoneTokens` seeds the set with the full canonical uncapped by `MaxPrefix` (`phone.go:44-46`). (2) The stored `mobile_number` is raw — `user_changes.go:116-121` passes `str("mobile_number")` into `search.UserTokens` and never rewrites the field (`:64-75` touch only verification flags). Refining a term against it with any contains/startsWith test drops correct matches.

App-written docs hold a bare 10-digit string: every mobile input uses `FilteringTextInputFormatter.digitsOnly` + `maxLength(10)` with a decorative `+63` prefix (`register_screen_form_users_widget.dart:179-198`, `borrower_details_section.dart:108-128`, and the two update_profile widgets). The variation is on the **query** side.

**Do instead** — replace 623-624 with:

> Refine name and email candidates in Dart against the full `request.term`, because those query tokens were truncated to `maxPrefix`. Do **NOT** apply that refinement to a phone-shaped term — the phone token is never truncated, and the raw term's spelling will not match the raw `mobile_number` stored on the document. Refine a phone-shaped term by comparing `SearchTokenizer.canonicalPhone(term)` against `SearchTokenizer.canonicalPhone(doc.mobile_number)` as a prefix match; when the term's digit run is exactly 4 digits, compare that **raw digit run** against the last 4 characters of `canonicalPhone(doc.mobile_number)` instead — do not canonicalize a 4-digit tail, since `canonicalPhone('0142')` is `'142'`.

Test: stored `mobile_number: '9175550142'`; terms `+63 917 555 0142`, `0917 555 0142`, `09175550142` must all survive refinement. This clause depends on B3 (the loop) being applied first.

Also amend Task 3 Step 5's `matchedField` rule (625-626), which is client-only: scope it to clients, and add the offers rule from B10 §5.

### I6. Diacritic folding is a 25-character table where Go strips every combining mark

**Plan says** (lines 148-149, 153-161): a fixed `_accented`/`_plain` lookup over `lowered.split('')`.

**What shipped:** `tokenizer.go:141-152` folds generically — NFD → `runes.Remove(runes.In(unicode.Mn))` → NFC → lower → collapse. Measured against the plan's Dart:

| input | Go | plan's Dart |
|---|---|---|
| `"Peña"` NFC | `pena` | `pena` ✓ |
| `"Peña"` NFD (`n` + U+0303) | `pena` | `peña` ✗ |
| `"Māori"` | `maori` | `māori` ✗ |
| `"Nguyễn"` | `nguyen` | `nguyễn` ✗ |
| `"Erdős"` / `"Ștefan"` | `erdos` / `stefan` | unchanged ✗ |
| `"Straße"` / `"Søren"` | `straße` / `søren` | same ✓ (Go does **not** fold ß or ø — no canonical decomposition) |

The failure path is `SearchQuery.queryToken` (line 552), which returns the unfolded string verbatim → a token no index contains → zero results, no error. `golden_tokens.json:42` is the file's **only** non-ASCII input and it is precomposed U+00F1, the one case the table covers, so the contract test structurally cannot catch this.

**Do instead:**

1. Fold marks with the full Mn class — `apps/loans/pubspec.yaml:7` pins `^3.5.0`, so unicode property escapes are available:

```dart
  /// Go folds via NFD -> strip every Unicode Mn -> NFC (tokenizer.go:141-152).
  /// Dart has no NFD in core, so this strips marks that are ALREADY
  /// decomposed; the table below handles precomposed ones. \p{Mn} - not the
  /// U+0300-U+036F block - because Go strips the whole category.
  static final RegExp _combiningMark = RegExp(r'\p{Mn}', unicode: true);
```

applied inside `normalize` after `toLowerCase()` and before the table lookup (order per B4).

2. **Decide the precomposed set deliberately and write the decision into the plan.** Mn-stripping alone does not fix `ā ő ș ễ` — those are single precomposed code points and Dart has no NFD. Either (a) extend `_accented`/`_plain` to cover Latin Extended-A/B and the Vietnamese Latin Extended Additional block, or (b) add a package (`unorm_dart`), naming it in Task 1's dependency list. If you add a general ASCII-folding package, **verify it against the table above first**: `diacritic`-style tables map ø→o and ß→ss, which Go does not, creating divergence in the opposite direction. Do not ship "document the gap and move on" — `Nguyễn` is an ordinary PH-market surname and is currently unfindable.

3. Dart-only tests, with the decomposed literal written as an **explicit escape** so the file's encoding cannot silently precompose it:

```dart
    expect(SearchTokenizer.normalize('Pe\u00F1a'), 'pena');      // precomposed
    expect(SearchTokenizer.normalize('Pen\u0303a'), 'pena');     // decomposed
    expect(SearchTokenizer.normalize('Nguy\u1EC5n'), 'nguyen');
    expect(SearchTokenizer.normalize('Stra\u00DFe'), 'straße');  // Go does NOT fold ß
```

4. Amend the contract: `golden_tokens.json:2` claims the file is *"sufficient on its own"* but `:20` says only "folds diacritics". Add one sentence to `tokenize.normalization` stating the rule as *"NFD, remove every Unicode Mn, NFC — so ñ→n and ā→a, but ø and ß are unchanged"*, plus a decomposed golden case.

### I7. The non-alphanumeric split is ASCII-only in Dart, Unicode-aware in Go

**Plan says** (line 146): `static final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');`, used at 177-178.

**What shipped:** `tokenizer.go:114-116` splits on `!unicode.IsLetter(r) && !unicode.IsDigit(r)`. Measured, running shipped Go against a Dart transcription of the plan:

| input | Go | plan |
|---|---|---|
| `Straße` | `[st str stra straß straße]` | `[e st str stra strae straße]` |
| `Łukasz` | `[łu łuk łuka łukasz …]` | `[uk uka ukas ukasz łukasz]` |
| `山田太郎` | `[山田 山田太 山田太郎]` | `[山田太郎]` (parts empty — **no** prefix tokens) |
| `Иванов` | `[ив ива иван ивано иванов]` | `[иванов]` |

The affected class is exactly the letters NFD+Mn-removal does not reduce to ASCII (ß æ œ ø đ ł þ ð ı) plus every non-Latin script. No golden case covers it.

**Do instead** — three parts, all required together:

1. `static final RegExp _nonAlphanumeric = RegExp(r'[^\p{L}\p{Nd}]+', unicode: true);` — **`\p{Nd}`, not `\p{N}`**: `\p{N}` is Nd+Nl+No while Go's `unicode.IsDigit` is Nd only (`unicode.IsDigit('½') == false`). With `\p{N}`, `"2½ rate"` emits `2½` where Go emits `2`; with `\p{Nd}` the two agree exactly.
2. **`unicode: true` is mandatory, not decorative.** Without the flag Dart does not throw — it parses `\p{L}` as a literal class and `'ab'.split(...)` returns `['', '']`, i.e. silent total breakage. State this in the plan.
3. Make `_addPrefixes` **rune-based** in the same edit. Go slices `[]rune` (`tokenizer.go:189, 197-202`); the plan slices UTF-16 code units. Today the ASCII regex strips non-BMP characters before they reach it, masking the bug; fixing only the regex unmasks it (`"a𝒜bc"` → the plan emits `a\uD835`, an unpaired high surrogate Go can never produce).

```dart
  static void _addPrefixes(Set<String> tokens, String token) {
    final runes = token.runes.toList();
    if (runes.isEmpty) return;
    // tokenizer.go:193-196 - a whole token shorter than minPrefix is indexed
    // verbatim (a middle initial, say), not dropped.
    if (runes.length < minPrefix) { tokens.add(token); return; }
    final limit = runes.length < maxPrefix ? runes.length : maxPrefix;
    for (var i = minPrefix; i <= limit; i++) {
      tokens.add(String.fromCharCodes(runes.take(i)));
    }
  }
```

The same code-unit/rune mismatch is on the **runtime** path at `queryToken`'s `candidate.substring(0, maxPrefix)` (562-563) and `isSearchable`'s `.length` (568, 777) — convert those too.

4. Add golden coverage in the same PR (Go is the reference): one non-foldable Latin letter (`Straße`), one non-Latin word (`Иванов`), one non-Nd numeric (`2½ rate`) to pin `\p{Nd}` over `\p{N}`. Note in the plan that this split rule is deliberately Unicode.

### I8. `load()` carries a pagination cursor across calls — every search must pass `reset: true`

**Plan says** (lines 615-616): *"Build a `QueryStatement` list per scope, following the pattern in `apps/loans/lib/features/users/bloc/user_bloc.dart:332`."* The plan never mentions `reset`, `load()`, or the cursor. Grep for `reset` across all 1258 lines: zero hits.

**What shipped:** `BaseFirestoreService` holds `lastDocumentSnapshot` on the instance (`base_firestore_service.dart:21`). `UserFirestoreService.load()` clears it only when `reset: true` (`:111-113`), applies `startAfterDocument` otherwise (`:144-146`), and writes `lastDocumentSnapshot = data.docs.first` after **every** call (`:156`). `ProductViewFirestoreService.load()` is identical (`:115-117`, `:123-125`, `:154`). `reset` defaults to **false**. And the repositories are app-lifetime singletons (`repository_providers.dart:33, 36`), each holding one service — so the cursor is shared with `UserBloc`, the Payment Center picker, and every other `load()` caller.

**The mechanism is worse than "pages past its own results."** `startAfterDocument` positions by the trailing `orderBy` value, and the cursor is written from `docs.first`, not `.last`. So the *next* search — different token, different result set — silently excludes every matching document sorting at or before the previous search's first hit. Search "dela" → cursor lands on "Dela Cruz"; search "abad" → Abad is filtered out and the user sees an empty result for a client that exists. No exception, no log.

**Do instead** — amend the bullet at 615-616 to:

> Build a `QueryStatement` list per scope and issue it through the shared repository `load()` — `UserRepository.load()` for clients, `ProductViewRepository.load()` for offers — following the pattern in `apps/loans/lib/features/users/bloc/user_bloc.dart:332-346`. Inject both repositories into `FirestoreSearchIndex`; do **not** build raw `FirebaseFirestore` queries — `grep -rn FirebaseFirestore apps/loans/lib` returns zero hits, the `dev_`/`stg_` collection prefix lives in `BaseFirestoreService.root`, and the shipped composite indexes are cut to `load()`'s exact query shape (`deleted_at` + trailing `last_name` / `updated_at DESC`).
>
> **Every call must pass `reset: true`, and `limit: <candidateLimit>`.** `reset` defaults to `false`, `load()` writes `lastDocumentSnapshot = data.docs.first` after every call (`user_firestore_service.dart:156`, `product_view_firestore_service.dart:154`) and applies `startAfterDocument` on the next one, and the services are app-lifetime singletons shared with every other caller. Without `reset: true` a search silently omits every match sorting at or before the previous `load()`'s first document. The cited pattern already passes `reset: true` (`user_bloc.dart:334-336`) — note it also passes `limit: null`, which search must not.

**Give `FirestoreSearchIndex` its own `UserRepository()` / `ProductViewRepository()` instances** rather than `context.read<…>()`. `reset: true` protects search from inbound corruption, but search still writes a cursor back; private instances are what keep search from corrupting the Payment Center picker and the marketplace list. Construct them once at DI registration (Task 4 Step 5, line 838) — both service constructors reassign `FirebaseFirestore.instance.settings`.

**Also amend the bullet at line 627** (*"Respect the soft-delete convention used by every existing index"*) to:

> Do **NOT** add a `deleted_at` statement. Both services already start from `where('deleted_at', isNull: true)` (`user_firestore_service.dart:116`, `product_view_firestore_service.dart:120`), and that clause is what fills the `deleted_at` slot in each composite index. Passing `QueryStatement(field: 'deleted_at', isNull: true)` appends an identical second condition and trips `assert(… 'Condition $condition already exists in this query.')` at `cloud_firestore-5.6.12/lib/src/query.dart:649` — failing in debug builds and in the Task 3 tests. (`isNull: true` lowers to `addCondition(field, '==', null)` at `:677-679`, and `FieldPath` has real value equality at `field_path.dart:54-58`, so the duplicate genuinely compares equal.)

### I9. `SearchRequest.limit` is never wired, and the repository default is 10

**Plan says:** `this.limit = 20` (line 535), `final int limit;` (line 546) — and then nothing. Grep confirms `limit` appears nowhere else except an unrelated tokenizer local. Step 5 (616-627) never states what to pass to `load()`, while pointing at a pattern that passes `limit: null` (`user_bloc.dart:335`).

**What shipped:** omitting the argument takes `defaultDataLimit = 10` (`constants.dart:5`, propagated through `base_repository.dart:27`, `user_repository.dart:51`, `product_view_repository.dart:44`, and both services). The cap is applied **server-side** in `last_name ASC` / `updated_at DESC` order (`user_firestore_service.dart:118-120` + `:142`; `product_view_firestore_service.dart:127-129` + `:119-121`) — i.e. **before** the Dart refinement the plan requires two lines later. A search for "juan dela cruz" has query token `juan`, matches every Juan in the company, and with a cap of 10 or 20 in `last_name` ASC order, Juan Dela Cruz is dropped before Dart ever sees him. That directly contradicts spec `:173-175` (*"Dart refines against the full query string. This is what makes the 12 character cap correct rather than lossy."*).

**Do instead** — state the decision in Step 5: `load(statements: …, limit: <candidateLimit>, reset: true)`. Rename `SearchRequest.limit` so its role is unambiguous (candidate fetch cap vs. display cap) and wire it — `SearchOverlay.maxItems = 5` already handles overlay truncation. Note the residual: a high-cardinality token can still exceed any cap, so either state a bounded over-fetch (and its limitation) or state that search uses `limit: null` like the pattern it cites. Given the `array-contains` predicate already narrows far more than the BorrowerSearchWidget's full-collection scan, `limit: null` is defensible — but the plan must *choose*.

### I10. `SearchResults` has no total count — "See all N results" saturates

**Plan says:** `class SearchResults { final List<SearchResultItem> items; final SearchScope scope; }` (588-595); the overlay renders *"a 'See all N results' row when more exist"* (1009); asserted as `expect(find.text('See all 7 results'), findsOneWidget)` (992).

**Reality:** N can only come from `items.length`. With refinement running after the fetch (623-624), N is *the survivors of refinement among the first N documents* — for 300 matching offers the row can read "See all 14 results". Nothing supplies a total: `BaseDatabaseService.load()` returns `Future<List<T>>` with no count channel (`base_database_service.dart:30-35`), and while cloud_firestore ^5.4.1 does have `count()`, it would count *token* matches while the list shows *refined* matches — a header contradicting its own rows.

**Decisive:** the binding spec specifies this row as `results dropdown, top 5 + "See all"` — **no N** (`2026-08-24-search-design.md:186`). The count was invented past the spec.

**Do instead:** add `final bool hasMore;` (default false) to `SearchResults`, set from the **raw** list `load()` returned before Dart refinement. Fetch `limit + 1` and set `hasMore = rawDocs.length > limit`, truncating the raw list to `limit` before refining. **Do not** write `hasMore = items.length == request.limit` — refinement drops rows, so that reads false in exactly the case it must catch, and `== limit` is the standard off-by-one. Change line 1009's copy to "See all results" gated on `hasMore`, and line 992 to `expect(find.text('See all results'), findsOneWidget)`.

*Related gap, same root: `SearchIndex.query()` (line 601) has no pagination and Task 7 Step 5 (line 1084) describes "the full result list" on `/search`. With the same ceiling, "See all" navigates to the same capped set. Decide whether `/search` paginates or state plainly that v1 caps both surfaces.*

### I11. Staff offers queries are unscoped in the plan, company-scoped in the spec

**Plan says** (621-622): *"For `SearchScope.offers`: `search_tokens arrayContains request.queryToken`, plus each non-null `OfferFilters` field."* Company reaches offers only as a user-removable chip (519-521, 1064, 1075-1078) seeded from `params['company']` (1102).

**Spec says** (`:164`): `teller`, `loanOfficer`, `admin` → *"clients + products, **own `company_id` only**"*; only `customer` gets *"offers, across all companies"* (`:163`). And `:167-168`: *"`FirestoreSearchIndex` injects `company_id == currentUser.companyId` for **every staff query**"* — not "every clients query". `scopesFor` grants staff the offers scope (371-376), so this query shape is live.

**This is not a data leak** — `product_views` is public marketplace data every borrower already browses across all companies, and the existing product list scopes `company_id` only for `UserRole.admin` (`product_bloc.dart:136-144`, `extensions.dart:170-176`). It is a spec-conformance divergence with no recorded decision. Note the shipped index set proves nothing either way: the company-scoped `dev_product_views` index (`firestore.indexes.dev.json:729-750`) is fully explained by the spec-mandated company *facet*.

**Do instead — pick one and write it down:**

- **(a) Honour the spec.** Inject `company_id` for `teller`/`loanOfficer`/`admin` (and `reviewModerator`, per B9) on the offers scope; `appAdmin` stays unscoped (spec `:165`, same reasoning as B7); `customer` unscoped. Then the company chip is redundant for scoped staff — hide it — and `params['company']` (1102) must be *ignored* for those roles, not merely defaulted. Served by `firestore.indexes.dev.json:729-750` (+`:773-798` with term). No new index.
- **(b) Amend the spec** at `:164` to *"clients (own `company_id` only) + products (all companies)"* and at `:167-168`, keeping `OfferFilters.companyId` a pure facet. Served by `:711-728`.

Either way, `SearchRequest` (529-546) carries no role and `FirestoreSearchIndex` is given no auth dependency (449, 750), so option (a) needs the role threaded in — which B6's role branch already provides.

### I12. Nothing tests the authorization predicates

**Plan says:** Task 3's four tests (460-500) assert only `queryToken`/`isSearchable`; Step 5 has **no test step at all** — it goes from prose straight to *analyze and commit* (610-637). Task 4 mocks `SearchIndex` outright (line 660). Grep for `company_id` in the plan: lines 34, 617-620, 1251 — never inside a test. Done-when line 1242 (*"A borrower cannot resolve a clients scope — covered by test"*) is about the resolver, not the query.

**Why it matters:** `SearchTokensForUser` (`user_changes.go:106-129`) has **no role gate** — staff, admin and appAdmin user documents all carry `search_tokens` (also ungated at `user_created.go:112` and `backfill.go:180`). `user_role == UserRole.customer.name` is the only thing keeping staff PII out of clients results. And there is no *verifiable* server-side backstop: `apps/loans/firestore.rules` is the expired allow-all template (`request.time < timestamp.date(2024, 6, 22)`), `apps/loans/firebase.json:242-244` declares `firestore.indexes` and no `rules` key, and the live ruleset is console-managed and unreadable from source (`progress.md:617-621`, ruling I5). Spec `:167-170` names query construction as *the* boundary.

**Do instead** — add a Step to Task 3 that extracts the statement-building into a pure, testable method taking role + company, and asserts on the constructed `List<QueryStatement>`:

- staff clients query contains `company_id ==` the authenticated company AND `user_role == 'customer'`;
- appAdmin clients query contains `user_role` and **no** `company_id`;
- no `OfferFilters` field ever appears in a clients query.

Two mechanical traps: `QueryStatement` has no `==`/Equatable override, so assert by locating `statements.firstWhere((s) => s.field == 'company_id').isEqualTo` rather than `contains(QueryStatement(...))`; and do **not** assert `deleted_at` in the list — `load()` adds it (see I8).

**Split Done-when line 1242 in two:**
- *"A borrower cannot resolve a clients scope — asserted on the resolver (Task 2)"*
- *"The clients query carries `company_id` (staff) and `user_role == customer` (all roles) — asserted on the constructed `List<QueryStatement>`, not on the resolver; the appAdmin variant carries `user_role` and no `company_id`"*

**Add a Global Constraint recording ruling I5:** *resolver and query-construction scoping is where **this app** enforces scope. Whether it is also enforced server-side is unverified from this repo — `firebase.json` declares no `firestore.rules`, and the checked-in rules file (expired 2024-06-22) is not deployed and cannot be the live ruleset, since the app demonstrably works. Deliberately unpatched; deferred to the user (`progress.md:617-621`).* Soften line 365-366's `/// this is the authorization boundary` to `/// this is the app's authorization boundary`; the same overreach is inherited from spec `:167-171`.

### I13. `SearchRequest.companyId` and `OfferFilters.companyId` name two different companies

**Plan says:** `OfferFilters.companyId` (521) is undocumented; `SearchRequest.companyId` (543) is documented as the authorization value.

**Reality:** they denote different companies. `product_views.company_id` is the **lender** — `product_view_projection.go:205` writes `"company_id": mapString(product, "provider_id")` (and `:186`: *"company_id is NOT in the list — it is product.provider_id"*). `SearchRequest.companyId` was the **viewer's** company (removed in B6). Same name, same type, different referent, one of them undocumented.

**Do instead** — after B6 removes `SearchRequest.companyId`, document the survivor at line 521:

```dart
  /// The *provider* company whose offers to show - `product_views.company_id`,
  /// which the projection writes from the product's `provider_id`
  /// (product_view_projection.go:205). A discovery facet supplied by the user
  /// via chip or `?company=` query param. Never an authorization boundary;
  /// the viewer's company is resolved inside FirestoreSearchIndex.
```

Add one line to Step 5: *the viewer's company and `OfferFilters.companyId` are different values and must never be interchanged; `OfferFilters` contributes predicates to the offers query only and must never appear in the clients query* (covered by I12's test).

**Also specify where the company chip's LABEL comes from** — the deep link carries an id, not a name, and `company_name` (`product_view_projection.go:206`; `late String companyName` at `product_view_entity.dart:61-62`) is only reachable once results come back. Do **not** source it from the first result: `SearchResultItem` never carries it and a zero-result deep link has nothing to show. Carry the display name in filter state at selection time (the picker knows both), and for deep-link entry resolve once via `CompanyRepository.get(id: …)` (`company_repository.dart:30`), stating the failure behaviour — a nonexistent id renders as unresolved or is dropped, **never** as a raw document id. The plan also never specifies how a company is *chosen* (line 1077's "add facet" chip has no picker); specify that first. Same for how `maxInterestRate` and `term` render.

### I14. A filter-only offers query is unreachable, and unindexed if made reachable

**Plan says:** filters are parsed from query params independently of `q` (1101-1105), while `_onQueryChanged` returns `tooShort` before querying (776-784) and `_onFiltersChanged` re-dispatches with an empty term (827-828).

**Reality:** `/search?company=abc` renders chips and never queries — a dead-end deep link. If an executor "fixes" it by issuing the query, the shape (`company_id ==` + `deleted_at isNull` + `orderBy('updated_at', descending)`) has **no index**: the closest `dev_product_views` entry is `company_id, deleted_at, created_at ASC` (`firestore.indexes.dev.json:433-450`) — wrong sort field and direction. Every shipped offers index leads with `search_tokens CONTAINS`, by design (spec `:134-137`).

**Do instead** — add to Task 7 Step 5:

> Filters narrow a token search; they never issue one on their own. Every offers query must carry a `search_tokens` clause — gate on `SearchRequest.isSearchable` (see I4), not an ad-hoc length check. When the term is not searchable and `!filters.isEmpty`, render a distinct state ("Add a search term to apply these filters") rather than the generic too-short copy, and still render the chips so deep-linked filters are visible and removable. Task 7 Step 5 must also state that the screen dispatches `FiltersChangedEvent(initialFilters)` — or seeds `SearchState.filters` at construction — before/with the initial `QueryChangedEvent`, otherwise deep-linked filters never reach the bloc at all.
>
> Do **not** "fix" this by issuing the query and adding an index; and a filter-only query carrying `maxInterestRate` would still throw regardless of any index (finstack#103, see B8).

### I15. The empty-state copy is client-only

**Plan says** (1010-1011): `empty` → *"No results for X. Try a shorter term, or search by mobile number"*.

**Reality:** only `users` documents carry phone tokens (`entities.go:11-16`). `ProductViewTokens` is `Tokenize(companyName, loanType, tagLine)` (`entities.go:22-24`; spec `:60`) — a `product_views` document has no phone data at all. And `scopesFor(UserRole.customer)` returns `{offers}` only (369-370; spec `:156`), so **a borrower can never reach a scope where phone tokens exist** — this hint is unactionable 100% of the time for the entire borrower population.

**Do instead** — make the copy scope-aware. `SearchState` already carries the scope (line 651), so the overlay's `BlocBuilder` can branch on `state.scope` with no signature change:
- clients → *"Try a shorter term, or search by mobile number"*
- offers → *"Try a shorter term, or search by lender name or loan type"*

Add a Task 6 Step 1 test case (do **not** edit the assertion at line 996 — `find.textContaining('Try a shorter term')` passes under both): a `MockSearchBloc` seeded with `scope: SearchScope.offers`, `status: SearchStatus.empty`, expecting `find.textContaining('loan type')` and `findsNothing` for `find.textContaining('mobile number')`.

**Also fix the same wording in the spec** at `2026-08-24-search-design.md:224-226`, or the next plan re-seeds the defect.

---

## MINOR

### M1. The Dart test filename disagrees with the shipped Go pointer

The plan names `apps/loans/test/features/search/search_tokenizer_test.dart` (lines 48, 56, 121, 219, 227). `tokenizer_test.go:221` says the file is `apps/loans/test/features/search/tokenizer_test.dart`; the same stale line is copied at `docs/superpowers/plans/2026-08-24-search-backend.md:286`. `golden_tokens.json:2` names only the directory, which is right either way.

**Keep the plan's name** — every one of the 31 test files under `apps/loans/test/` is `<source>_test.dart`, and the source is `search_tokenizer.dart`. Correct the Go comment (and the backend plan line) in a **backend-side** change: `.github/workflows/loans-functions-development.yml:9,20` filters on `functions/loans/**`, so touching that file from a Flutter PR redeploys the Go backend for a comment and breaks the split-PR/backend-first rule.

### M2. `queryToken` treats `0917.555.0142` as a name

Line 554's `^[0-9+\s()-]+$` admits only digits, `+`, whitespace, `(`, `)`, `-`. Spec `:111-113` says *"predominantly digits"*. A dotted paste falls to the name path, yielding `0917.555.014` — and since a mobile number never contributes a raw full-value token (`entities.go:11-15`), that matches nothing, guaranteed.

Widen it, operating on `normalized` (not the raw `term`) so the symmetric-normalization step is preserved:

```dart
    // Phone-shaped: at least one digit, and every other character a separator
    // someone might paste. Narrower than the spec's "predominantly digits" on
    // purpose - a term with letters is a name.
    final phoneShaped = RegExp(r'^[0-9+.()/\s-]*[0-9][0-9+.()/\s-]*$');
```

Extend the doc comment at 548-550 to say the phone token is sent whole (see B5's version, which already does). Add a `'0917.555.0142'` case to the `queryToken` tests. *(The spec's "E.164 path" wording at `:111` is legacy — `:99-109` supersedes it with plain digit canonicalization; do not echo "E.164".)*

### M3–M4. Rune vs. code-unit, and the `limits` block

Both are folded into **I1**, **I2** and **I7** above; nothing separate to do. The rule, stated once: **every cap and every prefix/truncation operation goes through `.runes`, never `String.length` / `String.substring`** — `capFullValue` (I1), `_addPrefixes` (I7), `queryToken`'s `maxPrefix` truncation (562-563), `isSearchable`'s length (568, 777). And the Dart constants are `static const` (a Dart `const` cannot be loaded from JSON); the golden test asserts them against the `limits` block (B1).

### M5. Compare golden tokens as an **ordered list**, not sets

The plan compares with `.toSet()` and a rationale block at 101-107 (*"Compared as SETS, deliberately… Membership is the actual contract"*). That came from a real ruling (`progress.md:94-102`, committed as `4589abf`), but it **predates the Round-B restructure**. `golden_tokens.json:7` now states: *"The exact expected output: deduplicated and sorted ascending. **Compare as an ordered list.**"* Go uses `reflect.DeepEqual` on the slice (`tokenizer_test.go:241`). Every expected token in all 18 cases is ASCII after folding, so byte-wise and UTF-16 orders are identical and ordered comparison passes 18/18. Set comparison is strictly weaker — it also hides duplicates and an unsorted return, and once `maxTokens` truncates a *sorted* list (I2), sort order selects which tokens survive.

**Delete the set-comparison block at 101-107** and use the ordered `expect` in B1's harness. Add a Notes line recording that `golden_tokens.json:7` (introduced 2026-08-25) supersedes the sets ruling committed as `4589abf` (2026-08-24), and the guard: *ordered equality is safe only while the vectors stay ASCII; if a non-BMP token is ever added, normalize sort order on both sides (compare code points), never revert to sets and never delete the case.* The Go-only sorted-list assertion the original ruling preserved is already satisfied by `tokenizer_test.go:241`.

### M6. `_onFiltersChanged` cannot re-dispatch `QueryChangedEvent`

Lines 827-828 say it re-dispatches `QueryChangedEvent` with the current term, but the event requires `{required String location}` (line 651) and `SearchState` has no `location` — and a bloc handler has no `BuildContext` to call `GoRouter.of(context).location` (a repo-local extension at `extensions.dart:60-69`, not a go_router API; go_router is `^14.2.7`). **It does not compile.**

**Do not** fix it by storing `location` on the state: `ParsedQuery.term` is the prefix-**stripped** term (388-392, 298-306), so re-resolving it loses an explicit prefix. Concrete: an admin at `/payment-center` types `products: salary` → scope offers; a chip change re-dispatches `('salary', '/payment-center')`, `_defaultScope` matches neither `/offers` nor `Paths.index`, and returns **clients** — the scope silently flips and `OfferFilters` ride into a clients query.

**Do instead** — amend 827-828: `_onFiltersChanged` emits `state.copyWith(filters: event.filters)` then queries directly against `state.scope` and `state.term`, reusing the same `minPrefix` guard and `_requestId` stale-response guard. Factor the post-resolution body of `_onQueryChanged` into a shared `_runQuery(SearchScope scope, String term, Emitter<SearchState> emit)` and call it from both handlers. Note explicitly: it must **not** re-dispatch `QueryChangedEvent`.

### M7. The bloc declares an unused `_debounce`

Line 758 declares `final _debounce = Debounce(milliseconds: 250);` inside `SearchBloc`; it is never read there (line 823 says the widget uses `_debounce.run`, and `_debounce` is library-private to `search_bloc.dart`, so that will not compile either). `apps/loans/analysis_options.yaml` includes `very_good_analysis` and suppresses no `unused_field`, so `fvm flutter analyze` exits non-zero — breaking Done-when line 1239 and every "analyze and commit" step from Task 4 on. Meanwhile Task 5 Step 4 (944-945) specifies `onChanged` with **no debounce at all**, so an executor following the concrete code ships one Firestore query per keystroke.

The debounce **must** live in the widget: `pubspec.yaml` has `bloc: ^8.1.3` with no `bloc_concurrency`/`stream_transform`/`rxdart` (the plan notes this at 744), and `Debounce.run` inside a handler would call `emit` after the handler returned, which bloc 8 rejects.

**Do:** delete line 758; put `final _debounce = Debounce(milliseconds: 250);` in `SearchField`'s `State` with `_debounce.dispose()` in `dispose()` (`debounce.dart:5-19`; precedent at `add_user_widget.dart:64,169`); change 944-945 to `_debounce.run(() => context.read<SearchBloc>().add(QueryChangedEvent(...)))`. Also fix the four now-stale attributions: line 7, the Task 4 title (641), the commit message (847), and line 823 — the bloc owns only the request-id guard.

### M8. Stale dependency and executor notes

Replace **line 13**: *"**Depends on:** backend merged; **dev** indexes deployed 2026-08-26 and the dev backfill complete and verified end-to-end; **staging and production indexes are NOT deployed and no backfill has run there.**"*

Replace the notes at **1254-1258** with:

> Six composite indexes back this feature — 2 on `users`, 4 on `product_views` — defined in `apps/loans/firestore.indexes.dev.json:663-798` and mirrored, prefix-adjusted, in `.stg.json` / `.prod.json`. **Do NOT use the backend plan's Task 6 as the reference** (`2026-08-24-search-backend.md:1085-1160`): its five proposed indexes use unprefixed collection groups, a different field order, and two `interest_rate` indexes that were deliberately not shipped. The per-env files are the source of truth; `apps/loans/firestore.indexes.json` is a scratch artifact overwritten at deploy time (`apps/loans/scripts/deploy-indexes.sh:20-22`: *"Never edit it directly and never treat it as the source of truth"*) and currently holds a stale 35-index snapshot with **zero** `search_tokens` indexes — do not read it to check whether an index exists, and do not write it (three commits' index edits were already silently discarded this way — `functions/loans/MEMORY.md:374-395`).
>
> The indexes are deployed to **dev only** (`progress.md:675-681`); staging and production need `./scripts/deploy-indexes.sh stg|prod` before the feature ships there. Nothing in CI deploys index files.
>
> A `FAILED_PRECONDITION` / index-required error **in dev** no longer means a missing deploy — it means the query shape is not covered by any of the six. Compare against `firestore.indexes.dev.json`: `search_tokens CONTAINS` is first, and the users indexes sort by `last_name ASC`, not `updated_at`.
>
> A **different** error — *"inequality filter property and first sort order must be the same"* / *"you must also use 'interest_rate' as your first argument to orderBy()"* — is finstack#103 (see B8). It is thrown client-side before any network call, because `ProductViewFirestoreService.load():121` hardcodes `orderBy('updated_at', descending)`. **No index fixes this.**

Also correct `functions/loans/MEMORY.md:374`, which still says the backfill was only exercised against fakes.

### M9. Done-when criteria

Line 1241 → *"The Dart golden-vector test reads the same `golden_tokens.json` the Go suite asserts, dispatches each case on its `path`, enforces per-path input arity, FAILS on an unknown or missing `path`, FAILS if any of the four paths has no case, and asserts the `limits` block (min_prefix 2, max_prefix 12, max_full_value 256, max_words 64, max_tokens 2000) against the Dart constants — mirroring `tokenizer_test.go:222-302`."*

Line 1243 → *"Manual check on development: a client name, a full pasted email, and the same mobile number in all **FOUR** spellings — `09175550142`, `+639175550142`, `639175550142`, `00639175550142` — each returning the same client. The fourth is the only one that catches a single-pass prefix trim (`golden_tokens.json:145-154`)."*

Add:
- *"Manual check: pasting a client's full name with a doubled internal space (e.g. `Juan  Carlos`) returns the same result as the single-spaced spelling (`golden_tokens.json:94-103`)."*
- *"Manual check, offers scope: a lender name and a `loan_type` both return results; the company and term chips filter correctly. Verify whatever B8's decision was holds end to end — if the interest-rate facet is dropped, then no chip offers it AND `/search?scope=offers&interest=5` does not construct a range filter (the router at line 1103 still parses `params['interest']`, so removing only the chip leaves the crash reachable by deep link)."*
- *"Manual check as an appAdmin: a clients search with no company scope returns results spanning **more than one company**, served by the unscoped `dev_users` index. Same-company-only results mean the unscoped path is not being exercised."*
- *"Manual check: the last-4 tail (`0142`) returns the client (see I3)."* — only if I3's `arrayContainsAny` fix lands; otherwise omit, it cannot pass.

Also amend Step 4's *"Expected: PASS, all four tests"* (line 220) per B1.

### M10. `showSearchField` is a dead flag

Line 951-953 says to default it to `true` *"following the existing flags"*. Those flags all default to **false** and are set per role by the caller (`layout_widgets.dart:86-89`; `home_screen.dart:39-49`). More decisively: `LayoutWidgets.defaultAppBar` has exactly **one** caller — `app_widgets.dart:65` — and all four screens go through the `AppWidgets.defaultAppBar` pass-through (`app_widgets.dart:55-74`), which forwards each flag by hand. A flag added only to `LayoutWidgets` is unreachable from `home_screen.dart`.

**Do:** default it to `false`; add `bool showSearchField` to `app_widgets.dart:55-63` and forward it at `:65-73`; set it at `home_screen.dart:39`. Add `apps/loans/lib/widgets/app_widgets.dart` and `apps/loans/lib/features/index/screens/home_screen.dart` to Task 5's Files list and the `git add` at line 964.

**Replace the "following the existing flags" justification**: unlike them it is **not** role-derived — spec `:156-165` gives every role at least one scope (`customer` → offers), so there is no role for which the field should be hidden. The flag keeps the field off app bars, not off roles. (Spec `:207-208` carries the same loose wording; flag it there too.)

**Add the guard sentence:** the replacement must stay inside the `if (!showSignUp && !showLogin) ...[` block at `layout_widgets.dart:129` (the stub it replaces is at `:270-281`). That guard is the only thing keeping search off the three pre-auth app bars — `login_screen.dart:61`, `register_screen.dart:47`, `set_password_screen.dart:179` — where `AuthenticationService.instance.user` throws `Please login` (`authentication_service.dart:16-22`).

---

## Still true — do NOT change

- **The tokenizer's overall shape.** `normalize` → full-value token + per-word prefix expansion, `minPrefix = 2`, `maxPrefix = 12`, and `_addPrefixes` emitting a sub-`minPrefix` token whole. Only the specific defects above change.
  - **Superseded on execution (2026-08-31):** the `_accented`/`_plain` table was **deleted**, not kept. Real NFD subsumes it, and keeping both is two sources of truth for one rule. Its *ordering* claim (lowercase before folding) was also wrong: Go folds first, then lowercases, and the Dart side now mirrors that. Verified by replicating `Normalize` against the same `golang.org/x/text` version the functions use — the table cannot fold `Nguyễn`, `Erdős`, `Ștefan` or `Māori`, and must NOT fold `Straße`→`strasse` or `Søren`→`soren`, which Go does not.
- **`canonicalPhone` stays in the API.** It is exported in Go (`phone.go:18`) and is the runtime query-side entry point (line 556). It is simply not one of the four golden *paths*.
- **The resolver design.** Scope selection lives in `SearchScopeResolver`, a customer has no clients scope, and a typed prefix naming a scope the role lacks is treated as literal text (390-392). B9 adds a missing case; B11 makes the deep link *feed* the resolver instead of bypassing it. Neither weakens the rule.
- **The plan's Task 3 tests for `queryToken` at 473-489**, including the email assertion at 482-489 — that one states the correct contract and B5 changes the *code* to match it.
- **The bloc's request-id / stale-response guard.** Correct as written; only the debounce ownership (M7) and the auth reads (B6/B12) move.
- **The client-side refinement principle** (spec `:173-175`) — refine against the full term because the query token was truncated. I5 narrows it (not for phone-shaped terms); I9 makes the fetch large enough for it to be honest. The principle stands.
- **`SearchOverlay.maxItems = 5`** and the overlay/`/search` split, including the deep-linkability rationale at 1111-1112.
- **The overall task order and file structure**, the `dev_`/`stg_` prefix convention, and the rule that Firestore collection paths never hardcode a prefix.
- **The dev environment.** Indexes are deployed and READY, tokens are backfilled, and both a clients query and an offers query have been executed successfully against `loooans-dev-stg`. The backend is not in question — only the plan's description of it.