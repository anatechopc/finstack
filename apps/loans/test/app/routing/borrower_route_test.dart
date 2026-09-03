import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/routing/router.dart';
import 'package:loooans/app/view/page_not_found.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/main/screen/main_screen.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/screens/borrower_detail_screen.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

User _userWith(UserRole role) => User()
  ..id = 'me'
  ..firstName = 'Ana'
  ..lastName = 'Reyes'
  // `late ImageUrl?` — unset is a LateError, not a null.
  ..profilePhotoUrl = null
  ..userRole = role;

void main() {
  late _MockUserBloc users;
  late _MockLoansBloc loans;

  setUp(() {
    users = _MockUserBloc();
    when(() => users.state).thenReturn(const UserState());
    loans = _MockLoansBloc();
    when(() => loans.state).thenReturn(const LoansState());
  });

  /// The route's builder alone, behind a one-route router. The app router's
  /// `redirect` needs Firebase, and it passes every verified user anyway:
  /// the gate under test is the builder's.
  Future<void> pumpBorrowerRoute(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/borrowers/user-7',
      routes: [
        GoRoute(path: Paths.borrowersAction, builder: buildBorrowerPage),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<UserBloc>.value(value: users),
          BlocProvider<LoansBloc>.value(value: loans),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('/borrowers/:id is gated on the clients scope', () {
    testWidgets('a customer gets Page Not Found, and no profile is loaded',
        (tester) async {
      // The report: any verified user could paste /borrowers/<uid> and read
      // that user's profile and loan history. Loading is the leak, so it is
      // the loading that must not happen — not merely the rendering.
      AuthenticationService.instance.user = _userWith(UserRole.customer);

      await pumpBorrowerRoute(tester);

      expect(find.byType(PageNotFound), findsOneWidget);
      expect(find.byType(BorrowerDetailScreen), findsNothing);
      verifyNever(() => users.selectUser(any()));
      verifyNever(
        () => loans.getLoansByUser(
          userId: any(named: 'userId'),
          allStatus: any(named: 'allStatus'),
          userIsBorrower: any(named: 'userIsBorrower'),
        ),
      );
    });

    testWidgets('a placeholder (pre-login) user gets Page Not Found',
        (tester) async {
      // `redirect` lets placeholder users through everywhere on purpose.
      AuthenticationService.instance.user =
          User.createPlaceholder(lastName: 'Guest');

      await pumpBorrowerRoute(tester);

      expect(find.byType(PageNotFound), findsOneWidget);
      verifyNever(() => users.selectUser(any()));
    });

    for (final role in [UserRole.admin, UserRole.teller, UserRole.appAdmin]) {
      testWidgets('${role.name} reaches the profile', (tester) async {
        AuthenticationService.instance.user = _userWith(role);

        await pumpBorrowerRoute(tester);

        expect(find.byType(BorrowerDetailScreen), findsOneWidget);
        expect(find.byType(PageNotFound), findsNothing);
        verify(() => users.selectUser('user-7')).called(1);
      });
    }
  });

  group('compactDetailRoute — the /?sec=&id= redirect on a phone', () {
    test('sends staff on /?sec=borrowers&id= to the full-screen route', () {
      expect(
        compactDetailRoute(
          section: 'borrowers',
          id: 'user-7',
          user: _userWith(UserRole.teller),
        ),
        '/borrowers/user-7',
      );
    });

    test('does not send a customer there — the second way in, same gate', () {
      expect(
        compactDetailRoute(
          section: 'borrowers',
          id: 'user-7',
          user: _userWith(UserRole.customer),
        ),
        isNull,
      );
    });

    test('offers and loans are open to everyone', () {
      final customer = _userWith(UserRole.customer);
      expect(
        compactDetailRoute(section: 'offers', id: 'p-1', user: customer),
        '/offers/p-1',
      );
      expect(
        compactDetailRoute(section: 'loans', id: 'l-1', user: customer),
        '/loans/l-1',
      );
    });

    test('nothing without an id, or for a section with no detail page', () {
      final admin = _userWith(UserRole.admin);
      expect(
        compactDetailRoute(section: 'borrowers', id: null, user: admin),
        isNull,
      );
      expect(
        compactDetailRoute(section: 'users', id: 'u-1', user: admin),
        isNull,
      );
    });
  });
}
