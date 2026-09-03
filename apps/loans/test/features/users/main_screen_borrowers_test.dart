import 'package:address_repository/address_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/routing/router.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/capital/bloc/capital_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/main/screen/main_screen.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/model/user_address.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockAuthenticationBloc
    extends MockBloc<AuthenticationEvent, AuthenticationState>
    implements AuthenticationBloc {}

class _MockCapitalBloc extends MockBloc<CapitalEvent, CapitalState>
    implements CapitalBloc {}

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

/// The `/` page as the app router builds it, with the Borrowers section as
/// its one visible child. This is the only test that mounts `MainScreen`;
/// it exists because the remount was the bug.
void main() {
  late _MockUserBloc users;
  late _MockLoansBloc loans;
  late GoRouter router;

  final juan = UserAddress(
    user: User()
      ..id = 'user-7'
      ..firstName = 'Juan'
      ..lastName = 'Dela Cruz'
      ..mobileNumber = '09175550142'
      ..emailAddress = 'juan@example.com'
      ..createdAt = DateTime(2025)
      ..profilePhotoUrl = null
      ..userRole = UserRole.customer,
    address: Address()
      ..line1 = 'no address'
      ..dataType = DataType.user,
  );

  setUp(() {
    SettingsService.initialize();
    SettingsService.instance.setClassicUIForTest(enabled: true);

    AuthenticationService.instance
      ..user = (User()
        ..id = 'staff-1'
        ..firstName = 'Ana'
        ..lastName = 'Reyes'
        ..profilePhotoUrl = null
        ..userRole = UserRole.admin)
      ..company = (Company()
        ..id = 'company-1'
        ..managementType = CompanyManagementType.selfManaged);

    users = _MockUserBloc();
    when(() => users.state).thenReturn(const UserState());
    when(() => users.userAddresses)
        .thenAnswer((_) => Stream.value([juan]));

    loans = _MockLoansBloc();
    when(() => loans.state).thenReturn(const LoansState());
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _MockAuthenticationBloc();
    when(() => auth.state).thenReturn(const AuthenticationState());
    final capital = _MockCapitalBloc();
    when(() => capital.state).thenReturn(CapitalState());

    router = GoRouter(
      initialLocation: '/?sec=borrowers',
      routes: [
        GoRoute(path: Paths.index, builder: buildMainPage),
        GoRoute(
          path: Paths.borrowersAction,
          builder: (_, __) => const Scaffold(body: Text('full-screen route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthenticationBloc>.value(value: auth),
          BlocProvider<CapitalBloc>.value(value: capital),
          BlocProvider<UserBloc>.value(value: users),
          BlocProvider<LoansBloc>.value(value: loans),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'opening and closing a borrower updates MainScreen in place: '
      'no remount, the list loaded once', (tester) async {
    await pump(tester);
    final mainScreen = tester.state(find.byType(MainScreen));

    await tester.tap(find.text('Dela Cruz, Juan'));
    await tester.pumpAndSettle();
    expect(router.location, '/?sec=borrowers&id=user-7');
    expect(find.byType(AlertDialog), findsOneWidget);

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(router.location, '/?sec=borrowers');
    expect(find.byType(AlertDialog), findsNothing);

    // `UniqueKey()` on the `/` page remounted MainScreen on every one of
    // those URL changes, and each mount is a `loadNext` of every customer
    // in the company, their addresses, and the RTDB report.
    expect(tester.state(find.byType(MainScreen)), same(mainScreen));
    verify(
      () => users.loadNext(
        companyId: any(named: 'companyId'),
        customerOnly: any(named: 'customerOnly'),
      ),
    ).called(1);
  });
}
