import 'package:address_repository/address_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/model/user_address.dart';
import 'package:loooans/features/users/screens/borrowers_screen.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

UserAddress _borrower(String id, String firstName) => UserAddress(
      user: User()
        ..id = id
        ..firstName = firstName
        ..lastName = 'Dela Cruz'
        ..mobileNumber = '09175550142'
        ..emailAddress = '$firstName@example.com'
        ..createdAt = DateTime(2025)
        ..profilePhotoUrl = null
        ..userRole = UserRole.customer,
      // `completeAddress1Line` short-circuits on this and reads only
      // `dataType`, so nothing else on the entity needs seeding.
      address: Address()
        ..line1 = 'no address'
        ..dataType = DataType.user,
    );

void main() {
  late _MockUserBloc users;
  late _MockLoansBloc loans;
  late GoRouter router;

  setUp(() {
    // The settings widget the screen embeds reads SettingsService.instance,
    // which the router initializes at startup and a test must do itself.
    // It is a bare singleton — no storage, no Firebase.
    SettingsService.initialize();
    // Each test states the UI mode it needs; start from the default.
    SettingsService.instance.setClassicUIForTest(enabled: false);

    // BorrowerScreen.initState reads `company.id`, which throws unless the
    // role is company-managed AND a company is set.
    AuthenticationService.instance
      ..user = (User()
        ..id = 'staff-1'
        ..firstName = 'Ana'
        ..lastName = 'Reyes'
        // `late ImageUrl?` — unset is a LateError, not a null.
        ..profilePhotoUrl = null
        ..userRole = UserRole.admin)
      ..company = (Company()
        ..id = 'company-1'
        // `late` on CompanyEntity; the settings widget the screen embeds
        // reads it, and unset is a LateError.
        ..managementType = CompanyManagementType.selfManaged);

    users = _MockUserBloc();
    when(() => users.state).thenReturn(const UserState());
    when(() => users.userAddresses)
        .thenAnswer((_) => Stream<List<UserAddress>>.value(const []));

    loans = _MockLoansBloc();
    when(() => loans.state).thenReturn(const LoansState());
  });

  void resize(WidgetTester tester, Size logical) {
    // `tester.view`, not `setSurfaceSize`: the latter resizes the render
    // surface only, and `MediaQuery.sizeOf` — which `getScreenSize` reads —
    // keeps reporting the 800px default. The guard then sees `medium`.
    tester.view
      ..physicalSize = logical
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A real router, because the screen now routes: every borrower tap goes
  /// through the URL, and closing the dialog rewrites it. The index route
  /// mirrors what MainScreen does with `?id=` — hands it to the screen.
  Future<void> pump(WidgetTester tester, {required String initialLocation}) {
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: Paths.index,
          builder: (_, state) => Scaffold(
            body: BorrowerScreen(
              initialBorrowerId: state.uri.queryParameters['id'],
            ),
          ),
        ),
        GoRoute(
          path: Paths.borrowersAction,
          builder: (_, __) => const Scaffold(body: Text('full-screen route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Providers ABOVE MaterialApp, as `app.dart` has them: `showDialog`
    // pushes onto the root Navigator, and a dialog built there cannot see
    // providers that live under the route.
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<UserBloc>.value(value: users),
          BlocProvider<LoansBloc>.value(value: loans),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  group('initialBorrowerId (the /?sec=borrowers&id= deep link)', () {
    testWidgets("opens that borrower's dialog on a wide screen",
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=borrowers&id=user-7');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // Not merely *a* dialog: the one for the borrower in the URL.
      // BorrowerDetailScreen.initState selects the user it was given.
      verify(() => users.selectUser('user-7')).called(1);
    });

    testWidgets('opens nothing when there is no id', (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=borrowers');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => users.selectUser(any()));
    });

    testWidgets(
        'opens nothing on a compact screen, where MainScreen '
        'redirects the same URL to the full-screen route', (tester) async {
      // 700px is `medium`: the guard still returns, without inheriting the
      // screen's own 85px header overflow at phone width (:192).
      resize(tester, const Size(700, 800));

      await pump(tester, initialLocation: '/?sec=borrowers&id=user-7');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('every way of opening a borrower is a URL', () {
    testWidgets('classic UI: a table row tap navigates to /?sec=borrowers&id=',
        (tester) async {
      SettingsService.instance.setClassicUIForTest(enabled: true);
      resize(tester, const Size(1600, 900));
      when(() => users.userAddresses).thenAnswer(
        (_) => Stream.value([_borrower('user-7', 'Juan')]),
      );

      await pump(tester, initialLocation: '/?sec=borrowers');
      await tester.pumpAndSettle();

      // The reported inconsistency: this used to call showDialog directly
      // and leave the address bar on /?sec=borrowers, while a search result
      // for the same person changed it.
      await tester.tap(find.text('Dela Cruz, Juan'));
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=borrowers&id=user-7');
    });

    testWidgets('non-classic UI: a row tap opens the full-screen route',
        (tester) async {
      // The non-classic UI has no Borrowers section for a dialog to sit over
      // and no borrower-profile surface of its own, so the profile is its own
      // screen there. Sending it to /?sec=borrowers&id= rendered the home
      // page with an id in the URL and opened nothing.
      resize(tester, const Size(1600, 900));
      when(() => users.userAddresses).thenAnswer(
        (_) => Stream.value([_borrower('user-7', 'Juan')]),
      );

      await pump(tester, initialLocation: '/?sec=borrowers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dela Cruz, Juan'));
      await tester.pumpAndSettle();

      expect(router.location, '/borrowers/user-7');
      expect(find.text('full-screen route'), findsOneWidget);
    });

    testWidgets('closing the dialog drops the id from the URL',
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=borrowers&id=user-7');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Pop the dialog route itself rather than pressing its Close button:
      // BorrowerDetailScreen renders nothing until UserStatus.selected, and
      // faking that pulls in the whole loans table. The route completing is
      // what the `.then` listens for, whichever way it closes.
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      // The URL said a dialog was open; it must stop saying so — and this
      // is also what makes re-tapping the same borrower a URL change again.
      expect(router.location, '/?sec=borrowers');
    });
  });
}
