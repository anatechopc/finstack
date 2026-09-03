import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loooans/services/authentication_service.dart';

/// Binds the `Ctrl K` / `⌘K` accelerator the app-bar badge advertises
/// (`SearchField`'s shortcut badge).
///
/// It is mounted above the router, in `app.dart`, rather than per route. That
/// is the only place that reaches the screens outside the `ShellRoute` —
/// `/clients/:action`, `/loans/:action`, `/offers/:action` and the rest build
/// their own scaffolds and never see `AppWidgets.defaultAppBar`.
///
/// Sitting that high also puts it over the three pre-auth routes, hence the
/// guard: on `/login`, `/register` and `/set-password`
/// `AuthenticationService.user` throws `Please login`, and `SearchScreen`
/// reads the role on its first build. `isLoggedIn` is the same predicate the
/// app bar's `!showSignUp && !showLogin` reduces to (`HomeScreen` passes
/// `user.isPlaceholder`), plus the null case those screens are in.
///
/// It also sits over every modal dialog. Key events bubble up from the
/// dialog's focus scope, so without the [navigatorKey] guard `Ctrl K` inside
/// an open dialog navigated the page underneath to `/search` and left the
/// dialog stranded on top of it. `canPop()` on the root navigator is the
/// "something is on top of the page" test.
///
/// `CallbackShortcuts` over `Shortcuts` + `Actions`: there is one binding with
/// no intent worth naming, and it is what `SearchField` already uses for
/// Escape.
class SearchShortcutWrapper extends StatelessWidget {
  const SearchShortcutWrapper({
    required this.onActivate,
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final VoidCallback onActivate;
  final Widget child;

  /// The root navigator. Passed in rather than looked up because the one
  /// production mount is above the `Router`, where `Navigator.of` finds
  /// nothing.
  final GlobalKey<NavigatorState> navigatorKey;

  static const control = SingleActivator(
    LogicalKeyboardKey.keyK,
    control: true,
  );

  /// macOS and iOS send meta, not control. A bare `k` is deliberately not
  /// bound — it would swallow the letter in every text field in the app.
  static const meta = SingleActivator(LogicalKeyboardKey.keyK, meta: true);

  void _activate() {
    if (!AuthenticationService.instance.isLoggedIn) return;
    if (navigatorKey.currentState?.canPop() ?? false) return;

    onActivate();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {control: _activate, meta: _activate},
      child: child,
    );
  }
}
