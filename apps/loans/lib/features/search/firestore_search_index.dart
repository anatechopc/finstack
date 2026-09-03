import 'package:flutter/foundation.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

/// Fetches candidate `users` documents. Injected so the authorization
/// predicates can be asserted without Firebase.
typedef ClientLoader = Future<List<User>> Function(
  List<QueryStatement> statements,
  int limit,
);

/// Fetches candidate `product_views` documents.
typedef OfferLoader = Future<List<ProductView>> Function(
  List<QueryStatement> statements,
  int limit,
);

/// Private to search, and lazily constructed — `load()` writes
/// `lastDocumentSnapshot` back onto the service after every call, and the
/// repositories registered in `repository_providers.dart` are app-lifetime
/// singletons shared with `UserBloc`, the Payment Center picker and the
/// marketplace list. `reset: true` stops search reading someone else's
/// cursor; owning its own instances stops search writing one to them.
final UserRepository _searchUserRepository = UserRepository();
final ProductViewRepository _searchProductViewRepository =
    ProductViewRepository();

/// Builds every search query the app issues.
///
/// This is the app's authorization boundary. `SearchTokensForUser` has no
/// role gate, so staff, admin and appAdmin user documents all carry
/// `search_tokens`; `user_role == customer` is the only thing keeping staff
/// PII out of clients results. Whether the same rule is enforced server-side
/// is unverified from this repo — `firebase.json` declares no
/// `firestore.rules` key and the checked-in rules file expired 2024-06-22, so
/// it cannot be the live ruleset.
class FirestoreSearchIndex implements SearchIndex {
  FirestoreSearchIndex({
    AuthenticationService? auth,
    ClientLoader? loadClients,
    OfferLoader? loadOffers,
  })  : _auth = auth ?? AuthenticationService.instance,
        _loadClients = loadClients ?? _defaultClientLoader,
        _loadOffers = loadOffers ?? _defaultOfferLoader;

  final AuthenticationService _auth;
  final ClientLoader _loadClients;
  final OfferLoader _loadOffers;

  static Future<List<User>> _defaultClientLoader(
    List<QueryStatement> statements,
    int limit,
  ) =>
      _searchUserRepository.load(
        statements: statements,
        limit: limit,
        reset: true,
      );

  static Future<List<ProductView>> _defaultOfferLoader(
    List<QueryStatement> statements,
    int limit,
  ) =>
      _searchProductViewRepository.load(
        statements: statements,
        limit: limit,
        reset: true,
      );

  /// The predicates that reach Firestore, or an empty list when no query may
  /// be issued at all — an unsearchable term, or a scope this role does not
  /// have. Empty is never a legitimate query shape: `search_tokens` is always
  /// present, so [query] treats emptiness as "do not ask".
  ///
  /// Deliberately does **not** add `deleted_at`: both services already open
  /// with `where('deleted_at', isNull: true)` (`UserFirestoreService.load`,
  /// `ProductViewFirestoreService.load`), which is what fills that slot in
  /// each composite index. A second identical condition trips an assert
  /// inside cloud_firestore.
  @visibleForTesting
  List<QueryStatement> statementsFor(SearchRequest request) {
    final role = _auth.user.userRole;

    // The same set the resolver uses, so search cannot drift from it.
    if (!SearchScopeResolver.scopesFor(role).contains(request.scope)) {
      return const <QueryStatement>[];
    }
    if (!request.isSearchable) return const <QueryStatement>[];

    // Read the company only for the roles whose session actually has one.
    // `AuthenticationService.company` throws for `customer` AND for
    // `appAdmin`, and `hasCompany` is a null check where the getter gates on
    // role, so it can be true while `company` throws.
    final viewerCompanyId = UserRole.companyManagedRoles.contains(role)
        ? _auth.company.id
        : null;

    final tokens = QueryStatement(
      field: 'search_tokens',
      arrayContainsAny: request.queryTokens,
    );

    switch (request.scope) {
      case SearchScope.clients:
        return <QueryStatement>[
          tokens,
          // appAdmin belongs to no company and searches unscoped, served by
          // the company-less `users` index.
          if (viewerCompanyId != null)
            QueryStatement(field: 'company_id', isEqualTo: viewerCompanyId),
          QueryStatement(
            field: 'user_role',
            isEqualTo: UserRole.customer.name,
          ),
        ];

      case SearchScope.offers:
        // The search design spec: staff see their own company's offers only.
        // Their injected company wins over the facet, which is why the chip is
        // hidden for them; `customer` and `appAdmin` search all companies and
        // the facet is theirs to set.
        final companyId = viewerCompanyId ?? request.filters.companyId;

        return <QueryStatement>[
          tokens,
          if (companyId != null)
            QueryStatement(field: 'company_id', isEqualTo: companyId),
          if (request.filters.term != null)
            QueryStatement(field: 'term', isEqualTo: request.filters.term),
        ];
    }
  }

  @override
  Future<SearchResults> query(SearchRequest request) async {
    final statements = statementsFor(request);
    if (statements.isEmpty) return SearchResults.empty;

    return switch (request.scope) {
      SearchScope.clients =>
        _search(request, statements, _loadClients, _matchClient),
      SearchScope.offers =>
        _search(request, statements, _loadOffers, _matchOffer),
    };
  }

  static Future<SearchResults> _search<T>(
    SearchRequest request,
    List<QueryStatement> statements,
    Future<List<T>> Function(List<QueryStatement>, int) load,
    SearchResultItem? Function(T, String) match,
  ) async {
    // One over the cap, so `hasMore` is answered by the raw page rather than
    // by the refined one.
    final raw = await load(statements, request.candidateLimit + 1);
    final page = raw.take(request.candidateLimit);
    final term = request.normalizedTerm;

    return SearchResults(
      items: [
        for (final candidate in page)
          if (match(candidate, term) case final item?) item,
      ],
      hasMore: raw.length > request.candidateLimit,
    );
  }

  /// Refines a client candidate against the full term.
  ///
  /// A phone-shaped term takes a separate path: its token was never truncated,
  /// so there is nothing to refine away, and the stored `mobile_number` is raw
  /// (`SearchTokensForUser` never rewrites it) — comparing the term's
  /// spelling against it would drop correct matches. The index also emits
  /// digit-only parts of the email (`jc.1998@x.com` → `1998`), so a digit run
  /// the mobile does not explain may still be a correct email match.
  static SearchResultItem? _matchClient(User user, String term) {
    if (SearchRequest.phoneShaped.hasMatch(term)) {
      if (_matchesPhone(term, user.mobileNumber)) {
        return ClientResultItem(user: user, matchedField: 'mobile');
      }
      if (_matchesWords(term, [user.emailAddress])) {
        return ClientResultItem(user: user, matchedField: 'email');
      }

      return null;
    }

    if (_matchesWords(term, [user.firstName, user.middleName, user.lastName])) {
      return ClientResultItem(user: user, matchedField: 'name');
    }
    if (_matchesWords(term, [user.emailAddress])) {
      return ClientResultItem(user: user, matchedField: 'email');
    }

    return null;
  }

  static SearchResultItem? _matchOffer(ProductView view, String term) {
    if (_matchesWords(term, [view.companyName])) {
      return OfferResultItem(productView: view, matchedField: 'company_name');
    }
    if (_matchesWords(term, [view.loanType])) {
      return OfferResultItem(productView: view, matchedField: 'loan_type');
    }
    if (_matchesWords(term, [view.tagLine])) {
      return OfferResultItem(productView: view, matchedField: 'tag_line');
    }

    return null;
  }

  /// True when every word of [term] is a prefix of some word form in
  /// [values] — the same shape the token index matches on, so refinement
  /// narrows the candidate set without contradicting it. A term longer than
  /// [SearchTokenizer.maxPrefix] is exactly what this catches: 'bartholomewson'
  /// was sent as 'bartholomews' and must not keep 'Bartholomewsmith'.
  ///
  /// Both sides go through [SearchTokenizer.wordForms]: the haystack holds
  /// every form the indexer prefix-expanded (`Dela-Cruz` → `delacruz`,
  /// `dela`, `cruz`) and each term word is compared as its joined form, which
  /// is what [SearchRequest.queryTokens] sent. Splitting the haystack on spaces
  /// alone
  /// dropped `Dela-Cruz` for `cruz` and `O'Brien` for `brien` — rows the
  /// index had correctly returned.
  static bool _matchesWords(String term, List<String?> values) {
    final haystack = values
        .whereType<String>()
        .map(SearchTokenizer.normalize)
        .expand((value) => value.split(' '))
        .expand(SearchTokenizer.wordForms)
        .toList();

    return term
        .split(' ')
        .map(SearchTokenizer.wordForms)
        .where((forms) => forms.isNotEmpty)
        .map((forms) => forms.first)
        .every(
          (word) => haystack.any((candidate) => candidate.startsWith(word)),
        );
  }

  /// A 4-digit run is ambiguous: `PhoneTokens` indexes it both as a prefix of
  /// the canonical number and as its last-four tail, and the query sent both
  /// readings, so either may be the one that matched. The tail is compared
  /// raw — `canonicalPhone('0142')` is `'142'`. Anything longer is a prefix
  /// of the canonical number.
  static bool _matchesPhone(String term, String storedMobile) {
    final stored = SearchTokenizer.canonicalPhone(storedMobile);
    if (stored.isEmpty) return false;

    final prefix = SearchTokenizer.canonicalPhone(term);
    final isPrefix = prefix.isNotEmpty && stored.startsWith(prefix);

    final digits = SearchRequest.digitsOf(term);
    if (digits.length != SearchTokenizer.lastDigits) return isPrefix;

    return isPrefix ||
        stored.length >= SearchTokenizer.lastDigits &&
            stored.endsWith(digits);
  }
}
