import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_overlay.dart';
import 'package:loooans/utils/debounce.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// The app-bar search entry point, and the host of the results overlay.
///
/// Owns the debounce — the bloc deliberately does not. `pubspec.yaml` pins
/// `bloc: ^8.1.3` with no `bloc_concurrency`, and a `Debounce.run` inside a
/// handler would `emit` after the handler returned, which bloc 8 rejects. The
/// timer is cancelled when the state is disposed, so a query the user has
/// navigated away from never reaches the bloc.
///
/// It also owns the overlay's `OverlayEntry`. The panel has to live above the
/// Navigator to escape the app bar's 120px toolbar, which means it cannot be a
/// child of this widget and cannot inherit its providers — hence the explicit
/// `LayerLink` and `BlocProvider.value` below.
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
  final _focusNode = FocusNode();
  final _link = LayerLink();

  /// Shared by the field and the panel so a tap on either counts as inside.
  /// Without it, clicking a result would register as a tap outside the field
  /// and tear the panel down before the row could report the tap.
  final _tapGroup = Object();

  OverlayEntry? _entry;

  static const double _fieldWidth = 280;

  /// Matches the circular icon buttons beside it. The app bar's toolbar is
  /// 120px (`layout_widgets.dart:43`) and without an explicit height the field
  /// renders at the full 120, towering over those buttons — measured, not
  /// eyeballed, and pinned by a test. Wrapping in `Center` does NOT fix it;
  /// only constraining the height does.
  static const double _fieldHeight = 48;

  /// Wider than the field: an offer row carries a company, a rate, an amount
  /// and a term, and 280px wraps all of it.
  static const double _overlayWidth = 360;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _hide();
    _focusNode.dispose();
    _debounce.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) _show();
  }

  void _onChanged(String value) {
    // Not inside the debounce: the panel should follow the keystroke, not the
    // pause. It renders nothing while the status is still `idle`.
    _show();

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

  void _show() {
    if (_entry != null) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final bloc = context.read<SearchBloc>();

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: _overlayWidth,
        child: CompositedTransformFollower(
          link: _link,
          // Anchored right: the field sits near the right edge of the app bar,
          // so a panel wider than it has to grow leftwards or run off-screen.
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, AppSpacing.xs),
          child: TapRegion(
            groupId: _tapGroup,
            onTapOutside: (_) => _hide(),
            child: BlocProvider<SearchBloc>.value(
              value: bloc,
              child: SearchOverlay(onDismiss: _dismiss),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  /// Escape leaves the caret where it is — the user is dismissing the results,
  /// not abandoning the query. A row or "See all" takes the focus with it,
  /// because the surface the user is about to land on owns it now.
  void _dismiss() {
    _hide();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // Compact goes to `/search` rather than expanding in place: the panel would
    // cover the whole phone screen anyway, and `/search` is the same thing with
    // scope tabs, filters, a back button and a URL.
    if (getScreenSize(context: context) == ScreenSize.compact) {
      return IconButton(
        tooltip: 'Search',
        onPressed: () => GoRouter.maybeOf(context)?.go(Paths.search),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.black,
        ),
        icon: const Icon(Icons.search_rounded),
      );
    }

    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _tapGroup,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _hide},
          child: SizedBox(
            width: _fieldWidth,
            height: _fieldHeight,
            child: BlocBuilder<SearchBloc, SearchState>(
              buildWhen: (previous, current) => previous.scope != current.scope,
              builder: (context, state) => TextField(
                controller: _controller,
                focusNode: _focusNode,
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
                  suffixIcon: _badge(),
                  border: OutlineInputBorder(
                    borderRadius: defaultBorderRadius,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _badge() {
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
