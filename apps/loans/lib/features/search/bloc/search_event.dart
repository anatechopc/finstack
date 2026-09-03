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
    this.filters,
    this.candidateLimit,
  });

  final String query;
  final String location;

  /// A scope tab tap, or `/search?scope=`. Handed to `SearchScopeResolver` as a
  /// *request*, never as a decision: the resolver intersects it with the role's
  /// permitted set exactly as it does a typed prefix, so a pin naming a scope
  /// the role lacks is dropped rather than honoured. `router.dart` has no role
  /// gate, which is why the deep link must not mint a scope of its own.
  final SearchScope? pinnedScope;

  /// The offer facets to query with. `null` keeps whatever the state holds;
  /// `const OfferFilters()` clears them. The bloc lives for the whole app, so
  /// a facet set on `/search` would otherwise narrow every later query — the
  /// app-bar overlay included, which has no filter UI to show or clear it. The
  /// field sends empty; the screen sends its chips with every query, which is
  /// also why a deep-linked facet needs no separate [FiltersChangedEvent]
  /// dispatched ahead of the query.
  final OfferFilters? filters;

  /// How many candidates to fetch before refinement — see
  /// [SearchRequest.candidateLimit]. `null` is
  /// [SearchRequest.defaultCandidateLimit]. The overlay shows five rows and
  /// passes a smaller page; the same term later asked with a larger page is
  /// always re-run.
  final int? candidateLimit;
}

/// The user changed an offer facet. Re-queries the scope and term already on
/// the state; it deliberately does **not** re-dispatch [QueryChangedEvent].
final class FiltersChangedEvent extends SearchEvent {
  const FiltersChangedEvent(this.filters);

  final OfferFilters filters;
}

/// The session ended. Returns the bloc to its initial state — results erased,
/// facets cleared, any in-flight response dropped, the default scope
/// re-derived from whoever is (or is not) signed in now — so the next account
/// to focus the field never sees this one's client rows.
final class SearchClearedEvent extends SearchEvent {
  const SearchClearedEvent();
}
