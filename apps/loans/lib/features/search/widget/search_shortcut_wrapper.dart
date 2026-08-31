import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loooans/services/authentication_service.dart';

/// Binds the `Ctrl K` / `⌘K` accelerator the app-bar badge advertises
/// (`search_field.dart:203`).
///
/// It is mounted above the router, in `app.dart`, rather than per route. That
/// is the only place that reaches the screens outside the `ShellRoute` —
/// `/clients/:action`, `/loans/:action`, `/offers/:action` and the rest build
/// their own scaffolds and never see `AppWidgets.defaultAppBar`.
///
/// Sitting that high also puts it over the three pre-auth routes, hence the
/// guard: on `/login`, `/register` and `/set-password`
/// `AuthenticationService.instance.user` throws `Please login`
/// (`authentication_service.dart:16-22`), and `SearchScreen` reads
/// `authService.user.userRole` on its first build. `isLoggedIn` is the same
/// predicate the app bar's `!showSignUp && !showLogin` reduces to
/// (`home_screen.dart:41-42` passes `user.isPlaceholder`), plus the null case
/// those screens are in.
///
/// `CallbackShortcuts` over `Shortcuts` + `Actions`: there is one binding with
/// no intent worth naming, and it is what `SearchField` already uses for
/// Escape (`search_field.dart:162`).
class SearchShortcutWrapper extends StatelessWidget {
  const SearchShortcutWrapper({
    required this.onActivate,
    required this.child,
    this.authService,
    super.key,
  });

  final VoidCallback onActivate;
  final Widget child;

  /// Injected in tests. Defaults to the app-wide instance rather than taking
  /// it as required, because the one production call site is above every
  /// provider.
  final AuthenticationService? authService;

  static const _control = SingleActivator(
    LogicalKeyboardKey.keyK,
    control: true,
  );

  /// macOS and iOS send meta, not control. A bare `k` is deliberately not
  /// bound — it would swallow the letter in every text field in the app.
  static const _meta = SingleActivator(LogicalKeyboardKey.keyK, meta: true);

  void _activate() {
    if (!(authService ?? AuthenticationService.instance).isLoggedIn) return;

    onActivate();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {_control: _activate, _meta: _activate},
      child: child,
    );
  }
}
