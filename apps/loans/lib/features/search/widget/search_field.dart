import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_app_bar_action.dart';
import 'package:loooans/features/search/widget/search_overlay.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/utils/debounce.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// The search input, in two dressings: the app-bar entry point that hosts the
/// results overlay (the default), and the full-width field on `/search`
/// (`showOverlay: false`), which `SearchScreen` drives through [controller],
/// [pinnedScope] and [filters].
///
/// Owns the debounce — the bloc deliberately does not. `pubspec.yaml` pins
/// `bloc: ^8.1.3` with no `bloc_concurrency`, and a `Debounce.run` inside a
/// handler would `emit` after the handler returned, which bloc 8 rejects. The
/// timer is cancelled when the state is disposed, so a query the user has
/// navigated away from never reaches the bloc.
///
/// It also owns the overlay's `OverlayEntry`. The panel has to live above the
/// Navigator to escape the app bar's 120px toolbar, which means it cannot be a
/// child of this widget — hence the explicit `LayerLink`. It still sees the
/// blocs: `AppBlocProviders` sits above `MaterialApp` in `app.dart`, so the
/// root `Overlay` inherits them.
class SearchField extends StatefulWidget {
  const SearchField({
    this.controller,
    this.pinnedScope,
    this.filters = const OfferFilters(),
    this.showOverlay = true,
    this.showShortcutBadge = true,
    this.autofocus = false,
    super.key,
  });

  /// Supplied by `SearchScreen`, which has to read the text back on a scope
  /// tap and overwrite it on a deep-link change. Null means the field owns
  /// one.
  final TextEditingController? controller;

  /// Carried on every query this field dispatches. The app bar pins nothing;
  /// `/search` pins its active tab.
  final SearchScope? pinnedScope;

  /// Carried on every query this field dispatches. The app bar sends the
  /// default — empty — because it has no facet UI to show or clear, and the
  /// bloc lives for the whole app: a facet left over from `/search` would
  /// otherwise silently narrow every overlay query after it.
  final OfferFilters filters;

  /// The app-bar variant: mounts the results panel, collapses to an icon when
  /// the app bar is narrow, and asks for the panel-sized candidate page.
  /// `false` on `/search`, where the page itself is the results surface.
  final bool showOverlay;

  /// The `Ctrl K` / `⌘K` hint. Never shown on a compact screen: advertising a
  /// shortcut to someone with no keyboard is worse than showing nothing.
  final bool showShortcutBadge;

  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _debounce = Debounce(milliseconds: 250);
  late final _controller = widget.controller ?? TextEditingController();
  final _focusNode = FocusNode();
  final _link = LayerLink();

  /// Shared by the field and the panel so a tap on either counts as inside.
  /// Without it, clicking a result would register as a tap outside the field
  /// and tear the panel down before the row could report the tap.
  final _tapGroup = Object();

  OverlayEntry? _entry;

  /// The router, listened to for the life of the field. The panel is an
  /// `OverlayEntry`, so a navigation the panel did not cause — `Ctrl K`, a
  /// keyboard-driven route change, browser Back — would otherwise leave it
  /// floating over the next page.
  Listenable? _router;

  static const double _fieldWidth = 280;

  /// Matches the circular icon buttons beside it. The app bar's toolbar is
  /// 120px (`LayoutWidgets.defaultAppBar`) and without an explicit height the
  /// field renders at the full 120, towering over those buttons — measured,
  /// not eyeballed, and pinned by a test. Wrapping in `Center` does NOT fix
  /// it; only constraining the height does.
  static const double _fieldHeight = 48;

  /// Wider than the field: an offer row carries a company, a rate, an amount
  /// and a term, and 280px wraps all of it.
  static const double _overlayWidth = 360;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _router = GoRouter.maybeOf(context)?.routerDelegate;
    _router?.addListener(_hide);
  }

  @override
  void dispose() {
    _router?.removeListener(_hide);
    _hide();
    _focusNode.dispose();
    _debounce.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Focus alone opens nothing. The bloc outlives the session, and with the
  /// text empty the only thing the panel could show is whatever the last
  /// query — possibly another account's — left on the state.
  void _onFocusChanged() {
    if (_focusNode.hasFocus && _controller.text.isNotEmpty) _show();
  }

  void _onChanged(String value) {
    // Not inside the debounce: the panel should follow the keystroke, not the
    // pause. It renders nothing while the status is still `idle`.
    if (value.isEmpty) {
      _hide();
    } else {
      _show();
    }

    _debounce.run(() {
      // `location` is a repo-local GoRouter extension (`SafeNavigation`).
      // `maybeOf` because the field is also mounted in tests and dialogs that
      // have no router above them; the resolver's route default handles ''.
      context.read<SearchBloc>().add(
            QueryChangedEvent(
              value,
              location: GoRouter.maybeOf(context)?.location ?? '',
              pinnedScope: widget.pinnedScope,
              filters: widget.filters,
              candidateLimit:
                  widget.showOverlay ? SearchOverlay.candidateLimit : null,
            ),
          );
    });
  }

  void _show() {
    if (!widget.showOverlay || _entry != null) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: _overlayWidth,
        child: CompositedTransformFollower(
          link: _link,
          // A resize that collapses the field to an icon unlinks the panel;
          // painting it unlinked put it at the window's origin.
          showWhenUnlinked: false,
          // Anchored right: the field sits near the right edge of the app bar,
          // so a panel wider than it has to grow leftwards or run off-screen.
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, AppSpacing.xs),
          child: TapRegion(
            groupId: _tapGroup,
            onTapOutside: (_) => _hide(),
            child: SearchOverlay(onDismiss: _dismiss),
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

  /// `Ctrl K` while this field has focus. Bound here as well as in
  /// `SearchShortcutWrapper` because the inner binding wins: the root one
  /// goes to a bare `/search` and would discard what has been typed.
  ///
  /// On `/search` itself there is nowhere to go; swallowing the key keeps the
  /// root binding from re-navigating and wiping the query and its filters.
  void _onShortcut() {
    if (!widget.showOverlay) return;

    final text = _controller.text;
    GoRouter.maybeOf(context)?.go(
      Uri(
        path: Paths.search,
        queryParameters: text.isEmpty
            ? null
            : <String, String>{Paths.paramSearchQuery: text},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showOverlay) return _shortcuts(_textField());

    // Compact and medium go to `/search` rather than expanding in place: the
    // panel would cover a phone screen anyway, and `/search` is the same
    // thing with scope tabs, filters, a back button and a URL. Medium is
    // included because at 600–839px the field plus the admin buttons need
    // ~950px of actions row and overflowed it.
    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      return SearchAppBarAction(
        style: IconButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.black,
        ),
      );
    }

    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _tapGroup,
        child: _shortcuts(
          SizedBox(
            width: _fieldWidth,
            height: _fieldHeight,
            child: _textField(),
          ),
        ),
      ),
    );
  }

  Widget _shortcuts(Widget child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _hide,
          SearchShortcutWrapper.control: _onShortcut,
          SearchShortcutWrapper.meta: _onShortcut,
        },
        child: child,
      );

  Widget _textField() => BlocBuilder<SearchBloc, SearchState>(
        buildWhen: (previous, current) => previous.scope != current.scope,
        builder: (context, state) => TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
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
      );

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
