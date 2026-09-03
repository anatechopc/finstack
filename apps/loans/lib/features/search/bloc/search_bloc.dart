import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:user_repository/user_repository.dart';

part 'search_event.dart';
part 'search_state.dart';

/// Owns the query, the resolved scope, the offer facets and the results.
///
/// It owns exactly one piece of concurrency control — the request-id guard —
/// and no debounce: that lives in `SearchField`. `bloc: ^8.1.3` ships no
/// `bloc_concurrency`, so `on<QueryChangedEvent>` runs handlers concurrently
/// and a slow response for `de` really can land after a fast one for
/// `dela cruz`. The guard is the whole defence against it.
///
/// The company is **not** read here. `AuthenticationService.company` throws for
/// `customer` and for `appAdmin`, so reading it in this handler would put the
/// borrower's only scope in a permanent, silent error state.
/// `FirestoreSearchIndex` resolves it, branching on role first.
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  /// Production constructor used by DI. Delegates to
  /// [SearchBloc.withDependencies] so the logic stays unit-testable.
  SearchBloc(BuildContext context)
      : this.withDependencies(
          searchIndex: context.read<SearchIndex>(),
          authService: AuthenticationService.instance,
        );

  SearchBloc.withDependencies({
    required SearchIndex searchIndex,
    required this.authService,
  })  : _searchIndex = searchIndex,
        super(SearchState(scope: _defaultScope(authService))) {
    on<QueryChangedEvent>(_onQueryChanged);
    on<FiltersChangedEvent>(_onFiltersChanged);
    on<SearchClearedEvent>(_onCleared);
  }

  final SearchIndex _searchIndex;

  /// Injected, never `AuthenticationService.instance` — `CLAUDE.md` forbids the
  /// singleton in blocs. Read per event, not cached: this bloc is mounted above
  /// the login route, and a cached identity would freeze the role across
  /// logout/login. The one construction-time read, [_defaultScope], is
  /// repeated on [SearchClearedEvent] for the same reason.
  final AuthenticationService authService;

  /// Incremented on every query and on every abandonment. A response whose id
  /// no longer matches is discarded.
  int _requestId = 0;

  /// The candidate page that produced the results now on the state. An
  /// identical query asking for no more than this is answered from the state.
  int _servedLimit = 0;

  /// The scope the field's hint shows before the first query: clients when
  /// the role has it, else offers. "Search clients…" is a lie to a borrower.
  static SearchScope _defaultScope(AuthenticationService auth) {
    final UserRole role;
    try {
      role = auth.user.userRole;
    } on Exception {
      // `user` throws 'Please login' with nobody signed in — which is exactly
      // when logout dispatches `SearchClearedEvent`. Nobody gets the
      // least-privileged scope.
      return SearchScope.offers;
    }

    return SearchScopeResolver.scopesFor(role).contains(SearchScope.clients)
        ? SearchScope.clients
        : SearchScope.offers;
  }

  Future<void> _onQueryChanged(
    QueryChangedEvent event,
    Emitter<SearchState> emit,
  ) {
    final parsed = SearchScopeResolver.resolve(
      role: authService.user.userRole,
      location: event.location,
      rawQuery: event.query,
      pinnedScope: event.pinnedScope,
    );

    return _runQuery(
      scope: parsed.scope,
      term: parsed.term,
      filters: event.filters ?? state.filters,
      candidateLimit:
          event.candidateLimit ?? SearchRequest.defaultCandidateLimit,
      emit: emit,
    );
  }

  Future<void> _onFiltersChanged(
    FiltersChangedEvent event,
    Emitter<SearchState> emit,
  ) {
    // Re-query the scope and term already resolved. Re-dispatching
    // `QueryChangedEvent` would re-resolve `state.term`, which is
    // prefix-stripped — an admin's `products: acme` at `/payment-center` would
    // silently flip back to the clients scope and carry the offer facets there.
    return _runQuery(
      scope: state.scope,
      term: state.term,
      filters: event.filters,
      candidateLimit: SearchRequest.defaultCandidateLimit,
      emit: emit,
    );
  }

  void _onCleared(SearchClearedEvent event, Emitter<SearchState> emit) {
    _requestId++;
    _servedLimit = 0;
    emit(SearchState(scope: _defaultScope(authService)));
  }

  Future<void> _runQuery({
    required SearchScope scope,
    required String term,
    required OfferFilters filters,
    required int candidateLimit,
    required Emitter<SearchState> emit,
  }) async {
    if (SearchTokenizer.normalize(term).runes.length <
        SearchTokenizer.minPrefix) {
      // Abandon anything in flight too: without this, results for a query the
      // user has just erased land on top of the `tooShort` state.
      _requestId++;
      _servedLimit = 0;
      emit(
        state.copyWith(
          status: SearchStatus.tooShort,
          scope: scope,
          term: term,
          filters: filters,
          // Erase means erase. Clearing here rather than in each surface is
          // the only reason the overlay and `/search` don't both have to carry
          // the same "these results are stale" guard.
          results: SearchResults.empty,
        ),
      );

      return;
    }

    // "See all" and back/forward re-dispatch the query whose results are
    // already on the state; Firestore bills every candidate read again. A
    // larger page is a different question and always runs.
    final answered = state.status == SearchStatus.results ||
        state.status == SearchStatus.empty;
    if (answered &&
        scope == state.scope &&
        term == state.term &&
        filters == state.filters &&
        candidateLimit <= _servedLimit) {
      return;
    }

    emit(
      state.copyWith(
        status: SearchStatus.loading,
        scope: scope,
        term: term,
        filters: filters,
      ),
    );

    final id = ++_requestId;

    try {
      final results = await _searchIndex.query(
        SearchRequest(
          scope: scope,
          term: term,
          filters: filters,
          candidateLimit: candidateLimit,
        ),
      );

      // A newer query started while this one was in flight — drop this result.
      if (id != _requestId) return;

      _servedLimit = candidateLimit;
      emit(
        state.copyWith(
          status:
              results.items.isEmpty ? SearchStatus.empty : SearchStatus.results,
          results: results,
        ),
      );
    } catch (err) {
      if (id != _requestId) return;

      emit(state.copyWith(status: SearchStatus.error));
    }
  }
}
