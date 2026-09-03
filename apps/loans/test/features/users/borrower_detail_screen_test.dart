import 'package:bloc_test/bloc_test.dart';
import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/cash_pool/model/cash_pool_display.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/screens/borrower_detail_screen.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserBloc extends MockBloc<UserEvent, UserState>
    implements UserBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

class _MockCashPoolBloc extends MockBloc<CashPoolEvent, CashPoolState>
    implements CashPoolBloc {}

void main() {
  late _MockUserBloc users;
  late _MockLoansBloc loans;
  late _MockCashPoolBloc cashPool;
  late GoRouter router;

  final juan = User()
    ..id = 'user-7'
    ..firstName = 'Juan'
    ..lastName = 'Dela Cruz'
    ..birthDate = DateTime(1990, 5, 4)
    ..mobileNumber = '09175550142'
    ..emailAddress = 'juan@example.com'
    ..createdAt = DateTime(2025)
    ..profilePhotoUrl = null
    ..userRole = UserRole.customer;

  final salaryLoan = UserLoanView.create(
    userId: 'user-7',
    loanId: 'loan-1',
    loanType: 'Salary loan',
    userFullName: 'Dela Cruz, Juan',
    loanDueAt: null,
    loanCreatedAt: DateTime(2025, 3),
    loanStatus: LoanStatus.approved,
    productId: 'product-1',
    companyName: 'Company',
    companyId: 'company-1',
    amount: 5000,
    amortization: 500,
  );

  setUp(() {
    users = _MockUserBloc();
    // The screen renders nothing until the user is selected.
    when(() => users.state).thenReturn(UserState.selected(user: juan));
    when(() => users.user).thenReturn(juan);
    when(() => users.selectedUser).thenReturn(juan);
    when(() => users.address).thenReturn(null);

    loans = _MockLoansBloc();
    when(() => loans.state).thenReturn(const LoansState());
    when(() => loans.selectedBorrowerLoanViews).thenReturn([salaryLoan]);
    when(() => loans.selectedBorrowerPrincipalBorrowers).thenReturn([]);
    when(() => loans.selectedBorrowerLoanFiles).thenReturn([]);

    cashPool = _MockCashPoolBloc();
    when(() => cashPool.state).thenReturn(const CashPoolState());
    when(() => cashPool.cashPoolDisplay).thenReturn(
      const CashPoolDisplay(
        totalCashPool: 0,
        totalAcknowledged: 0,
        balance: 0,
        change: 0,
        savings: 0,
      ),
    );
    when(() => cashPool.loadCashPoolList2(any()))
        .thenAnswer((_) => Stream.value(const <CashPool>[]));
  });

  void resize(WidgetTester tester, Size logical) {
    // `tester.view`, not `setSurfaceSize`: `MediaQuery.sizeOf`, which
    // `getScreenSize` reads, only follows the former.
    tester.view
      ..physicalSize = logical
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The screen behind a real router: its exit is a routing decision.
  Future<void> pump(
    WidgetTester tester, {
    required String initialLocation,
    Widget Function(BuildContext)? home,
  }) {
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: Paths.index,
          builder: (context, _) =>
              home?.call(context) ?? const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: Paths.borrowersAction,
          builder: (_, state) => BorrowerDetailScreen(
            userId: state.pathParameters['action']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Providers above MaterialApp, as `app.dart` has them: a dialog is built
    // on the root Navigator and cannot see providers under the route.
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<UserBloc>.value(value: users),
          BlocProvider<LoansBloc>.value(value: loans),
          BlocProvider<CashPoolBloc>.value(value: cashPool),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  group('compact layout', () {
    testWidgets(
        'renders the profile and its loans stacked, with no placeholder '
        'rows and no overflow', (tester) async {
      // This branch used to be `ListTile(title: Text('Item $index'))`.
      resize(tester, const Size(390, 844));

      await pump(tester, initialLocation: '/borrowers/user-7');
      await tester.pumpAndSettle();

      expect(find.text('Dela Cruz, Juan'), findsWidgets);
      expect(find.text('Basic Information'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);

      // The loans table sits below the wallet block.
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();

      // One per column: the header cell repeats it, invisible past column 0.
      expect(find.text('Loans'), findsWidgets);
      expect(find.text('Salary loan'), findsOneWidget);
      expect(find.textContaining('Item '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('exit', () {
    testWidgets('a full-screen page reached by go: Close goes home',
        (tester) async {
      // Off mobile the leading tap was null and Close popped the sole root
      // page — a blank screen. `go` is how every non-classic tap gets here.
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/borrowers/user-7');
      await tester.pumpAndSettle();
      expect(find.byType(BorrowerDetailScreen), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(router.location, Paths.index);
      expect(find.text('home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pushed page (mobile): the back arrow pops to the list',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: Paths.index);
      await tester.pumpAndSettle();
      // What `openBorrower` does on Android/iOS.
      // Not awaited: on Android `goSafe` pushes, and that future completes
      // only when the page pops.
      router.goSafe('/borrowers/user-7');
      await tester.pumpAndSettle();
      expect(find.byType(BorrowerDetailScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(router.location, Paths.index);
      expect(find.text('home'), findsOneWidget);
      // Reset here, not only in tearDown: the binding checks foundation
      // debug variables when the body returns, before tearDowns run.
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    });

    testWidgets('in the dialog: Close closes the dialog and only the dialog',
        (tester) async {
      resize(tester, const Size(1600, 900));
      // The dialog's wide layout is sized for real fonts; the test font's
      // square glyphs are about twice as wide and overflow it. Halve them.
      tester.platformDispatcher.textScaleFactorTestValue = 0.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var closed = 0;

      await pump(
        tester,
        initialLocation: Paths.index,
        home: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => AppWidgets.showBorrowerDetailsDialog(
              context,
              'user-7',
              onClosed: () => closed++,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(closed, 1);
      // The page under the dialog is untouched.
      expect(find.text('open'), findsOneWidget);
      expect(router.location, Paths.index);
    });
  });
}
