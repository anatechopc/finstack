import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/features/search/widget/offer_filter_bar.dart';
import 'package:loooans/features/search/widget/search_field.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:user_repository/user_repository.dart';

/// The `/search` page: the deep-linkable surface, beside the app-bar overlay.
///
/// It renders `SearchField` in its page dressing — no overlay, full width —
/// and owns the field's controller, because a scope tap has to read the text
/// back and a deep-link change has to overwrite it.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.initialQuery,
    required this.initialFilters,
    this.initialScopeParam,
    super.key,
  });

  /// The only mapping from `/search`'s query parameters to this screen.
  ///
  /// `interest` is deliberately not read: `OfferFilters` has no such field,
  /// the query it would build is rejected by Firestore, and no environment
  /// indexes `interest_rate` (finstack#103). Parsing it would put the crash
  /// back within reach of a deep link even with the chip gone.
  factory SearchScreen.fromQueryParameters(Map<String, String> params) =>
      SearchScreen(
        initialQuery: params[Paths.paramSearchQuery] ?? '',
        initialScopeParam: params[Paths.paramSearchScope],
        initialFilters: OfferFilters(
          companyId: params[Paths.paramSearchCompany],
          term: params[Paths.paramSearchTerm],
        ),
      );

  final String initialQuery;
  final OfferFilters initialFilters;

  /// The raw `?scope=` string, never a `SearchScope`. Minting the enum here
  /// would be the one place a scope is chosen without `SearchScopeResolver`,
  /// and `router.dart` has no role gate to make that safe.
  final String? initialScopeParam;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);

  SearchScope? _pinnedScope;

  @override
  void initState() {
    super.initState();
    _syncWithRoute();
  }

  /// go_router keys the page by path, so `/search?q=a` → `/search?q=b` — a
  /// second "See all", `Ctrl K` from the app bar, browser Back — arrives here
  /// as new props on the same state, not as a remount. Without this the field,
  /// the pin and the facets all kept showing the previous link.
  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialQuery == oldWidget.initialQuery &&
        widget.initialScopeParam == oldWidget.initialScopeParam &&
        widget.initialFilters == oldWidget.initialFilters) {
      return;
    }

    _controller.text = widget.initialQuery;
    _syncWithRoute();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncWithRoute() {
    // Matched on `name`, the deep-link spelling (`SearchScope` says so);
    // `aliases` are what a user types before a colon. An unrecognised value
    // stays null and the role's route default applies.
    _pinnedScope = SearchScope.values
        .firstWhereOrNull((scope) => scope.name == widget.initialScopeParam);

    // ONE event, facets riding on it. A `FiltersChangedEvent` dispatched
    // ahead of the query re-ran the PREVIOUS term with the new facets — a
    // billed read, and a flash of the wrong results.
    _dispatchQuery(filters: widget.initialFilters);
  }

  /// `location` is hardcoded because this widget only ever renders at
  /// `Paths.search`; reading it back off the router would buy nothing and
  /// would fail in tests that mount the screen without one. A null [filters]
  /// keeps the chips the bloc already holds.
  void _dispatchQuery({OfferFilters? filters}) {
    context.read<SearchBloc>().add(
          QueryChangedEvent(
            _controller.text,
            location: Paths.search,
            pinnedScope: _pinnedScope,
            filters: filters,
          ),
        );
  }

  void _onScopeTapped(SearchScope scope) {
    setState(() => _pinnedScope = scope);
    _dispatchQuery();
  }

  @override
  Widget build(BuildContext context) {
    final role = AuthenticationService.instance.user.userRole;
    final permitted = SearchScopeResolver.scopesFor(role);
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        backgroundColor: AppColors.green1,
        centerTitle: false,
      ),
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) => Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The chips the bloc holds ride on every typed query, so a
              // facet never has to be re-sent ahead of the term it narrows.
              SearchField(
                controller: _controller,
                pinnedScope: _pinnedScope,
                filters: state.filters,
                showOverlay: false,
                showShortcutBadge: false,
                autofocus: true,
              ),
              // A single-scope role gets no tab row: one tab is a control with
              // nothing to switch to.
              if (permitted.length > 1) ...[
                const Gap(AppSpacing.sm),
                _scopeTabs(permitted, state.scope),
              ],
              if (state.scope == SearchScope.offers) ...[
                const Gap(AppSpacing.sm),
                OfferFilterBar(
                  filters: state.filters,
                  showCompanyChip:
                      !UserRole.companyManagedRoles.contains(role),
                  onChanged: (filters) => context.read<SearchBloc>().add(
                        FiltersChangedEvent(filters),
                      ),
                ),
              ],
              const Gap(AppSpacing.md),
              Expanded(child: _body(state)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeTabs(Set<SearchScope> permitted, SearchScope active) => Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final scope in SearchScope.values)
            if (permitted.contains(scope))
              ChoiceChip(
                key: Key('search_scope_${scope.name}'),
                label: Text(_scopeLabel(scope)),
                selected: scope == active,
                onSelected: (_) => _onScopeTapped(scope),
              ),
        ],
      );

  /// Branches on status, never on `results.isEmpty`: `SearchStatus.tooShort`
  /// deliberately leaves `state.results` alone, so a status-blind body would
  /// render the results of a query the user has just erased.
  Widget _body(SearchState state) {
    switch (state.status) {
      case SearchStatus.idle:
      case SearchStatus.tooShort:
        // Filters narrow a token search; they never issue one. Every offers
        // query must carry a `search_tokens` clause — a filter-only query has
        // no index and would be a dead end even with one.
        return _message(
          state.filters.isEmpty
              ? 'Type at least ${SearchTokenizer.minPrefix} characters to '
                  'search.'
              : 'Add a search term to apply these filters.',
        );
      case SearchStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case SearchStatus.error:
        return _message('Something went wrong. Try searching again.');
      case SearchStatus.empty:
        return _message(state.emptyCopy);
      case SearchStatus.results:
        return _results(state.results);
    }
  }

  Widget _results(SearchResults results) => ListView.separated(
        itemCount: results.items.length + (results.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          // `SearchResults` carries no total, only `hasMore` — set from the raw
          // page before refinement. A "See all N" would report the survivors of
          // refinement among the first page and read "14" for 300 matches.
          // v1 caps both surfaces and does not paginate; saying so is the
          // honest version.
          if (index == results.items.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'More matches exist — narrow your search to see them.',
              ),
            );
          }

          final item = results.items[index];

          return SearchResultTile(
            item: item,
            onTap: () => SearchResultTile.open(context, item),
          );
        },
      );

  static Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  static String _scopeLabel(SearchScope scope) => switch (scope) {
        SearchScope.clients => 'Clients',
        SearchScope.offers => 'Offers',
      };
}
