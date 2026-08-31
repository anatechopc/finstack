import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/widget/search_app_bar_action.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/features/users/screens/loan_client_detail.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockAuthenticationService extends Mock
    implements AuthenticationService {}

void main() {
  late _MockAuthenticationService auth;

  setUp(() {
    auth = _MockAuthenticationService();
    when(() => auth.isLoggedIn).thenReturn(true);
    // Process-wide singleton: a previous test's user would leak into the
    // pre-auth case below.
    AuthenticationService.instance.dispose();
  });

  Future<bool> pumpAndPress(
    WidgetTester tester,
    LogicalKeyboardKey modifier, {
    AuthenticationService? authService,
  }) async {
    var opened = false;
    await tester.pumpApp(
      SearchShortcutWrapper(
        onActivate: () => opened = true,
        authService: authService,
        // A focusable child: key events dispatch from the primary focus
        // upwards, so with nothing focused below the wrapper its handler is
        // never reached. Every real route puts a focus scope here.
        child: const Scaffold(body: Focus(autofocus: true, child: SizedBox())),
      ),
    );

    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();

    return opened;
  }

  group('SearchShortcutWrapper', () {
    testWidgets('Ctrl+K opens search', (tester) async {
      expect(
        await pumpAndPress(
          tester,
          LogicalKeyboardKey.controlLeft,
          authService: auth,
        ),
        isTrue,
      );
    });

    testWidgets('Cmd+K opens search', (tester) async {
      expect(
        await pumpAndPress(
          tester,
          LogicalKeyboardKey.metaLeft,
          authService: auth,
        ),
        isTrue,
      );
    });

    testWidgets('does not fire pre-auth, where there is no user',
        (tester) async {
      // No injection: this is the real singleton in the state the login,
      // register and set-password screens leave it in. The wrapper sits above
      // the router, so it covers those routes too.
      //
      // `onActivate` reproduces the actual crash rather than flipping a flag:
      // reaching `/search` builds `SearchScreen`, whose first statement is
      // `authService.user.userRole` (`search_screen.dart:111`), and
      // `AuthenticationService.user` throws `Please login` with no user set
      // (`authentication_service.dart:16-22`). A flag-only assertion would go
      // green against a wrapper that fires and crashes.
      var opened = false;
      String? role;

      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.pumpApp(
          SearchShortcutWrapper(
            onActivate: () {
              opened = true;
              role = AuthenticationService.instance.user.userRole.toString();
            },
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        );

        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();

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
      when(() => auth.isLoggedIn).thenReturn(false);

      expect(
        await pumpAndPress(
          tester,
          LogicalKeyboardKey.controlLeft,
          authService: auth,
        ),
        isFalse,
      );
    });

    testWidgets('does not hijack a literal k typed into a text field',
        (tester) async {
      var opened = false;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpApp(
        SearchShortcutWrapper(
          onActivate: () => opened = true,
          authService: auth,
          child: Scaffold(
            body: TextField(controller: controller, autofocus: true),
          ),
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
      var opened = false;

      await tester.pumpApp(
        SearchShortcutWrapper(
          onActivate: () => opened = true,
          authService: auth,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

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
      // `dialog_widgets.dart:196` mounts the same widget — app bar included —
      // inside a dialog that already sits under the shell's `SearchField`.
      // Only `router.dart`'s `/clients/:action` opts in.
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
