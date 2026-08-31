import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/utils/debounce.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// The app-bar search entry point.
///
/// Owns the debounce — the bloc deliberately does not. `pubspec.yaml` pins
/// `bloc: ^8.1.3` with no `bloc_concurrency`, and a `Debounce.run` inside a
/// handler would `emit` after the handler returned, which bloc 8 rejects. The
/// timer is cancelled when the state is disposed, so a query the user has
/// navigated away from never reaches the bloc.
class SearchField extends StatefulWidget {
  const SearchField({this.showShortcutBadge = true, super.key});

  /// The `Ctrl K` / `⌘K` hint. Never shown on a compact screen: advertising a
  /// shortcut to someone with no keyboard is worse than showing nothing.
  final bool showShortcutBadge;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _debounce = Debounce(milliseconds: 250);
  final _controller = TextEditingController();

  /// Compact only: the icon has no route to send the user to yet, so it opens
  /// the field in place.
  bool _expanded = false;

  @override
  void dispose() {
    _debounce.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce.run(() {
      // `location` is a repo-local GoRouter extension (`extensions.dart:62`).
      // `maybeOf` because the field is also mounted in tests and dialogs that
      // have no router above them; the resolver's route default handles ''.
      context.read<SearchBloc>().add(
            QueryChangedEvent(
              value,
              location: GoRouter.maybeOf(context)?.location ?? '',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    if (isCompact && !_expanded) {
      return IconButton(
        tooltip: 'Search',
        onPressed: () => setState(() => _expanded = true),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.black,
        ),
        icon: const Icon(Icons.search_rounded),
      );
    }

    return SizedBox(
      width: isCompact ? 220 : 280,
      child: BlocBuilder<SearchBloc, SearchState>(
        buildWhen: (previous, current) => previous.scope != current.scope,
        builder: (context, state) => TextField(
          controller: _controller,
          autofocus: isCompact,
          onChanged: _onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.white,
            hintText: switch (state.scope) {
              SearchScope.clients => 'Search clients…',
              SearchScope.offers => 'Search offers…',
            },
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _suffix(isCompact),
            border: OutlineInputBorder(
              borderRadius: defaultBorderRadius,
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _suffix(bool isCompact) {
    if (isCompact) {
      return IconButton(
        tooltip: 'Close search',
        onPressed: () {
          _controller.clear();
          setState(() => _expanded = false);
        },
        icon: const Icon(Icons.close_rounded),
      );
    }

    if (!widget.showShortcutBadge) return null;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Center(
        widthFactor: 1,
        child: Text(
          Theme.of(context).platform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K',
          style: TextStyle(
            fontSize: AppTypography.bodySmall,
            color: AppColors.black.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
