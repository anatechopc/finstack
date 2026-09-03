import 'package:equatable/equatable.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

/// Filters applied to offer results.
///
/// v1 ships exactly **two** indexed facets — company and term — in all four
/// combinations (`firestore.indexes.{dev,stg,prod}.json`). Each additional
/// facet needs its own composite index in every environment.
///
/// Interest rate is deliberately absent: it is a range filter, and
/// `ProductViewFirestoreService.load` hardcodes `orderBy('updated_at')` before
/// its statement loop, so Firestore rejects the query outright. Enabling it
/// needs a `searchOffers` method in `packages/loans/product_view_repository`
/// — deferred to finstack#103.
///
/// Value-equal so `SearchBloc` can tell "the same facets again" from a real
/// change: every surface constructs a fresh instance per dispatch.
class OfferFilters extends Equatable {
  const OfferFilters({this.companyId, this.term});

  /// The *provider* company whose offers to show — `product_views.company_id`,
  /// which the projection writes from the product's `provider_id`
  /// (`projectedProductFields`). A discovery facet supplied by the user via
  /// chip or `?company=` query param. Never an authorization boundary; the
  /// viewer's company is resolved inside `FirestoreSearchIndex` and is a
  /// different value entirely.
  final String? companyId;

  /// `product_views.term` — a String ('30d', '6m'), not a number. The numeric
  /// period is `max_period`, which is not a facet.
  final String? term;

  bool get isEmpty => companyId == null && term == null;

  @override
  List<Object?> get props => [companyId, term];
}

/// What to search for. Deliberately carries **no** company and **no** role:
/// a caller able to pass those is able to pass the wrong ones, so
/// `FirestoreSearchIndex` resolves both from the authenticated session.
class SearchRequest {
  const SearchRequest({
    required this.scope,
    required this.term,
    this.filters = const OfferFilters(),
    this.candidateLimit = defaultCandidateLimit,
  });

  /// Enough that a common token's page still holds the refined hit — see
  /// [candidateLimit]. Public so the bloc's event can default to the same
  /// number without restating it.
  static const int defaultCandidateLimit = 50;

  final SearchScope scope;
  final String term;
  final OfferFilters filters;

  /// How many documents to fetch **before** the Dart refinement, not how many
  /// to show. Firestore applies the cap server-side, in `last_name` ASC /
  /// `updated_at` DESC order, so it is applied before refinement can run — a
  /// cap of 10 would drop "Juan Dela Cruz" from a search for "juan dela cruz"
  /// before Dart ever sees him.
  ///
  /// A bounded over-fetch, not `limit: null`: a high-cardinality token
  /// ("dela") would otherwise read the whole matching set on every keystroke.
  /// The residual is real — beyond this many token matches, a refined result
  /// can be missed. [SearchResults.hasMore] is what tells the user so.
  final int candidateLimit;

  /// [term] after [SearchTokenizer.normalize], computed once per instance.
  /// The NFD/NFC round trip is the costliest thing on the query path, and
  /// [queryTokens], [isSearchable] and the refinement all need the result.
  /// An `Expando` rather than a `late` field so the constructor stays const.
  String get normalizedTerm =>
      _normalized[this] ??= SearchTokenizer.normalize(term);

  static final Expando<String> _normalized = Expando<String>();

  /// The tokens sent to Firestore, matched with `array-contains-any`.
  ///
  /// A name term sends the JOINED form of its first word — `Tokenize`
  /// prefix-expands `o'brien` as `obrien` and `dela-cruz` as `delacruz`, so
  /// the punctuation the user typed must be stripped the same way — cut to
  /// [SearchTokenizer.maxPrefix] runes and refined client-side.
  ///
  /// A value containing '@' is sent WHOLE, capped only at
  /// [SearchTokenizer.maxFullValue]: '@' and '.' are consumed by the word
  /// split before prefixes are taken, so the full-value token is the only one
  /// a complete paste can match. A *partial* paste ("juan.cruz@gm") has no
  /// such token, so the joined prefix of the local part goes with it.
  ///
  /// A phone-shaped term emits up to two candidates. `PhoneTokens` indexes the
  /// last four digits of the *canonical* form as a discrete token because
  /// staff often have only the tail — but `canonicalPhone('0142')` strips the
  /// leading zero to `'142'`, which is in no token set. Sending a 4-digit run
  /// raw *as well* covers the tail without breaking the prefix path, and
  /// `array-contains-any` needs no new index: every `search_tokens` entry is
  /// `arrayConfig: CONTAINS`.
  List<String> get queryTokens {
    final normalized = normalizedTerm;

    if (phoneShaped.hasMatch(normalized)) {
      final digits = digitsOf(normalized);
      final canonical = SearchTokenizer.canonicalPhone(normalized);

      return <String>{
        canonical,
        if (digits.length == SearchTokenizer.lastDigits) digits,
      }.where((token) => token.isNotEmpty).toList();
    }

    // normalize() collapses internal whitespace runs, so a single-space split
    // is sufficient here.
    final first = normalized.split(' ').first;
    if (first.isEmpty) return const <String>[];

    if (first.contains('@')) {
      final local = SearchTokenizer.wordForms(first.split('@').first);

      return <String>{
        SearchTokenizer.capFullValue(first),
        if (local.isNotEmpty) SearchTokenizer.prefixOf(local.first),
      }.toList();
    }

    final forms = SearchTokenizer.wordForms(first);
    if (forms.isEmpty) return const <String>[];

    return <String>[SearchTokenizer.prefixOf(forms.first)];
  }

  /// Measured on the value actually sent, not only on the raw term.
  ///
  /// The raw-term gate stays because the spec's minimum is a rule about the
  /// query the user typed. It is not sufficient on its own: '63', '+63' and
  /// '()' all clear it and then canonicalize to '', a legal query that can
  /// never match.
  ///
  /// The `minPrefix` floor applies to phone tokens **only**. `PhoneTokens`
  /// expands prefixes from `minPrefix` and adds a full canonical that is never
  /// one digit, so a 1-character phone token ('09' → '9', '+639' → '9') is in
  /// no token set and cannot be. A *name* token may legitimately be shorter:
  /// `addPrefixes` indexes a middle initial verbatim, so 'a bcd' must stay
  /// searchable.
  bool get isSearchable {
    final tokens = queryTokens;
    if (tokens.isEmpty) return false;

    final normalized = normalizedTerm;
    if (normalized.runes.length < SearchTokenizer.minPrefix) return false;

    if (!phoneShaped.hasMatch(normalized)) return true;

    return tokens.every(
      (token) => token.length >= SearchTokenizer.minPrefix,
    );
  }

  /// A term made only of digits and phone punctuation. Public because the
  /// refinement has to take the same branch the token did — a phone-shaped
  /// term is never truncated, so refining it like a name would drop correct
  /// matches.
  static final RegExp phoneShaped = RegExp(r'^[0-9+\s()-]+$');

  static String digitsOf(String value) => value.replaceAll(_nonDigit, '');

  static final RegExp _nonDigit = RegExp('[^0-9]');
}

/// One result row. A sum type, because the two scopes read different
/// collections and share no id: a client row is a `users` document, an offer
/// row is a `product_views` document whose *document id* is meaningless —
/// legacy views carry auto-generated ids and every consumer selects by
/// `product_id` (`HandleProductWrittenCore`).
sealed class SearchResultItem {
  const SearchResultItem({required this.matchedField});

  /// Which source field produced the match, so a row the user did not
  /// obviously search for still explains itself. Clients: `name`, `email` or
  /// `mobile`. Offers: `company_name`, `loan_type` or `tag_line`.
  final String matchedField;
}

class ClientResultItem extends SearchResultItem {
  const ClientResultItem({required this.user, required super.matchedField});

  final User user;
}

class OfferResultItem extends SearchResultItem {
  const OfferResultItem({
    required this.productView,
    required super.matchedField,
  });

  final ProductView productView;
}

class SearchResults {
  const SearchResults({
    required this.items,
    this.hasMore = false,
  });

  final List<SearchResultItem> items;

  /// Whether the *raw* page came back full — set before refinement, never from
  /// `items.length`. Refinement drops rows, so `items.length == limit` reads
  /// false in exactly the case it has to catch.
  final bool hasMore;

  static const empty = SearchResults(items: []);
}

/// The swap point. `FirestoreSearchIndex` implements this now; a
/// `TypesenseSearchIndex` can replace it without the bloc or UI changing,
/// which is what makes choosing Firestore today reversible.
// The single member IS the point: this is the seam a TypesenseSearchIndex
// slots into, not an accidental one-method class.
// ignore: one_member_abstracts
abstract class SearchIndex {
  Future<SearchResults> query(SearchRequest request);
}
