import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_field.dart';
import 'package:loooans/widgets/layout_widgets.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

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

  testWidgets('the compact icon opens the field', (tester) async {
    await tester.pumpApp(subject(size: _compact));

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
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

  testWidgets('a pause between keystrokes dispatches each one',
      (tester) async {
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
}
