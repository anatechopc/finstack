part of 'search_bloc.dart';

sealed class SearchEvent {
  const SearchEvent();
}

/// The user changed the query text. [location] is the current route, which the
/// resolver uses to pick a default scope when the query carries no prefix.
///
/// Emitted once per typing pause, not per keystroke — the debounce lives in
/// `SearchField`, not here: bloc 8 rejects an `emit` made after its handler
/// returned, which is exactly what a `Debounce.run` inside a handler would do.
final class QueryChangedEvent extends SearchEvent {
  const QueryChangedEvent(
    this.query, {
    required this.location,
    this.pinnedScope,
  });

  final String query;
  final String location;

  /// A scope tab tap, or `/search?scope=`. Handed to `SearchScopeResolver` as a
  /// *request*, never as a decision: the resolver intersects it with the role's
  /// permitted set exactly as it does a typed prefix, so a pin naming a scope
  /// the role lacks is dropped rather than honoured. `router.dart` has no role
  /// gate, which is why the deep link must not mint a scope of its own.
  final SearchScope? pinnedScope;
}

/// The user changed an offer facet. Re-queries the scope and term already on
/// the state; it deliberately does **not** re-dispatch [QueryChangedEvent].
final class FiltersChangedEvent extends SearchEvent {
  const FiltersChangedEvent(this.filters);

  final OfferFilters filters;
}
