import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/view/app.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/index/screens/home_screen.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_app_bar_action.dart';
import 'package:loooans/features/search/widget/search_field.dart';
import 'package:loooans/features/search/widget/search_overlay.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/notification_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/layout_widgets.dart';
import 'package:mocktail/mocktail.dart';
// Prefixed: the package exports a `Notification` that collides with Flutter's.
import 'package:notification_repository/notification_repository.dart' as notif;
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockAuthenticationBloc
    extends MockBloc<AuthenticationEvent, AuthenticationState>
    implements AuthenticationBloc {}

class _MockConversationsBloc
    extends MockBloc<ConversationsEvent, ConversationsState>
    implements ConversationsBloc {}

class _MockNotificationRepository extends Mock
    implements notif.NotificationRepository {}

class _MockSearchIndex extends Mock implements SearchIndex {}

class _MockAuthenticationService extends Mock
    implements AuthenticationService {}

class _FakeSearchRequest extends Fake implements SearchRequest {}

const _wide = Size(1280, 800);
const _medium = Size(700, 800);
const _compact = Size(390, 844);

User _admin() => User()
  ..id = 'user-1'
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  // `late ImageUrl?` on `User` — unset is a LateError, not a null.
  ..profilePhotoUrl = null
  ..userRole = UserRole.admin;

SearchResults _oneClient() => SearchResults(
      items: [
        ClientResultItem(
          user: User()
            ..id = 'user-1'
            ..firstName = 'Juan'
            ..lastName = 'Dela Cruz'
            ..mobileNumber = '09175550142',
          matchedField: 'name',
        ),
      ],
    );

void main() {
  late SearchBloc bloc;

  // `SearchEvent` is sealed, so the fallback is a real event, not a `Fake`.
  setUpAll(() {
    registerFallbackValue(const QueryChangedEvent('', location: ''));
    registerFallbackValue(_FakeSearchRequest());
  });

  setUp(() {
    bloc = _MockSearchBloc();
    when(() => bloc.state).thenReturn(const SearchState());
  });

  /// The bloc sits ABOVE `MaterialApp`, as `AppBlocProviders` does in
  /// `app.dart`: the results panel is an `OverlayEntry` in the root `Overlay`,
  /// and that is where it reads the bloc from.
  Future<void> pumpField(
    WidgetTester tester,
    Widget child, {
    SearchBloc? withBloc,
  }) =>
      tester.pumpWidget(
        BlocProvider<SearchBloc>.value(
          value: withBloc ?? bloc,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
        ),
      );

  Future<void> pumpRouter(
    WidgetTester tester,
    GoRouter router, {
    TransitionBuilder? builder,
  }) =>
      tester.pumpWidget(
        BlocProvider<SearchBloc>.value(
          value: bloc,
          child: MaterialApp.router(routerConfig: router, builder: builder),
        ),
      );

  Widget subject({Size size = _wide, bool showShortcutBadge = true}) =>
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: SearchField(showShortcutBadge: showShortcutBadge),
        ),
      );

  List<QueryChangedEvent> capturedQueries() =>
      verify(() => bloc.add(captureAny()))
          .captured
          .whereType<QueryChangedEvent>()
          .toList();

  Future<void> pressCtrlK(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('renders a text field on a wide screen', (tester) async {
    await pumpField(tester, subject());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  // Collapsed on medium too: at 600–839px the 280px field plus the admin
  // buttons need ~950px of actions row, and 768px overflowed it. The icon is
  // the same widget the out-of-shell app bars use.
  for (final (name, size) in [('compact', _compact), ('medium', _medium)]) {
    testWidgets('collapses to an icon on a $name screen', (tester) async {
      await pumpField(tester, subject(size: size));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SearchAppBarAction), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
    });
  }

  testWidgets('stays a text field at the expanded breakpoint', (tester) async {
    await pumpField(tester, subject(size: const Size(840, 800)));

    expect(find.byType(TextField), findsOneWidget);
  });

  // Task 5 expanded the field in place because `Paths.search` did not exist
  // yet. It does now, and a 360px panel over a 390px phone is `/search` with
  // none of its affordances.
  testWidgets('the compact icon goes to /search', (tester) async {
    final router = GoRouter(
      initialLocation: Paths.index,
      routes: [
        GoRoute(
          path: Paths.index,
          builder: (_, __) => subject(size: _compact),
        ),
        GoRoute(
          path: Paths.search,
          builder: (_, __) => const Scaffold(body: Text('search page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpRouter(tester, router);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(router.location, Paths.search);
    expect(find.text('search page'), findsOneWidget);
  });

  testWidgets('advertises no shortcut on a compact screen', (tester) async {
    await pumpField(tester, subject(size: _compact));

    expect(find.text('Ctrl K'), findsNothing);
    expect(find.text('⌘K'), findsNothing);
  });

  testWidgets('hides the badge when asked to', (tester) async {
    await pumpField(tester, subject(showShortcutBadge: false));

    expect(find.text('Ctrl K'), findsNothing);
  });

  testWidgets('the hint tracks the scope', (tester) async {
    when(() => bloc.state)
        .thenReturn(const SearchState(scope: SearchScope.offers));
    await pumpField(tester, subject());

    expect(find.text('Search offers…'), findsOneWidget);
    expect(find.text('Search clients…'), findsNothing);
  });

  testWidgets('rapid keystrokes coalesce into one query', (tester) async {
    await pumpField(tester, subject());

    final field = find.byType(TextField);
    for (final value in ['d', 'de', 'del', 'dela', 'dela ']) {
      await tester.enterText(field, value);
      await tester.pump(const Duration(milliseconds: 40));
    }

    // Nothing may have been dispatched yet — the pause has not elapsed.
    verifyNever(() => bloc.add(any()));

    await tester.pump(const Duration(milliseconds: 300));

    final queries = capturedQueries();
    expect(queries, hasLength(1));
    expect(queries.single.query, 'dela ');
  });

  testWidgets('a pause between keystrokes dispatches each one', (tester) async {
    await pumpField(tester, subject());

    final field = find.byType(TextField);
    await tester.enterText(field, 'dela');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field, 'cruz');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      capturedQueries().map((event) => event.query),
      ['dela', 'cruz'],
    );
  });

  testWidgets('a pending query is dropped when the field is disposed',
      (tester) async {
    await pumpField(tester, subject());

    await tester.enterText(find.byType(TextField), 'dela');
    await pumpField(tester, const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));

    verifyNever(() => bloc.add(any()));
  });

  // The bloc lives for the whole app and `/search` writes facets to it. The
  // app bar has no facet UI to show or clear, so a term chip picked on
  // `/search` would otherwise silently narrow every overlay query after it.
  testWidgets('every query from the app bar clears the offer facets',
      (tester) async {
    when(() => bloc.state).thenReturn(
      const SearchState(
        scope: SearchScope.offers,
        filters: OfferFilters(companyId: 'company-1', term: '1m'),
      ),
    );
    await pumpField(tester, subject());

    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pump(const Duration(milliseconds: 300));

    expect(capturedQueries().single.filters, const OfferFilters());
  });

  // The panel shows five rows; fetching the default fifty was forty-five
  // billed reads per keystroke for nothing.
  testWidgets('asks for the panel-sized candidate page', (tester) async {
    await pumpField(tester, subject());

    await tester.enterText(find.byType(TextField), 'dela');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      capturedQueries().single.candidateLimit,
      SearchOverlay.candidateLimit,
    );
    expect(SearchOverlay.candidateLimit, lessThan(50));
  });

  group('Ctrl K inside the field', () {
    late GlobalKey<NavigatorState> navigatorKey;
    late GoRouter router;

    setUp(() {
      AuthenticationService.instance.user = _admin();
      navigatorKey = GlobalKey<NavigatorState>();
      router = GoRouter(
        navigatorKey: navigatorKey,
        initialLocation: Paths.index,
        routes: [
          GoRoute(path: Paths.index, builder: (_, __) => subject()),
          GoRoute(
            path: Paths.search,
            builder: (_, __) => const Scaffold(body: Text('search page')),
          ),
        ],
      );
      addTearDown(router.dispose);
    });

    /// The root binding is mounted exactly as `app.dart` mounts it, so the
    /// test proves the field's binding wins over it — not merely that the
    /// field has one.
    Future<void> pumpWithRootShortcut(WidgetTester tester) => pumpRouter(
          tester,
          router,
          builder: (_, child) => SearchShortcutWrapper(
            navigatorKey: navigatorKey,
            onActivate: () => router.go(Paths.search),
            child: child!,
          ),
        );

    testWidgets('carries the typed text to /search', (tester) async {
      await pumpWithRootShortcut(tester);
      await tester.enterText(find.byType(TextField), 'dela');

      await pressCtrlK(tester);

      // The root binding alone would land on a bare `/search`, discarding
      // what was typed.
      expect(router.location, '/search?q=dela');
      expect(find.text('search page'), findsOneWidget);
    });

    testWidgets('still goes to /search when nothing is typed', (tester) async {
      await pumpWithRootShortcut(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await pressCtrlK(tester);

      expect(router.location, Paths.search);
    });
  });

  group('the results panel', () {
    /// A state with rows in it, so the panel is a real target and not the
    /// zero-size box `SearchStatus.idle` renders.
    void seedResults() => when(() => bloc.state).thenReturn(
          SearchState(
            status: SearchStatus.results,
            term: 'dela',
            results: _oneClient(),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      seedResults();
      await pumpField(tester, subject());
      await tester.enterText(find.byType(TextField), 'dela');
      await tester.pump();
    }

    testWidgets('opens under the field once there is something to show',
        (tester) async {
      await open(tester);

      expect(find.byType(SearchOverlay), findsOneWidget);
      expect(find.byType(SearchResultTile), findsOneWidget);
    });

    // The bloc outlives the session. Whatever the last query left on the
    // state — another account's client rows included — must not be a focus
    // away.
    testWidgets('does not open on focus alone', (tester) async {
      seedResults();
      await pumpField(tester, subject());

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      expect(find.byType(SearchResultTile), findsNothing);
    });

    testWidgets('closes when the text is cleared', (tester) async {
      await open(tester);
      expect(find.byType(SearchOverlay), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      // The erase still reaches the bloc, which is what clears the state.
      await tester.pump(const Duration(milliseconds: 300));
      expect(capturedQueries().last.query, '');
    });

    testWidgets('a tap away dismisses it', (tester) async {
      await open(tester);
      expect(find.byType(SearchOverlay), findsOneWidget);

      // Inside the 800x600 test view — `MediaQuery` is overridden for layout
      // but the surface a tap is routed through is not — and clear of both the
      // field and the panel hanging under it.
      await tester.tapAt(const Offset(600, 500));
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
    });

    testWidgets('Escape dismisses it', (tester) async {
      await open(tester);
      expect(find.byType(SearchOverlay), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      // The query survives: Escape closes the results, it does not undo the
      // typing that produced them.
      expect(find.widgetWithText(TextField, 'dela'), findsOneWidget);
    });

    testWidgets('typing again after a dismissal reopens it', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(SearchOverlay), findsNothing);

      await tester.enterText(find.byType(TextField), 'dela c');
      await tester.pump();

      expect(find.byType(SearchOverlay), findsOneWidget);
    });

    testWidgets('goes away with the field', (tester) async {
      await open(tester);

      await pumpField(tester, const SizedBox.shrink());
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // The panel is an `OverlayEntry`: nothing unmounts it when the page under
    // it changes. A `ShellRoute` keeps the field mounted across the change,
    // exactly as the app's shell app bar does.
    testWidgets('goes away when the route changes underneath it',
        (tester) async {
      seedResults();
      final router = GoRouter(
        initialLocation: Paths.index,
        routes: [
          ShellRoute(
            builder: (_, __, child) => MediaQuery(
              data: const MediaQueryData(size: _wide),
              child: Scaffold(
                appBar: AppBar(actions: const [SearchField()]),
                body: child,
              ),
            ),
            routes: [
              GoRoute(path: Paths.index, builder: (_, __) => const Text('home')),
              GoRoute(path: Paths.users, builder: (_, __) => const Text('users')),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await pumpRouter(tester, router);
      await tester.enterText(find.byType(TextField), 'dela');
      await tester.pump();
      expect(find.byType(SearchOverlay), findsOneWidget);

      router.go(Paths.users);
      await tester.pumpAndSettle();

      expect(find.text('users'), findsOneWidget);
      // The field survived the navigation; only the panel went.
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(SearchOverlay), findsNothing);
    });
  });

  group('logout', () {
    testWidgets('clears the search bloc', (tester) async {
      final auth = _MockAuthenticationBloc();
      whenListen(
        auth,
        Stream.value(const AuthenticationState.logout()),
        initialState: const AuthenticationState(),
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthenticationBloc>.value(value: auth),
            BlocProvider<SearchBloc>.value(value: bloc),
          ],
          child: const ClearSearchOnLogout(child: SizedBox()),
        ),
      );
      await tester.pump();

      verify(() => bloc.add(const SearchClearedEvent())).called(1);
    });

    // End to end through a REAL bloc: the previous account's rows are on the
    // state, the session ends, the next account focuses a fresh field.
    testWidgets('leaves the next account nothing to see on focus',
        (tester) async {
      final index = _MockSearchIndex();
      when(() => index.query(any())).thenAnswer((_) async => _oneClient());
      final auth = _MockAuthenticationService();
      when(() => auth.user).thenReturn(_admin());
      final real =
          SearchBloc.withDependencies(searchIndex: index, authService: auth);
      addTearDown(real.close);

      await pumpField(tester, subject(), withBloc: real);
      await tester.enterText(find.byType(TextField), 'dela');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SearchResultTile), findsOneWidget);

      // What `ClearSearchOnLogout` dispatches, followed by the app bar — field
      // included — giving way to the login screen.
      real.add(const SearchClearedEvent());
      await pumpField(tester, const SizedBox.shrink(), withBloc: real);
      await tester.pump();

      await pumpField(tester, subject(), withBloc: real);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      expect(find.byType(SearchResultTile), findsNothing);
      expect(real.state.status, SearchStatus.idle);
    });
  });

  testWidgets('stays off the pre-auth app bar even when enabled',
      (tester) async {
    // login / register / set-password all call defaultAppBar with the login
    // and sign-up buttons showing. Rendering the field there would read
    // `AuthenticationService.instance.user`, which throws `Please login`.
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          appBar: LayoutWidgets.defaultAppBar(context, showSearchField: true),
        ),
      ),
    );

    expect(find.byType(SearchField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('the authenticated app bar', () {
    late _MockUserBloc users;
    late _MockNotificationRepository notifications;

    setUp(() {
      users = _MockUserBloc();
      when(() => users.state).thenReturn(const UserState());
      notifications = _MockNotificationRepository();
      when(() => notifications.dataStream)
          .thenAnswer((_) => Stream<List<notif.Notification>>.value(const []));
    });

    /// What an authenticated `defaultAppBar` costs. Three static reads in
    /// that one method have to be satisfied before it will build at all:
    /// `AuthenticationService.instance.user`, `NotificationService.instance`
    /// (NOT inside the `showMessagesButton` block, so turning that flag off
    /// does not avoid it), and a `UserBloc`. `NotificationService.initialize`
    /// sets its statics before it reaches `FirebaseMessaging`, which is the
    /// only reason this is reachable from a test isolate at all.
    Widget scaffolding(Widget Function(BuildContext) build) =>
        MultiRepositoryProvider(
          providers: [
            // `RepositoryProvider`, not `Provider`: `flutter_bloc` re-exports
            // the former, and `provider` itself is not a declared dependency
            // of the app.
            RepositoryProvider<notif.NotificationRepository>.value(
              value: notifications,
            ),
            BlocProvider<UserBloc>.value(value: users),
            BlocProvider<SearchBloc>.value(value: bloc),
          ],
          child: Builder(
            builder: (context) {
              try {
                NotificationService.initialize(context);
              } catch (_) {
                // FirebaseMessaging is unavailable in a test isolate. The
                // statics are already set by the time it throws.
              }

              return build(context);
            },
          ),
        );

    // The positive half. Without it, `showSearchField` could be ignored
    // outright and the pre-auth test above would still be green.
    testWidgets('renders the field when enabled', (tester) async {
      // The default 800px view overflows this app bar's actions row by 144px.
      // `setSurfaceSize` resizes the surface but not `MediaQuery`, which is
      // what the collapse rule reads; the view's own size drives both.
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AuthenticationService.instance.user = _admin();

      await tester.pumpApp(
        scaffolding(
          (context) => Scaffold(
            appBar: LayoutWidgets.defaultAppBar(
              context,
              showLogin: false,
              showSignUp: false,
              showSearchField: true,
            ),
          ),
        ),
      );

      expect(find.byType(SearchField), findsOneWidget);
      // Live, not merely mounted: the hint comes from the bloc it found.
      expect(find.text('Search clients…'), findsOneWidget);

      // The toolbar is 120px (`LayoutWidgets.defaultAppBar`) and an
      // unconstrained field renders at the full 120, dwarfing the icon
      // buttons beside it. Measured, not eyeballed: every other assertion
      // here passed while the field was two and a half times too tall.
      // Wrapping in `Center` does not fix it — only the explicit height does.
      final fieldHeight = tester.getSize(find.byType(TextField)).height;
      expect(
        fieldHeight,
        lessThan(64),
        reason:
            '$fieldHeight tall in a 120px toolbar; the height is unconstrained',
      );
    });

    // `/search` carries its own field. A second one in the shell app bar fed
    // the same bloc with the overlay floating over the page's own results,
    // and on compact it was a search icon whose tap went to `/search` from
    // `/search`.
    testWidgets('drops the field on /search and keeps it elsewhere',
        (tester) async {
      // `setSurfaceSize` resizes the surface but not `MediaQuery`, which is
      // what the collapse rule reads; the view's own size drives both.
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AuthenticationService.instance.user = _admin()
        ..userRole = UserRole.customer;

      final auth = _MockAuthenticationBloc();
      when(() => auth.state).thenReturn(const AuthenticationState());
      final conversations = _MockConversationsBloc();
      when(() => conversations.state).thenReturn(const ConversationsState());

      final router = GoRouter(
        initialLocation: Paths.index,
        routes: [
          ShellRoute(
            builder: (_, __, child) => HomeScreen(child: child),
            routes: [
              GoRoute(path: Paths.index, builder: (_, __) => const Text('home')),
              GoRoute(
                path: Paths.search,
                builder: (_, __) => const Text('search page'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        scaffolding(
          (_) => MultiBlocProvider(
            providers: [
              BlocProvider<AuthenticationBloc>.value(value: auth),
              BlocProvider<ConversationsBloc>.value(value: conversations),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.byType(SearchField), findsOneWidget);

      router.go(Paths.search);
      await tester.pumpAndSettle();

      expect(find.text('search page'), findsOneWidget);
      expect(find.byType(SearchField), findsNothing);
      expect(find.byType(SearchAppBarAction), findsNothing);

      router.go(Paths.index);
      await tester.pumpAndSettle();

      expect(find.byType(SearchField), findsOneWidget);
    });
  });
}
