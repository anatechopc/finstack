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
