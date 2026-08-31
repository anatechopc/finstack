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
  const QueryChangedEvent(this.query, {required this.location});

  final String query;
  final String location;
}

/// The user changed an offer facet. Re-queries the scope and term already on
/// the state; it deliberately does **not** re-dispatch [QueryChangedEvent].
final class FiltersChangedEvent extends SearchEvent {
  const FiltersChangedEvent(this.filters);

  final OfferFilters filters;
}
