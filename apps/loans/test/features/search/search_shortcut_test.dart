import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/widget/search_app_bar_action.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/features/users/screens/loan_client_detail.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:user_repository/user_repository.dart';

User _admin() => User()
  ..id = 'user-1'
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  ..userRole = UserRole.admin;

void main() {
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
    // Process-wide singleton: a previous test's user would leak into the
    // pre-auth case below.
    AuthenticationService.instance.dispose();
  });

  /// The wrapper above a `MaterialApp` whose root navigator it holds the key
  /// to — the shape `app.dart` gives it.
  Future<void> pumpWrapper(
    WidgetTester tester, {
    required VoidCallback onActivate,
    required Widget child,
  }) =>
      tester.pumpWidget(
        SearchShortcutWrapper(
          navigatorKey: navigatorKey,
          onActivate: onActivate,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
        ),
      );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey modifier) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  Future<bool> pumpAndPress(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
  ) async {
    var opened = false;
    await pumpWrapper(
      tester,
      onActivate: () => opened = true,
      // A focusable child: key events dispatch from the primary focus
      // upwards, so with nothing focused below the wrapper its handler is
      // never reached. Every real route puts a focus scope here.
      child: const Scaffold(body: Focus(autofocus: true, child: SizedBox())),
    );
    await press(tester, modifier);

    return opened;
  }

  group('SearchShortcutWrapper', () {
    testWidgets('Ctrl+K opens search', (tester) async {
      AuthenticationService.instance.user = _admin();

      expect(
        await pumpAndPress(tester, LogicalKeyboardKey.controlLeft),
        isTrue,
      );
    });

    testWidgets('Cmd+K opens search', (tester) async {
      AuthenticationService.instance.user = _admin();

      expect(await pumpAndPress(tester, LogicalKeyboardKey.metaLeft), isTrue);
    });

    testWidgets('does not fire pre-auth, where there is no user',
        (tester) async {
      // The singleton is in the state the login, register and set-password
      // screens leave it in. The wrapper sits above the router, so it covers
      // those routes too.
      //
      // `onActivate` reproduces the actual crash rather than flipping a flag:
      // reaching `/search` builds `SearchScreen`, whose first statement reads
      // `AuthenticationService.instance.user.userRole`, and
      // `AuthenticationService.user` throws `Please login` with no user set.
      // A flag-only assertion would go green against a wrapper that fires
      // and crashes.
      var opened = false;
      String? role;

      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await pumpWrapper(
          tester,
          onActivate: () {
            opened = true;
            role = AuthenticationService.instance.user.userRole.toString();
          },
          child: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox()),
          ),
        );
        await press(tester, modifier);

        // Exception first: with the guard gone the framework catches the
        // `Please login` throw inside the key message handler and parks it
        // here, so this is the assertion that names the crash.
        expect(tester.takeException(), isNull);
        expect(opened, isFalse, reason: '$modifier fired the shortcut');
        expect(role, isNull);
      }
    });

    testWidgets('does not fire for a placeholder (pre-login) browser',
        (tester) async {
      AuthenticationService.instance.user =
          User.createPlaceholder(lastName: 'Guest');

      expect(
        await pumpAndPress(tester, LogicalKeyboardKey.controlLeft),
        isFalse,
      );
    });

    // Key events bubble up from the dialog's focus scope, so the wrapper
    // sees them. Firing would navigate the page underneath to `/search` and
    // leave the dialog stranded on top of it.
    testWidgets('does nothing while a dialog is open', (tester) async {
      AuthenticationService.instance.user = _admin();
      var opened = 0;

      await pumpWrapper(
        tester,
        onActivate: () => opened++,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  content: Focus(autofocus: true, child: Text('modal')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.controlLeft);

      expect(opened, 0);
      expect(find.text('modal'), findsOneWidget);

      // Closed again, the shortcut is back.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.controlLeft);

      expect(opened, 1);
    });

    testWidgets('does not hijack a literal k typed into a text field',
        (tester) async {
      AuthenticationService.instance.user = _admin();
      var opened = false;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpWrapper(
        tester,
        onActivate: () => opened = true,
        child: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'kayla');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      expect(opened, isFalse);
      expect(controller.text, 'kayla');
    });

    testWidgets('still fires while a text field has focus', (tester) async {
      AuthenticationService.instance.user = _admin();
      var opened = false;

      await pumpWrapper(
        tester,
        onActivate: () => opened = true,
        child: const Scaffold(body: TextField(autofocus: true)),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.controlLeft);

      expect(opened, isTrue);
    });
  });

  group('SearchAppBarAction', () {
    // The visible half of the affordance. `/clients/:action` and
    // `/loans/:action` build their own scaffolds and never see `SearchField`,
    // so this button is the only pointer-reachable way into search there.
    testWidgets('navigates to /search from an out-of-shell route',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/clients/client-1',
        routes: [
          GoRoute(
            path: Paths.clientsAction,
            builder: (_, __) => const Scaffold(
              appBar: _StubAppBar(),
              body: Text('client detail'),
            ),
          ),
          GoRoute(
            path: Paths.loansAction,
            builder: (_, __) => const Scaffold(
              appBar: _StubAppBar(),
              body: Text('loan detail'),
            ),
          ),
          GoRoute(
            path: Paths.search,
            builder: (_, __) => const Scaffold(body: Text('search page')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('client detail'), findsOneWidget);

      await tester.tap(find.byType(SearchAppBarAction));
      await tester.pumpAndSettle();

      expect(find.text('search page'), findsOneWidget);

      router.go('/loans/loan-1');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SearchAppBarAction));
      await tester.pumpAndSettle();

      expect(find.text('search page'), findsOneWidget);
    });

    test('LoanClientDetail keeps the action off by default', () {
      // `DialogWidgets.showLoanClientDetail` mounts the same widget — app bar
      // included — inside a dialog that already sits under the shell's
      // `SearchField`. Only `router.dart`'s `/clients/:action` opts in.
      expect(
        const LoanClientDetail(userId: 'user-1').showSearchAction,
        isFalse,
      );
    });
  });
}

/// Stands in for the two screens' own app bars, which need five mocked blocs
/// and two repositories to mount. What is under test here is the button's
/// wiring, not their layout.
class _StubAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _StubAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(actions: const [SearchAppBarAction()]);
}
