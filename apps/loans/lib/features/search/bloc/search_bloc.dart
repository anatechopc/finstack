import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/services/authentication_service.dart';

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
/// `customer` and for `appAdmin` (`authentication_service.dart:42-53`), so
/// reading it in this handler would put the borrower's only scope in a
/// permanent, silent error state. `FirestoreSearchIndex` resolves it, branching
/// on role first.
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
        super(const SearchState()) {
    on<QueryChangedEvent>(_onQueryChanged);
    on<FiltersChangedEvent>(_onFiltersChanged);
  }

  final SearchIndex _searchIndex;

  /// Injected, never `AuthenticationService.instance` — `CLAUDE.md` forbids the
  /// singleton in blocs. Read per event, not in the constructor: this bloc is
  /// mounted above the login route, and a cached identity would freeze the role
  /// across logout/login.
  final AuthenticationService authService;

  /// Incremented on every query and on every abandonment. A response whose id
  /// no longer matches is discarded.
  int _requestId = 0;

  Future<void> _onQueryChanged(
    QueryChangedEvent event,
    Emitter<SearchState> emit,
  ) {
    final parsed = SearchScopeResolver.resolve(
      role: authService.user.userRole,
      location: event.location,
      rawQuery: event.query,
    );

    return _runQuery(scope: parsed.scope, term: parsed.term, emit: emit);
  }

  Future<void> _onFiltersChanged(
    FiltersChangedEvent event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(filters: event.filters));

    // Re-query the scope and term already resolved. Re-dispatching
    // `QueryChangedEvent` would re-resolve `state.term`, which is
    // prefix-stripped — an admin's `products: acme` at `/payment-center` would
    // silently flip back to the clients scope and carry the offer facets there.
    return _runQuery(scope: state.scope, term: state.term, emit: emit);
  }

  Future<void> _runQuery({
    required SearchScope scope,
    required String term,
    required Emitter<SearchState> emit,
  }) async {
    if (SearchTokenizer.normalize(term).length < SearchTokenizer.minPrefix) {
      // Abandon anything in flight too: without this, results for a query the
      // user has just erased land on top of the `tooShort` state.
      _requestId++;
      emit(
        state.copyWith(status: SearchStatus.tooShort, scope: scope, term: term),
      );

      return;
    }

    emit(
      state.copyWith(status: SearchStatus.loading, scope: scope, term: term),
    );

    final id = ++_requestId;

    try {
      final results = await _searchIndex.query(
        SearchRequest(scope: scope, term: term, filters: state.filters),
      );

      // A newer query started while this one was in flight — drop this result.
      if (id != _requestId) return;

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
