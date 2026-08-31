import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// The app-bar results dropdown: a preview of the first [maxItems] rows and a
/// way through to `/search`, which is the surface that shows the rest.
///
/// It reads the same `SearchBloc` the field writes to, so it needs no query
/// state of its own. `SearchField` mounts it in an `OverlayEntry` and owns the
/// dismissal; this widget only says when a dismissal is due.
class SearchOverlay extends StatelessWidget {
  const SearchOverlay({required this.onDismiss, super.key});

  /// A preview, not the result set. Everything past this lives on `/search`.
  static const int maxItems = 5;

  /// Tall enough for [maxItems] rows plus the "See all" row; the panel floats
  /// over the page, so it must not grow to the height of the result list.
  static const double maxHeight = 400;

  /// Tears down the entry the field mounted this in. The entry sits above the
  /// Navigator, so a row that navigated without calling this would leave the
  /// dropdown floating over the route it navigated to.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        // Nothing typed yet: no panel, no shadow, no empty white box under an
        // app bar the user has merely focused.
        if (state.status == SearchStatus.idle) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          borderRadius: defaultBorderRadius,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: maxHeight),
            child: _body(context, state),
          ),
        );
      },
    );
  }

  /// Branches on status, never on `results.isEmpty`: `SearchStatus.tooShort`
  /// and `SearchStatus.loading` both leave the previous `state.results` in
  /// place, so a status-blind body would render results for a query the user
  /// has just erased.
  Widget _body(BuildContext context, SearchState state) {
    switch (state.status) {
      case SearchStatus.idle:
      case SearchStatus.tooShort:
        return _message(
          'Keep typing — ${SearchTokenizer.minPrefix} characters minimum.',
        );
      case SearchStatus.loading:
        return const _Skeleton();
      case SearchStatus.empty:
        return _message(state.emptyCopy);
      case SearchStatus.error:
        return _error(context, state);
      case SearchStatus.results:
        return _results(context, state);
    }
  }

  Widget _results(BuildContext context, SearchState state) {
    final items = state.results.items;
    final shown = items.length < maxItems ? items.length : maxItems;

    // Not gated on `hasMore` alone. `hasMore` describes the RAW page before
    // refinement, so seven refined rows out of a page that never filled would
    // otherwise strand rows six and seven with no way to reach them.
    final seeAll = items.length > shown || state.results.hasMore;

    // "See all" is pinned below the list rather than being its last row: five
    // offer rows are taller than [maxHeight], so a scrolling last row is one
    // the user has to find before they can leave for the surface that would
    // have shown them everything.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: shown,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];

              return SearchResultTile(
                item: item,
                // Navigate first, dismiss second: `onDismiss` deactivates this
                // element, and `SearchResultTile.open` needs a live context to
                // reach the router and the `ProductBloc`.
                onTap: () {
                  SearchResultTile.open(context, item);
                  onDismiss();
                },
              );
            },
          ),
        ),
        if (seeAll) ...[
          const Divider(height: 1),
          _seeAll(context, state),
        ],
      ],
    );
  }

  /// No count. `SearchResults` has no total to report — `items.length` is the
  /// survivors of refinement among the first page, so "See all 14 results" is
  /// what 300 matches would render (I10). The row says there is more and
  /// nothing about how much.
  Widget _seeAll(BuildContext context, SearchState state) => ListTile(
        key: const Key('search_overlay_see_all'),
        title: const Text('See all results'),
        trailing: const Icon(Icons.arrow_forward_rounded),
        onTap: () {
          // `state.term` is prefix-stripped and `state.scope` is what the
          // resolver already decided, so `/search` reproduces exactly what the
          // overlay was showing instead of re-deriving it from raw text.
          GoRouter.maybeOf(context)?.go(
            Uri(
              path: Paths.search,
              queryParameters: <String, String>{
                'q': state.term,
                'scope': state.scope.name,
              },
            ).toString(),
          );
          onDismiss();
        },
      );

  /// Retries without touching the term — the field still holds what the user
  /// typed, and clearing it is not a recovery.
  ///
  /// The scope is pinned rather than re-resolved: `state.term` is stripped, so
  /// re-running `products: salary` as `salary` at `/payment-center` would
  /// silently flip an offers search back to clients.
  Widget _error(BuildContext context, SearchState state) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: Text('Something went wrong.')),
            TextButton(
              onPressed: () => context.read<SearchBloc>().add(
                    QueryChangedEvent(
                      state.term,
                      location: GoRouter.maybeOf(context)?.location ?? '',
                      pinnedScope: state.scope,
                    ),
                  ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  static Widget _message(String text) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(text),
      );
}

/// Placeholder rows rather than a spinner: the panel is already open at its
/// row height, and a spinner centred in it reads as a failure state.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  static const _rows = 3;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          _rows,
          (_) => const ListTile(
            leading: CircleAvatar(backgroundColor: Colors.black12),
            title:
                SizedBox(height: 12, child: ColoredBox(color: Colors.black12)),
          ),
        ),
      );
}
