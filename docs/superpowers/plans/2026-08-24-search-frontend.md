# Search Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give staff and borrowers a working search — an app-bar field with a results overlay, a deep-linkable `/search` page with offer filters, and role-derived scopes enforced at query construction.

**Architecture:** A Dart tokenizer mirrors the Go indexer exactly, pinned by the same golden vector file. A `SearchIndex` interface isolates Firestore so the engine can be swapped later. `SearchBloc` owns debounce and a request-id guard against out-of-order responses. Two surfaces render the same result tile.

**Tech Stack:** Flutter (fvm), `flutter_bloc`, `bloc_test`, `mocktail`, `go_router`, `very_good_analysis`.

**Spec:** `docs/superpowers/specs/2026-08-24-search-design.md`

**Depends on:** `docs/superpowers/plans/2026-08-24-search-backend.md` — merged and deployed to development first, and the backfill run. Queries return nothing until `search_tokens` exists.

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
