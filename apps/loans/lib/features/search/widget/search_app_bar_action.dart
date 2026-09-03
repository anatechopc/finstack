import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';

/// The visible search affordance for screens that build their own `AppBar`
/// instead of `AppWidgets.defaultAppBar` — the routes outside the `ShellRoute`
/// (`/clients/:action`, `/loans/:action`), which never see `SearchField` — and
/// what `SearchField` itself collapses to when the app bar is too narrow.
///
/// `Ctrl K` already reaches them via `SearchShortcutWrapper`, but a shortcut
/// with no visible control is keyboard-only. It goes to `/search` rather than
/// opening the overlay: the overlay is anchored to the app-bar field that
/// these screens do not have.
class SearchAppBarAction extends StatelessWidget {
  const SearchAppBarAction({this.style, super.key});

  /// The shell app bar's circular white buttons pass their style; the
  /// out-of-shell app bars take the default.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Search',
      style: style,
      icon: const Icon(Icons.search_rounded),
      onPressed: () => GoRouter.of(context).go(Paths.search),
    );
  }
}
