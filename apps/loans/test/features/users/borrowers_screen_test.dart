import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/model/user_address.dart';
import 'package:loooans/features/users/screens/borrowers_screen.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

void main() {
  late _MockUserBloc users;
  late _MockLoansBloc loans;

  setUp(() {
    // The settings widget the screen embeds reads SettingsService.instance,
    // which the router initializes at startup and a test must do itself.
    // It is a bare singleton — no storage, no Firebase.
    SettingsService.initialize();

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
    tester.view
      ..physicalSize = logical
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(WidgetTester tester, {String? initialBorrowerId}) {
    // Providers ABOVE MaterialApp, as `app.dart` has them: `showDialog`
    // pushes onto the root Navigator, and a dialog built there cannot see
    // providers that live under `home:`.
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<UserBloc>.value(value: users),
          BlocProvider<LoansBloc>.value(value: loans),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BorrowerScreen(initialBorrowerId: initialBorrowerId),
          ),
        ),
      ),
    );
  }

  group('initialBorrowerId (the /?sec=borrowers&id= deep link)', () {
    testWidgets("opens that borrower's dialog on a wide screen",
        (tester) async {
      // `tester.view`, not `setSurfaceSize`: the latter resizes the render
      // surface only, and `MediaQuery.sizeOf` — which `getScreenSize` reads —
      // keeps reporting the 800px default. The guard then sees `medium`.
      resize(tester, const Size(1600, 900));

      await pump(tester, initialBorrowerId: 'user-7');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // Not merely *a* dialog: the one for the borrower in the URL.
      // BorrowerDetailScreen.initState selects the user it was given.
      verify(() => users.selectUser('user-7')).called(1);
    });

    testWidgets('opens nothing when there is no id', (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => users.selectUser(any()));
    });

    testWidgets('opens nothing on a compact screen, where MainScreen '
        'redirects the same URL to the full-screen route', (tester) async {
      // 700px is `medium`: the guard still returns, without inheriting the
      // screen's own 85px header overflow at phone width (:192).
      resize(tester, const Size(700, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pump(tester, initialBorrowerId: 'user-7');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
