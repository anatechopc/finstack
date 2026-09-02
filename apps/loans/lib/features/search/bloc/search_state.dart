part of 'search_bloc.dart';

enum SearchStatus { idle, tooShort, loading, results, empty, error }

final class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.idle,
    this.scope = SearchScope.clients,
    this.term = '',
    this.results = SearchResults.empty,
    this.filters = const OfferFilters(),
  });

  final SearchStatus status;

  /// The scope the last query resolved to. Surfaces branch on it — the empty
  /// state's "search by mobile number" hint is true of clients only; a
  /// `product_views` document carries no phone data at all.
  final SearchScope scope;

  /// The term actually searched: prefix-**stripped**, so `products: salary`
  /// leaves `salary` here. Kept through an error so the field is not cleared
  /// under the user when a query fails.
  final String term;

  final SearchResults results;
  final OfferFilters filters;

  /// The empty-state line. It lives here rather than in a surface because both
  /// surfaces render it and a copy that drifts between them is a copy that is
  /// wrong in one of them.
  ///
  /// Scope-aware for the reason [scope] is on the state at all: only `users`
  /// documents carry phone tokens, and `scopesFor(customer)` is `{offers}`, so
  /// a "search by mobile number" hint is unactionable for every borrower.
  String get emptyCopy => switch (scope) {
        SearchScope.clients => 'No results for "$term". Try a shorter term, '
            'search by mobile number, or type offers: to search offers.',
        SearchScope.offers => 'No results for "$term". Try a shorter term, '
            'or search by lender name or loan type.',
      };

  SearchState copyWith({
    SearchStatus? status,
    SearchScope? scope,
    String? term,
    SearchResults? results,
    OfferFilters? filters,
  }) {
    return SearchState(
      status: status ?? this.status,
      scope: scope ?? this.scope,
      term: term ?? this.term,
      results: results ?? this.results,
      filters: filters ?? this.filters,
    );
  }

  /// `SearchResults` and `OfferFilters` are not `Equatable`, so they compare by
  /// identity here. That is deliberate: every query builds a fresh instance, so
  /// two successive result sets are never accidentally deduplicated by `emit`.
  @override
  List<Object?> get props => [status, scope, term, results, filters];
}
