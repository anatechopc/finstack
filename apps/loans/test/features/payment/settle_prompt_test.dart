import 'package:bloc_test/bloc_test.dart';
import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/cash_pool/model/cash_pool_display.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/widget/payment_center_dialogs.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_dialogs.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:mocktail/mocktail.dart';

// #155 through both single-payment dialogs (client detail and the Payment
// Center): pressing "Confirm payment" either asks "Planning to settle your
// account?" (an early payoff) or goes on to the payment proof ("Choose
// image source"). Figures from golden G16h: G1 with bill 1 paid 500 +
// 2,900, so bill 2 is 3,944.18 = 355.00 + 3,589.18 with 3,510.82 left after
// it (the old check, principal >= balance after, settled it); the last bill
// 3,510.82 + 175.541; the remainder row 510.82 after the last bill is paid
// 175.54 + 3,000. Settlement: 7,100 on bill 2, all that is owed before it.
// Open-term (10,000 balance, 500 interest): unchanged, 10,000 principal
// settles, interest only does not.
// The fills of a carried bill add up to it (second review of #156): bill 1
// paid 500 + 2,999.50 → bill 2 3,844.68, filled 350.03 + 3,494.65 (was
// 350.03 + 3,494.66 = 3,844.69).

class _MockCashPoolBloc extends MockBloc<CashPoolEvent, CashPoolState>
    implements CashPoolBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

class _MockPaymentCenterBloc
    extends MockBloc<PaymentCenterEvent, PaymentCenterState>
    implements PaymentCenterBloc {}

LoanCalculationResult engine(List<LoanSchedule> stored) =>
    LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: DateTime(2026, 1, 10),
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: List.of(stored),
    );

/// Records the next computed bill after [stored] with [principal] (the
/// interest as billed, or [interest]).
List<LoanSchedule> payNext(
  List<LoanSchedule> stored, {
  double? principal,
  double? interest,
}) {
  final next = engine(stored).schedules.first;
  PaymentConfirmationService.recordTellerPayment(
    next,
    interestPayment: interest ?? next.interestPayment,
    principalPayment: principal ?? next.principalPayment,
  );

  return [
    ...stored,
    next
      ..id = 'sched-${stored.length + 1}'
      ..status = LoanStatus.paid_late,
  ];
}

final one = payNext(const [], principal: 2900);
final two = payNext(one, principal: 3589.18);

Loan loanOf({required bool openTerm}) => Loan()
  ..id = 'loan-1'
  ..userId = 'u1'
  ..period = openTerm ? 0 : 3
  ..term = '1m'
  ..status = LoanStatus.paid_late
  ..createdAt = DateTime(2026, 1, 10)
  ..additionalLoanAmounts = []
  ..penalties = []
  ..allowLatePayments = false;

LoanSchedule openTermBill() => LoanSchedule.create(
      dueAt: DateTime(2026, 2, 9),
      outstandingBalance: 10000,
      amortization: 500,
      principalPayment: 0,
      interestCharge: 500,
      loanId: 'loan-1',
      interestDayMultiplier: 1,
      companyId: 'co-1',
      isOpenTerm: true,
    );

void main() {
  late _MockCashPoolBloc cashPool;
  late _MockLoansBloc loans;
  late _MockPaymentCenterBloc paymentCenter;

  setUp(() {
    SettingsService.initialize();
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
    loans = _MockLoansBloc();
    when(() => loans.state).thenReturn(const LoansState());
    paymentCenter = _MockPaymentCenterBloc();
    when(() => paymentCenter.state).thenReturn(const PaymentCenterState());
    when(() => paymentCenter.loanRowsOf(any())).thenReturn(const []);
  });

  /// The text in [dialog]'s field [name] (`interest_payment` or
  /// `principal_payment`).
  String fieldText(WidgetTester tester, String name) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is FormBuilderTextField && w.name == name,
          ),
          matching: find.byType(TextField),
        ),
      )
      .controller!
      .text;

  /// Opens [dialog]'s payment dialog for [row], enters [principal] when
  /// given, presses "Confirm payment" and returns whether the settle
  /// prompt opened (otherwise the payment proof must have). With
  /// [onOpen], only opens the dialog and hands it the tester.
  Future<bool> asksToSettle(
    WidgetTester tester, {
    required String dialog,
    required LoanSchedule row,
    required bool openTerm,
    String? principal,
    void Function()? onOpen,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loan = loanOf(openTerm: openTerm);
    when(() => loans.selectedLoan).thenReturn(loan);

    // Above the app, as in the app: the client-detail dialog reads its
    // blocs from the dialog route.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CashPoolBloc>.value(value: cashPool),
          BlocProvider<LoansBloc>.value(value: loans),
          BlocProvider<PaymentCenterBloc>.value(value: paymentCenter),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => dialog == 'client detail'
                    ? showMakePaymentDialog(
                        context,
                        schedule: row,
                        userId: 'u1',
                      )
                    : showPaymentCenterPaymentDialog(
                        context,
                        loan: loan,
                        schedule: row,
                        userId: 'u1',
                      ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (onOpen != null) {
      onOpen();
      return false;
    }

    if (principal != null) {
      final field = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is FormBuilderTextField && w.name == 'principal_payment',
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, principal);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm payment'));
    await tester.pumpAndSettle();

    final settle = find.text('Planning to settle your account?');
    final proof = find.text('Choose image source');
    expect(
      tester.any(settle) != tester.any(proof),
      isTrue,
      reason: 'exactly one of the settle prompt and the payment proof',
    );

    return tester.any(settle);
  }

  for (final dialog in ['client detail', 'Payment Center']) {
    group('$dialog dialog', () {
      testWidgets('bill 2 carrying 272.09 (3,589.18 principal) is recorded',
          (tester) async {
        final bill2 = engine(one).schedules.first;
        expect(bill2.principalPayment, closeTo(3589.18, 0.000001));
        expect(bill2.outstandingBalance, closeTo(3510.82, 0.000001));

        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: bill2,
            openTerm: false,
          ),
          isFalse,
        );
      });

      testWidgets('the last bill as billed is recorded', (tester) async {
        final bill3 = engine(two).schedules.single;
        expect(bill3.outstandingBalance, closeTo(0, 0.000001));

        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: bill3,
            openTerm: false,
          ),
          isFalse,
        );
      });

      testWidgets('the remainder row (510.82, no interest) is recorded',
          (tester) async {
        final remainder = engine(
          payNext(two, interest: 175.54, principal: 3000),
        ).schedules.single;
        expect(remainder.amortization, closeTo(510.82, 0.000001));

        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: remainder,
            openTerm: false,
          ),
          isFalse,
        );
      });

      testWidgets('7,100 on bill 2, all that is owed, offers settlement',
          (tester) async {
        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: engine(one).schedules.first,
            openTerm: false,
            principal: '7100',
          ),
          isTrue,
        );
      });

      testWidgets('open-term, unchanged: 10,000 principal settles',
          (tester) async {
        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: openTermBill(),
            openTerm: true,
            principal: '10000',
          ),
          isTrue,
        );
      });

      testWidgets('interest not in whole centavos (500 + 2,999.50): the '
          'fills add up to the bill, 350.03 + 3,494.65 = 3,844.68',
          (tester) async {
        final bill2 = engine(payNext(const [], principal: 2999.50))
            .schedules
            .first;
        expect(bill2.amortization.toStringAsFixed(2), '3844.68');

        await asksToSettle(
          tester,
          dialog: dialog,
          row: bill2,
          openTerm: false,
          onOpen: () {
            final interest = fieldText(tester, 'interest_payment');
            final principal = fieldText(tester, 'principal_payment');
            expect([interest, principal], ['350.03', '3494.65']);
            expect(
              (double.parse(interest) + double.parse(principal))
                  .toStringAsFixed(2),
              '3844.68',
            );
          },
        );
      });

      testWidgets('open-term, unchanged: interest only is recorded',
          (tester) async {
        expect(
          await asksToSettle(
            tester,
            dialog: dialog,
            row: openTermBill(),
            openTerm: true,
          ),
          isFalse,
        );
      });
    });
  }
}
