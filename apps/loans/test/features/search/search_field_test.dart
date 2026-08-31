import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_field.dart';
import 'package:loooans/features/search/widget/search_overlay.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
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

class _MockNotificationRepository extends Mock
    implements notif.NotificationRepository {}

const _wide = Size(1280, 800);
const _compact = Size(390, 844);

void main() {
  late SearchBloc bloc;

  // `SearchEvent` is sealed, so the fallback is a real event, not a `Fake`.
  setUpAll(
    () => registerFallbackValue(const QueryChangedEvent('', location: '')),
  );

  setUp(() {
    bloc = _MockSearchBloc();
    when(() => bloc.state).thenReturn(const SearchState());
  });

  Widget subject({Size size = _wide, bool showShortcutBadge = true}) =>
      MediaQuery(
        data: MediaQueryData(size: size),
        child: BlocProvider<SearchBloc>.value(
          value: bloc,
          child: Scaffold(
            body: SearchField(showShortcutBadge: showShortcutBadge),
          ),
        ),
      );

  List<QueryChangedEvent> capturedQueries() =>
      verify(() => bloc.add(captureAny()))
          .captured
          .whereType<QueryChangedEvent>()
          .toList();

  testWidgets('renders a text field on a wide screen', (tester) async {
    await tester.pumpApp(subject());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  testWidgets('collapses to an icon on a compact screen', (tester) async {
    await tester.pumpApp(subject(size: _compact));

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(router.location, Paths.search);
    expect(find.text('search page'), findsOneWidget);
  });

  testWidgets('advertises no shortcut on a compact screen', (tester) async {
    await tester.pumpApp(subject(size: _compact));

    expect(find.text('Ctrl K'), findsNothing);
    expect(find.text('⌘K'), findsNothing);
  });

  testWidgets('hides the badge when asked to', (tester) async {
    await tester.pumpApp(subject(showShortcutBadge: false));

    expect(find.text('Ctrl K'), findsNothing);
  });

  testWidgets('the hint tracks the scope', (tester) async {
    when(() => bloc.state)
        .thenReturn(const SearchState(scope: SearchScope.offers));
    await tester.pumpApp(subject());

    expect(find.text('Search offers…'), findsOneWidget);
    expect(find.text('Search clients…'), findsNothing);
  });

  testWidgets('rapid keystrokes coalesce into one query', (tester) async {
    await tester.pumpApp(subject());

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
    await tester.pumpApp(subject());

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
    await tester.pumpApp(subject());

    await tester.enterText(find.byType(TextField), 'dela');
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));

    verifyNever(() => bloc.add(any()));
  });

  group('the results panel', () {
    /// A state with rows in it, so the panel is a real target and not the
    /// zero-size box `SearchStatus.idle` renders.
    void seedResults() => when(() => bloc.state).thenReturn(
          SearchState(
            status: SearchStatus.results,
            term: 'dela',
            results: SearchResults(
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
              scope: SearchScope.clients,
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      seedResults();
      await tester.pumpApp(subject());
      await tester.enterText(find.byType(TextField), 'dela');
      await tester.pump();
    }

    testWidgets('opens under the field once there is something to show',
        (tester) async {
      await open(tester);

      expect(find.byType(SearchOverlay), findsOneWidget);
      expect(find.byType(SearchResultTile), findsOneWidget);
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

      await tester.pumpApp(const SizedBox.shrink());
      await tester.pump();

      expect(find.byType(SearchOverlay), findsNothing);
      expect(tester.takeException(), isNull);
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

  // The positive half. Without it, `showSearchField` could be ignored outright
  // and the negative test above would still be green.
  //
  // The scaffolding is what an authenticated `defaultAppBar` costs. Three
  // static reads in that one method have to be satisfied before it will build
  // at all: `AuthenticationService.instance.user` (`layout_widgets.dart:258`,
  // :370), `NotificationService.instance` (`:310` — NOT inside the
  // `showMessagesButton` block, so turning that flag off does not avoid it),
  // and a `UserBloc` (`:366`). `NotificationService.initialize` sets its
  // statics before it reaches `FirebaseMessaging`, which is the only reason
  // this is reachable from a test isolate at all.
  testWidgets('renders on the authenticated app bar when enabled',
      (tester) async {
    // The default 800px view overflows this app bar's actions row by 144px.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AuthenticationService.instance.user = User()
      ..id = 'user-1'
      ..firstName = 'Juan'
      ..lastName = 'Dela Cruz'
      // `late ImageUrl?` (`user_entity.dart:91`) — unset is a LateError, not
      // a null.
      ..profilePhotoUrl = null
      ..userRole = UserRole.admin;

    final users = _MockUserBloc();
    when(() => users.state).thenReturn(const UserState());

    final notifications = _MockNotificationRepository();
    when(() => notifications.dataStream)
        .thenAnswer((_) => Stream<List<notif.Notification>>.value(const []));

    await tester.pumpApp(
      // `RepositoryProvider`, not `Provider`: `flutter_bloc` re-exports the
      // former, and `provider` itself is not a declared dependency of the app.
      MultiRepositoryProvider(
        providers: [
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

            return Scaffold(
              appBar: LayoutWidgets.defaultAppBar(
                context,
                showLogin: false,
                showSignUp: false,
                showSearchField: true,
              ),
            );
          },
        ),
      ),
    );

    expect(find.byType(SearchField), findsOneWidget);
    // Live, not merely mounted: the hint comes from the bloc it found.
    expect(find.text('Search clients…'), findsOneWidget);
  });
}
