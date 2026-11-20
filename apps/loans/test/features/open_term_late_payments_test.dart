import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
// Stored rows are read back through this entity, which the package does
// not export.
// ignore: implementation_imports
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/widget/overdue_summary_tile.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_schedule_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../helpers/helpers.dart';

// finstack#114 and the owner's open-term rules R1-R5 (2026-11-19) at widget
// and bloc level: the screens fed by the real open-term engine.
// Loan: 10,000 at 5% a month ('1m', 500 per 30-day cycle); penalties
// "Late fee" 100 once + "Daily surcharge" 1% of the balance (100) per day.
//
// One missed bill (G13a): paid cycle 38 days ago -> the bill due 8 days ago
// keeps its date (R1), 30 days, 500 (before R1: billed today, 38 days,
// 633.33); 8 days late -> 100 + 100 x 8 = 900; the next bill (+22) is not
// due yet. With fixed dates (Sep 8 2026, paid Aug 1): Aug 31 500 + 900 ->
// Next payment 1,400; Pay in full 1,400 + Sep 30's 500 = 1,900 (allow late:
// 500 / 1,000).
// Two missed bills: paid cycle 68 days ago -> bills due 38 and 8 days ago
// (500 each), +22 current. The stretch runs from the earliest unpaid due
// date (R3): 100 x 38 = 3,800 once, and the flat "Late fee" 100 on each
// missed bill (owner, 2026-11-19: a flat amount is charged per missed bill)
// -> 3,900 + 100 = 4,000 (all per bill it would be 3,900 + 900 = 4,800;
// before the owner's flat-fee decision 3,900). Fixed dates, seen Oct 5:
// Aug 31 and Sep 30 missed -> Next payment 500 + 500 + (100 + 100 x 35) +
// 100 = 4,700; Pay in full + Oct 30's 500 = 5,200 (were 4,600 / 5,100).
// Bulk overdue (two missed): total interest 1,000 pays 500 + 500, penalty
// [3,900, 100] (was [3,900, 0]), days late [38, 8]; 700 pays 500 + 200 (the
// 300 short carries, R4); 400 pays the first bill only and the second stays
// unpaid.
//
// The client-detail row, the borrower table and the Payment Center read the
// wall clock, so those scenarios are dated relative to today; the payment
// dialog and the borrower totals take a date. Like the golden suite this
// assumes a zone without daylight saving (CI pins TZ=UTC): across a clock
// change the engine's 30-day step lands an hour off (campaign D11).
//
// Rejected submissions stored by #143's app (before R1): billed as due on
// the day they were submitted, interest from the paid cycle to that day,
// the cycle's own date in original_due_at. The engine leaves them as they
// are and bills the next scheduled date after them, from that day.
//   Submitted 2 days ago (paid 38 days ago): 36 days, 600, original due 8
//   days ago -> overdue, 900; the next bill is the scheduled +22 (24 days
//   from the stored row, 400), upcoming. Stored before #114 (no original
//   due date): 100 + 100 x 2 = 300.
//   Submitted 45 days ago (paid 80 days ago, loan 110 days old): 35 days,
//   583.33, amount due 500 (the old cap), original due 50 days ago; next
//   bills -20 (25 days, 416.67, missed) and +10 (500). Stretch from 50
//   days ago: 100 + 100 x 50 = 5,100 once (per bill 5,100 + 2,100 =
//   7,200), plus the flat 100 on the -20 bill = 5,200; Pay in full 500 +
//   416.67 + 500 + 5,200 = 6,616.67 on every screen (were 5,100 and
//   6,516.67 before the owner's flat-fee decision).
//   With a 5,000 top-up 50 days ago (stored 15,000, interest 500, penalty
//   100 + 1% x 15,000 x 50 = 7,600): the row is shown and confirmed as
//   stored (#145); the top-up is in its balance, so the next bill (-20, 25
//   days) is 15,000 x 5% x 25/30 = 625.

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily01pct = Penalty(
  id: 'daily-01',
  name: 'Daily 0.1%',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);
const daily1pct = Penalty(
  id: 'daily',
  name: 'Daily surcharge',
  amount: 1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);

/// Read on every use, so a run that crosses midnight stays consistent with
/// the engine's own clock.
DateTime get today => DateUtils.dateOnly(DateTime.now());

DateTime daysFromToday(int days) => DateUtils.addDaysToDate(today, days);

/// Every field is set (the Payment Center state compares loans by value).
Loan openTermLoan({required DateTime createdAt, bool allowLate = false}) =>
    Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'open term',
      interestRate: 5,
      term: '1m',
      amortization: 500,
      penalties: const [lateFee100, daily1pct],
      allowLatePayments: allowLate,
    )
      ..id = 'loan-1'
      ..createdAt = createdAt
      ..additionalLoanAmounts = [];

LoanSchedule paidCycle(DateTime dueAt) => LoanSchedule()
  ..id = 'sched-1'
  ..loanId = 'loan-1'
  ..companyId = 'co-1'
  ..createdAt = dueAt
  ..updatedAt = dueAt
  ..dueAt = dueAt
  ..paidAt = dueAt
  ..status = LoanStatus.paid_on_time
  ..isOpenTerm = true
  ..outstandingBalance = 10000
  ..principalPayment = 0
  ..interestPayment = 0
  ..interestCharge = 0
  ..amortization = 0
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

/// The open-term bills after a cycle paid [paidDaysAgo] days ago on a loan
/// created 30 days before it, as the app computes them now.
List<LoanSchedule> billsNow({int paidDaysAgo = 38}) =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: 10000,
      date: daysFromToday(-paidDaysAgo - 30),
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: [paidCycle(daysFromToday(-paidDaysAgo))],
      now: DateTime.now(),
    ).schedules;

/// What LoansBloc lists for client detail and the borrower now.
List<LoanSchedule> clientRowsNow(Loan loan, List<LoanSchedule> stored) =>
    LoanCalculationService.calculateOpenTerm(
      amount: 10000,
      date: loan.createdAt,
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: stored,
      loan: loan,
      now: DateTime.now(),
    ).schedules;

/// A submission on [submittedAt] that the lender rejected, as #143's app
/// stored it (before R1): billed as due that day with interest from the
/// paid cycle, the cycle's date in original_due_at; read back from
/// Firestore as overdue.
LoanSchedule rejectedSubmission({
  required DateTime paidDue,
  required DateTime submittedAt,
  bool storedBefore114 = false,
  double balance = 10000,
  double? interestCharge,
}) {
  final billedOn = DateUtils.dateOnly(submittedAt);
  final days = billedOn.difference(paidDue).inDays;
  final interest = interestCharge ?? balance * 0.05 * days / 30;
  final row = LoanSchedule()
    ..id = 'sched-2'
    ..loanId = 'loan-1'
    ..companyId = 'co-1'
    ..createdAt = submittedAt
    ..updatedAt = submittedAt
    ..dueAt = billedOn
    ..originalDueAt =
        storedBefore114 ? null : DateUtils.addDaysToDate(paidDue, 30)
    ..status = LoanStatus.not_paid_overdue
    ..isOpenTerm = true
    ..outstandingBalance = balance
    ..principalPayment = 0
    ..interestPayment = 0
    ..interestCharge = interest
    ..amortization = interest < balance * 0.05 ? interest : balance * 0.05
    ..extraPayment = 0
    ..advanceInterestPayments = 0
    ..interestDayMultiplier = days / 30;

  return LoanScheduleEntity.fromJson(row.toJson()).toLoanSchedule();
}

/// The open-term principal release as approval stores it for app-managed
/// companies (#138): open term, the whole principal as principal_payment,
/// nothing to collect, no isPlaceholder.
LoanSchedule storedRelease({
  required DateTime createdAt,
  LoanStatus status = LoanStatus.approved,
}) =>
    LoanSchedule()
      ..id = 'planned'
      ..loanId = 'loan-1'
      ..companyId = 'co-1'
      ..createdAt = createdAt
      ..updatedAt = createdAt
      ..dueAt = createdAt
      ..status = status
      ..isOpenTerm = true
      ..outstandingBalance = 0
      ..principalPayment = 10000
      ..interestPayment = 0
      ..interestCharge = 0
      ..amortization = 0
      ..extraPayment = 0
      ..advanceInterestPayments = 0
      ..interestDayMultiplier = 1;

class _Users extends Mock implements UserRepository {}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

void main() {
  group('client-detail schedule row (teller)', () {
    setUp(() {
      AuthenticationService.instance
        ..user = (User()
          ..id = 'teller-1'
          ..userRole = UserRole.admin)
        ..company = (Company()
          ..id = 'co-1'
          ..managementType = CompanyManagementType.selfManaged);
    });

    Future<void> pumpRows(
      WidgetTester tester,
      Loan loan,
      List<LoanSchedule> rows, {
      List<LoanSchedule> loanRows = const [],
    }) async {
      tester.view
        ..physicalSize = const Size(2400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: [
              for (final row in rows)
                ClientDetailScheduleItem(
                  index: 2,
                  schedule: row,
                  onMakePayment: (_) {},
                  loan: loan,
                  loanRows: loanRows,
                ),
            ],
          ),
        ),
      );
    }

    testWidgets('a missed bill keeps its date: Overdue, 500, 900 for 8 days',
        (tester) async {
      final missed = billsNow().first;
      await pumpRows(
        tester,
        openTermLoan(createdAt: daysFromToday(-68)),
        [missed],
      );

      expect(find.text('Make payment'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.textContaining('900.00 penalty · 8 days late'),
        findsOneWidget,
      );
      expect(
        find.text(daysFromToday(-8).toDefaultDateFormat()),
        findsOneWidget,
        reason: 'R1: the bill is dated on its cycle, not today',
      );
      expect(find.textContaining('500.00'), findsOneWidget);
      expect(find.textContaining('633.33'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a loan that allows late payments: Overdue, no penalty',
        (tester) async {
      await pumpRows(
        tester,
        openTermLoan(createdAt: daysFromToday(-68), allowLate: true),
        [billsNow().first],
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('penalty'), findsNothing);
    });

    testWidgets(
        'two missed bills: the stretch once, the flat fee on each, Make '
        'payment on the earliest only', (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-98));
      final rows = clientRowsNow(loan, [paidCycle(daysFromToday(-68))]);
      final missed =
          rows.where((r) => r.id == NO_ID && !r.isPlaceholder).take(2).toList();
      expect(
        missed.map((r) => DateUtils.dateOnly(r.dueAt)),
        [daysFromToday(-38), daysFromToday(-8)],
      );

      await pumpRows(tester, loan, missed, loanRows: rows);

      expect(find.text('Overdue'), findsNWidgets(2));
      expect(
        find.textContaining('3,900.00 penalty · 38 days late'),
        findsOneWidget,
      );
      // The flat 100 once is per missed bill (owner, 2026-11-19).
      expect(
        find.textContaining('${100.0.toCurrency()} penalty · 8 days late'),
        findsOneWidget,
      );
      expect(find.textContaining('penalty'), findsNWidgets(2));
      final buttons = tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Make payment'),
          )
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons[0].onPressed, isNotNull);
      expect(
        buttons[1].onPressed,
        isNull,
        reason: 'a later computed bill waits for the earlier one',
      );
    });

    testWidgets('the principal-release row has no Make payment and no penalty',
        (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68));
      final principalRelease =
          clientRowsNow(loan, [paidCycle(daysFromToday(-38))]).first;
      expect(principalRelease.isPlaceholder, isTrue);
      expect(principalRelease.status, LoanStatus.not_paid);

      await pumpRows(tester, loan, [principalRelease]);

      expect(find.text('Make payment'), findsNothing);
      expect(find.textContaining('penalty'), findsNothing);
    });
  });

  testWidgets(
      'borrower schedule table: overdue label, the stretch once, the flat '
      'fee on each bill', (tester) async {
    final rows = billsNow(paidDaysAgo: 68);
    await tester.pumpApp(
      LoanScheduleWidget(
        amortization: 500,
        schedules: rows,
        completeTerm: 'Open term',
        buildTable: true,
        tableHeight: 4 * LoanScheduleWidget.rowHeight,
        loan: openTermLoan(createdAt: daysFromToday(-98)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(LoanStatus.not_paid_overdue.label), findsNWidgets(2));
    expect(find.textContaining('3,900.00 penalty'), findsOneWidget);
    expect(
      find.textContaining('${100.0.toCurrency()} penalty'),
      findsOneWidget,
    );
    expect(find.textContaining('penalty'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "borrower schedule table: a pending application's projected "
      'bill', (tester) async {
    final loan = openTermLoan(createdAt: daysFromToday(-68))
      ..status = LoanStatus.pending;
    await tester.pumpApp(
      LoanScheduleWidget(
        amortization: 500,
        schedules: clientRowsNow(loan, const [])
            .where((r) => !r.isPlaceholder)
            .toList(),
        completeTerm: 'Open term',
        buildTable: true,
        tableHeight: 2 * LoanScheduleWidget.rowHeight,
        loan: loan,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(LoanScheduleWidget.projectedLabel), findsOneWidget);
    expect(find.text(LoanStatus.not_paid_overdue.label), findsNothing);
    expect(find.textContaining('penalty'), findsNothing);
  });

  group('payment dialog breakdown (PaymentPenaltySection)', () {
    final sep8 = DateTime(2026, 9, 8, 12);
    List<LoanSchedule> rowsOn(DateTime now) =>
        LoanCalculationService.calculateOpenTermSchedules(
          amount: 10000,
          date: DateTime(2026, 7, 2),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(DateTime(2026, 8))],
          now: now,
        ).schedules;

    Future<void> pumpSection(
      WidgetTester tester,
      Loan loan,
      List<LoanSchedule> paying, {
      List<LoanSchedule> loanRows = const [],
      DateTime? collectedAt,
    }) {
      return tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: FormBuilder(
              child: PaymentPenaltySection(
                schedules: paying,
                loan: loan,
                initialCollectedAt: collectedAt ?? DateTime(2026, 9, 8),
                loanRows: loanRows,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('one missed bill collected Sep 8: 100 once + 8 days x 100',
        (tester) async {
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2)),
        [rowsOn(sep8).first],
      );

      expect(find.textContaining('Late fee'), findsOneWidget);
      expect(find.textContaining('Daily surcharge'), findsOneWidget);
      expect(find.textContaining('× 8'), findsOneWidget);
      expect(find.textContaining('800.00'), findsOneWidget);
      expect(find.text('Waive penalties'), findsOneWidget);
    });

    testWidgets(
        'two missed bills paid together: the stretch once, the flat fee on '
        'each', (tester) async {
      final oct5 = DateTime(2026, 10, 5, 12);
      final rows = rowsOn(oct5);
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2)),
        rows.sublist(0, 2),
        loanRows: rows,
        collectedAt: DateTime(2026, 10, 5),
      );

      expect(find.text('2 installments'), findsOneWidget);
      // The bills' amount due, not their balances (#142): 500 + 500, and
      // with the penalty 1,000 + 100 + 3,500 + the Sep 30 bill's flat 100
      // (per missed bill, owner 2026-11-19) = 4,700 (was 4,600; before #142
      // 20,000 / 23,600).
      expect(find.text(1000.toCurrency()), findsOneWidget);
      expect(find.text(4700.toCurrency()), findsOneWidget);
      expect(find.text(20000.toCurrency()), findsNothing);
      expect(find.textContaining('Late fee'), findsNWidgets(2));
      expect(find.textContaining('Daily surcharge'), findsOneWidget);
      expect(find.textContaining('× 35'), findsOneWidget);
      expect(find.textContaining('3,500.00'), findsOneWidget);
      expect(find.textContaining('× 5'), findsNothing);
    });

    testWidgets('allowed late: 8 days shown, nothing to charge or waive',
        (tester) async {
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2), allowLate: true),
        [rowsOn(sep8).first],
      );

      expect(
        find.textContaining('8 days late · late payments allowed'),
        findsOneWidget,
      );
      expect(find.textContaining('Late fee'), findsNothing);
      expect(find.text('Waive penalties'), findsNothing);
    });
  });

  group("borrower's Next payment and Pay in full", () {
    final sep8 = DateTime(2026, 9, 8, 12);

    List<LoanSchedule> clientSchedules(
      Loan loan, {
      DateTime? now,
      List<LoanSchedule>? stored,
    }) =>
        LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: loan.createdAt,
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: stored ?? [paidCycle(DateTime(2026, 8))],
          loan: loan,
          now: now ?? sep8,
        ).schedules;

    test('one missed bill: Next payment 1,400, Pay in full 1,900', () {
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan),
        loan: loan,
        asOf: sep8,
      );

      expect(due.unpaid, hasLength(2), reason: 'placeholders are not due');
      expect(due.nextDue!.isPlaceholder, isFalse);
      expect(DateUtils.dateOnly(due.nextDue!.dueAt), DateTime(2026, 8, 31));
      expect(due.payNow, [due.nextDue]);
      expect(due.nextDuePenalty, closeTo(900, 0.01));
      expect(due.nextDueAmount, closeTo(1400, 0.01));
      expect(due.remainingPenalty, closeTo(900, 0.01));
      expect(due.remainingTotal, closeTo(1900, 0.01));
    });

    test('two missed bills (seen Oct 5): both owed, 3,600 + 100 flat', () {
      final oct5 = DateTime(2026, 10, 5, 12);
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan, now: oct5),
        loan: loan,
        asOf: oct5,
      );

      expect(
        due.payNow.map((s) => DateUtils.dateOnly(s.dueAt)),
        [DateTime(2026, 8, 31), DateTime(2026, 9, 30)],
      );
      // 100 + 100 x 35 on Aug 31 + the Sep 30 bill's flat 100 (per missed
      // bill, owner 2026-11-19; was 3,600 / 4,600 / 5,100).
      expect(due.nextDuePenalty, closeTo(3700, 0.01));
      expect(due.nextDueAmount, closeTo(4700, 0.01));
      expect(due.remainingPenalty, closeTo(3700, 0.01));
      expect(due.remainingTotal, closeTo(5200, 0.01));
    });

    test('allowed late: 500 due, no penalty', () {
      final loan =
          openTermLoan(createdAt: DateTime(2026, 7, 2), allowLate: true);
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan),
        loan: loan,
        asOf: sep8,
      );

      expect(due.nextDueAmount, closeTo(500, 0.01));
      expect(due.remainingTotal, closeTo(1000, 0.01));
      expect(due.remainingPenalty, 0);
    });

    test('a top-up row is not an installment: only the bills are due', () {
      // Top-up 2,000 on Aug 20: the Aug 31 bill = 10,000 x 5% x 19/30 +
      // 12,000 x 5% x 11/30 = 316.67 + 220 = 536.67 (R5); Sep 30 = 600;
      // penalty on the bill's 12,000 balance: 100 + 120 x 8 = 1,060.
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2))
        ..additionalLoanAmounts = [
          AdditionalLoanAmount()
            ..id = 'top-1'
            ..amount = 2000
            ..additionalCharges = 0
            ..advanceCharges = 0
            ..createdAt = DateTime(2026, 8, 20)
            ..status = LoanStatus.approved,
        ];
      final schedules = clientSchedules(loan);
      expect(schedules.where((s) => s.isAdditionalLoanAmount), hasLength(1));

      final due = borrowerAmountsDue(
        schedules: schedules,
        loan: loan,
        asOf: sep8,
      );

      expect(due.unpaid, hasLength(2));
      expect(due.unpaid.any((s) => s.isPlaceholder), isFalse);
      expect(due.nextDueAmount, closeTo(536.67 + 1060, 0.01));
      expect(due.remainingTotal, closeTo(536.67 + 600 + 1060, 0.01));
    });

    test('a rejected submission: client detail and borrower count 900 once',
        () {
      // Submitted Sep 6 on the cycle due Aug 31, rejected (stored by #143's
      // app: due Sep 6, original due Aug 31, 36 days, 600). The next bill
      // is the scheduled Sep 30 (Jul 2 + 90), 24 days from Sep 6, not due.
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final rejected = rejectedSubmission(
        paidDue: DateTime(2026, 8),
        submittedAt: DateTime(2026, 9, 6, 12),
      );
      expect(rejected.interestCharge, closeTo(600, 0.01));

      final schedules = clientSchedules(
        loan,
        stored: [paidCycle(DateTime(2026, 8)), rejected],
      );
      expect(
        DateUtils.dateOnly(schedules.last.dueAt),
        DateTime(2026, 9, 30),
      );
      expect(schedules.last.interestCharge, closeTo(400, 0.01));

      final clientDetailPenalties = schedules.fold<double>(
        0,
        (sum, s) =>
            sum +
            previewPenalty(
              schedule: s,
              loan: loan,
              asOf: sep8,
              loanRows: schedules,
            ).total,
      );
      expect(clientDetailPenalties, closeTo(900, 0.01));

      final due = borrowerAmountsDue(
        schedules: schedules,
        loan: loan,
        asOf: sep8,
      );
      expect(due.nextDue!.id, 'sched-2');
      expect(due.nextDuePenalty, closeTo(900, 0.01));
      expect(due.remainingPenalty, closeTo(900, 0.01));
    });
  });

  group('Payment Center (bloc): overdue open-term bills', () {
    late _Loans loans;
    late _Schedules schedules;
    late _Payments payments;
    late _Users users;
    var loanCreatedDaysAgo = 68;
    var loanTopUps = <AdditionalLoanAmount>[];

    setUpAll(() {
      registerFallbackValue(Loan());
      registerFallbackValue(LoanSchedule());
      registerFallbackValue(Payment());
    });

    void stubStored(List<LoanSchedule> Function() rows) {
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => rows());
    }

    setUp(() {
      loans = _Loans();
      schedules = _Schedules();
      payments = _Payments();
      users = _Users();
      loanCreatedDaysAgo = 68;
      loanTopUps = [];
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
          includeAdditionalLoanAmounts:
              any(named: 'includeAdditionalLoanAmounts'),
        ),
      ).thenAnswer((invocation) async {
        final statements =
            invocation.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [
                openTermLoan(createdAt: daysFromToday(-loanCreatedDaysAgo))
                  ..additionalLoanAmounts = List.of(loanTopUps),
              ]
            : <Loan>[];
      });
      stubStored(() => [paidCycle(daysFromToday(-38))]);
    });

    PaymentCenterBloc newBloc() {
      final auth = _Auth();
      when(() => auth.company).thenReturn(
        Company()
          ..id = 'co-1'
          ..managementType = CompanyManagementType.selfManaged,
      );
      when(() => auth.user).thenReturn(
        User()
          ..id = 'teller-1'
          ..firstName = 'Tess'
          ..lastName = 'Teller'
          ..emailAddress = 'teller@example.com',
      );
      final bloc = PaymentCenterBloc.withDependencies(
        userRepository: users,
        loanRepository: loans,
        loanScheduleRepository: schedules,
        paymentRepository: payments,
        storageRepository: _Storage(),
        authService: auth,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    Future<List<LoanSchedule>> actionable() async {
      final bloc = newBloc()
        ..add(SelectBorrowerEvent(borrower: User()..id = 'u1'));
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == PaymentCenterStatus.borrowerSelected ||
            s.status == PaymentCenterStatus.error,
      );
      expect(state.status, PaymentCenterStatus.borrowerSelected);

      return state.borrowerLoans.single.actionableSchedules;
    }

    Iterable<LoanSchedule> overdueOf(List<LoanSchedule> rows) =>
        rows.where((r) => r.status == LoanStatus.not_paid_overdue);

    /// What the dialog shows and the bulk handler stores for the overdue
    /// rows paid together now.
    List<double> penaltiesOf(
      Iterable<LoanSchedule> rows,
      List<LoanSchedule> stored,
    ) =>
        resolveLatenessTogether(
          schedules: rows.toList(),
          loan: openTermLoan(createdAt: daysFromToday(-loanCreatedDaysAgo)),
          collectedAt: DateTime.now(),
          loanRows: stored,
        ).map((r) => r.penalties.total).toList();

    test('one missed bill: listed overdue on its own date, 500', () async {
      final rows = await actionable();

      expect(rows, hasLength(2));
      final missed = rows.first;
      expect(missed.isOpenTerm, isTrue);
      expect(missed.status, LoanStatus.not_paid_overdue);
      expect(DateUtils.dateOnly(missed.dueAt), daysFromToday(-8));
      expect(missed.originalDueAt, isNull);
      expect(missed.interestCharge, closeTo(500, 0.01));
      expect(rows.last.status, LoanStatus.not_paid);
      expect(DateUtils.dateOnly(rows.last.dueAt), daysFromToday(22));

      final status = PaymentConfirmationService.applyLateness(
        schedule: missed,
        loan: openTermLoan(createdAt: daysFromToday(-68)),
        collectedAt: DateTime.now(),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_late);
      expect(missed.daysLate, 8);
      expect(missed.penalty, closeTo(900, 0.01));
    });

    testWidgets('two missed bills: one overdue tile, both dates, 1,000',
        (tester) async {
      loanCreatedDaysAgo = 98;
      stubStored(() => [paidCycle(daysFromToday(-68))]);
      final rows = await tester.runAsync(actionable);
      final overdue = overdueOf(rows!).toList();
      expect(overdue, hasLength(2));
      expect(
        penaltiesOf(overdue, [paidCycle(daysFromToday(-68))]),
        // The flat 100 once on each missed bill (owner 2026-11-19; was 0).
        [closeTo(3900, 0.01), closeTo(100, 0.01)],
      );

      await tester.pumpApp(
        Scaffold(
          body: OverdueSummaryTile(
            overdueSchedules: overdue,
            onPay: () {},
            readOnly: true,
          ),
        ),
      );

      expect(find.text('Overdue - 2 payments'), findsOneWidget);
      expect(
        find.text(
          '${daysFromToday(-38).toDefaultDateFormat()}'
          ' — ${daysFromToday(-8).toDefaultDateFormat()}',
        ),
        findsOneWidget,
      );
      expect(find.text(1000.toCurrency()), findsOneWidget);
    });

    group('bulk overdue payment (the real handler)', () {
      late List<LoanSchedule> written;
      late List<Payment> paymentDocs;
      late List<LoanStatus> loanStatuses;

      setUp(() {
        loanCreatedDaysAgo = 98;
        stubStored(() => [paidCycle(daysFromToday(-68))]);
        written = [];
        paymentDocs = [];
        loanStatuses = [];
        var paymentCount = 0;
        when(() => users.get(id: any(named: 'id'))).thenAnswer(
          (_) async => User()
            ..id = 'u1'
            ..firstName = 'Bea'
            ..lastName = 'Borrower'
            ..emailAddress = 'bea@example.com',
        );
        when(() => payments.add(data: any(named: 'data'))).thenAnswer(
          (invocation) async {
            final payment = (invocation.namedArguments[#data] as Payment)
              ..id = 'pay-${++paymentCount}';
            paymentDocs.add(payment);
            return payment;
          },
        );
        when(() => payments.update(data: any(named: 'data'))).thenAnswer(
          (invocation) async => invocation.namedArguments[#data] as Payment,
        );
        when(() => schedules.add(data: any(named: 'data'))).thenAnswer(
          (invocation) async {
            final row = (invocation.namedArguments[#data] as LoanSchedule)
              ..id = 'stored-${written.length + 1}';
            written.add(row);
            return row;
          },
        );
        when(
          () => loans.update(
            data: any(named: 'data'),
            updateView: any(named: 'updateView'),
          ),
        ).thenAnswer((invocation) async {
          final loan = invocation.namedArguments[#data] as Loan;
          loanStatuses.add(loan.status);
          return loan;
        });
        when(() => loans.get(id: any(named: 'id'))).thenAnswer(
          (_) async => openTermLoan(createdAt: daysFromToday(-98)),
        );
      });

      Future<void> payOverdue(double totalInterest) async {
        final overdue = overdueOf(await actionable()).toList();
        final bloc = newBloc()
          ..add(
            MakeOverduePaymentEvent(
              loan: openTermLoan(createdAt: daysFromToday(-98))
                ..additionalLoanAmounts = List.of(loanTopUps),
              schedules: overdue,
              totalPrincipalPayment: 0,
              totalInterestPayment: totalInterest,
              otpVerified: true,
            ),
          );
        // The handler writes every row and the loan, then stops at the
        // cash-pool step (its repository cannot be mocked).
        await bloc.stream.firstWhere(
          (s) =>
              s.status == PaymentCenterStatus.error ||
              s.status == PaymentCenterStatus.paymentSuccess,
        );
      }

      test('1,000 pays both bills; the stretch once, the flat fee on each',
          () async {
        await payOverdue(1000);

        expect(written, hasLength(2));
        expect(
          written.map((r) => r.status),
          everyElement(LoanStatus.paid_late),
        );
        expect(written.map((r) => r.daysLate), [38, 8]);
        // 100 + 3,800 on the first; the flat 100 once on the second too
        // (per missed bill, owner 2026-11-19; was 0).
        expect(
          written.map((r) => r.penalty),
          [closeTo(3900, 0.01), closeTo(100, 0.01)],
        );
        expect(written.map((r) => r.interestPayment), [500, 500]);
        expect(written.map((r) => r.originalDueAt), [null, null]);
        expect(
          written.map((r) => DateUtils.dateOnly(r.dueAt)),
          [daysFromToday(-38), daysFromToday(-8)],
        );
        // One confirmed payment per bill, linked both ways.
        expect(paymentDocs, hasLength(2));
        expect(
          paymentDocs.map((p) => p.status),
          everyElement(PaymentStatus.confirmed),
        );
        expect(
          paymentDocs.map((p) => p.loanScheduleId),
          ['stored-1', 'stored-2'],
        );
        expect(written.map((r) => r.paymentId), ['pay-1', 'pay-2']);
        expect(
          paymentDocs.map((p) => p.confirmedBy),
          ['teller-1', 'teller-1'],
        );
        expect(loanStatuses, [LoanStatus.paid_late]);
      });

      test('700 pays 500 + 200: the 300 short carries to the next bill',
          () async {
        await payOverdue(700);

        expect(written.map((r) => r.interestPayment), [500, 200]);
        expect(loanStatuses, [LoanStatus.paid_late]);
        final next = LoanCalculationService.calculateOpenTermSchedules(
          amount: 10000,
          date: daysFromToday(-98),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(daysFromToday(-68)), ...written],
        ).schedules.single;
        expect(DateUtils.dateOnly(next.dueAt), daysFromToday(22));
        expect(next.amortization, closeTo(800, 0.01));
      });

      test('400 pays the first bill only; the loan stays overdue', () async {
        await payOverdue(400);

        expect(written, hasLength(1));
        expect(written.single.interestPayment, 400);
        expect(written.single.penalty, closeTo(3900, 0.01));
        expect(paymentDocs, hasLength(1));
        expect(
          loanStatuses,
          [LoanStatus.not_paid_overdue],
          reason: 'the earliest bill still unpaid (was paid_late)',
        );
      });

      test('an older pending submission does not stretch the next bill: 900',
          () async {
        // Bill A (due 38 days ago) was submitted 30 days ago by an app build
        // that did not record the transfer time, and is still pending. The
        // teller bulk-pays bill B (due 8 days ago): A stopped being late at
        // its transfer, so B owes its own 8 days, 100 + 100 x 8 = 900
        // (second review of #146: 3,900, A counted as unpaid).
        LoanSchedule submittedA() =>
            LoanCalculationService.calculateOpenTermSchedules(
              amount: 10000,
              date: daysFromToday(-98),
              interestRate: 5,
              term: '1m',
              companyId: 'co-1',
              paidSchedules: [paidCycle(daysFromToday(-68))],
            ).schedules.first
              ..id = 'sched-A'
              ..loanId = 'loan-1'
              ..status = LoanStatus.payment_submitted
              ..paymentId = 'pay-A';
        stubStored(() => [paidCycle(daysFromToday(-68)), submittedA()]);
        when(() => payments.get(id: any(named: 'id'))).thenAnswer(
          (_) async => Payment()
            ..id = 'pay-A'
            ..loanScheduleId = 'sched-A'
            ..createdAt = daysFromToday(-30).add(const Duration(hours: 12))
            ..status = PaymentStatus.pending,
        );

        await payOverdue(500);

        expect(written, hasLength(1));
        expect(DateUtils.dateOnly(written.single.dueAt), daysFromToday(-8));
        expect(written.single.penalty, closeTo(900, 0.01));

        // Client detail and the borrower (LoansBloc settles the stored rows
        // the same way before computing): B is due with 900, not 0.
        final stored = [paidCycle(daysFromToday(-68)), submittedA()];
        await PaymentConfirmationService.settleSubmittedAtTheirTransfer(
          stored,
          payments,
        );
        final loan = openTermLoan(createdAt: daysFromToday(-98));
        final due = borrowerAmountsDue(
          schedules: clientRowsNow(loan, stored),
          loan: loan,
        );
        expect(due.payNow.map((r) => DateUtils.dateOnly(r.dueAt)), [
          daysFromToday(-8),
        ]);
        expect(due.nextDuePenalty, closeTo(900, 0.01));
        expect(due.nextDueAmount, closeTo(1400, 0.01));
      });

      test(
          'with a top-up: both screens bill the same, and the next bill '
          'keeps it (605, not 500)', () async {
        // Top-up 2,000 + 100 fifty days ago (#135): the -38 bill = 10,000 x
        // 5% x 18/30 + 12,100 x 5% x 12/30 = 300 + 242 = 542; the -8 bill =
        // 12,100 x 5% = 605; after both are paid the +22 bill is 605.
        loanTopUps = [
          AdditionalLoanAmount()
            ..id = 'top-1'
            ..amount = 2000
            ..additionalCharges = 100
            ..advanceCharges = 0
            ..createdAt = daysFromToday(-50)
            ..status = LoanStatus.approved,
        ];
        final overdue = overdueOf(await actionable()).toList();
        verify(
          () => loans.load(
            statements: any(named: 'statements'),
            limit: any(named: 'limit'),
            page: any(named: 'page'),
            reset: any(named: 'reset'),
            includeAdditionalLoanAmounts:
                any(named: 'includeAdditionalLoanAmounts', that: isTrue),
          ),
        ).called(greaterThan(0));
        expect(
          overdue.map((r) => r.interestCharge.toStringAsFixed(2)),
          ['542.00', '605.00'],
        );

        final loan = openTermLoan(createdAt: daysFromToday(-98))
          ..additionalLoanAmounts = List.of(loanTopUps);
        final clientDetail =
            clientRowsNow(loan, [paidCycle(daysFromToday(-68))])
                .where((r) => r.id == NO_ID && !r.isPlaceholder)
                .take(2);
        expect(
          clientDetail.map((r) => (r.outstandingBalance, r.interestCharge)),
          overdue.map((r) => (r.outstandingBalance, r.interestCharge)),
        );

        await payOverdue(542 + 605);
        expect(written.map((r) => r.outstandingBalance), [12100, 12100]);
        final next = LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: daysFromToday(-98),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(daysFromToday(-68)), ...written],
          loan: loan,
        ).schedules.last;
        expect(DateUtils.dateOnly(next.dueAt), daysFromToday(22));
        expect(next.interestCharge, closeTo(605, 0.01));
      });
    });

    group('after a rejected submission', () {
      /// The paid cycle and a submission on the next cycle that was rejected,
      /// as Firestore returns them.
      List<LoanSchedule> storedRows({
        required int paidDaysAgo,
        required int submittedDaysAgo,
        bool storedBefore114 = false,
      }) =>
          [
            paidCycle(daysFromToday(-paidDaysAgo)),
            rejectedSubmission(
              paidDue: daysFromToday(-paidDaysAgo),
              submittedAt: daysFromToday(-submittedDaysAgo)
                  .add(const Duration(hours: 12)),
              storedBefore114: storedBefore114,
            ),
          ];

      double penaltyOf(Iterable<LoanSchedule> rows) => rows.fold<double>(
            0,
            (sum, r) =>
                sum +
                resolveLateness(
                  schedule: r,
                  loan: openTermLoan(createdAt: daysFromToday(-68)),
                  collectedAt: DateTime.now(),
                ).penalties.total,
          );

      test('the stored row is the overdue cycle: 900, interest once', () async {
        stubStored(() => storedRows(paidDaysAgo: 38, submittedDaysAgo: 2));
        final rows = await actionable();

        expect(overdueOf(rows).map((r) => r.id), ['sched-2']);
        expect(rows.first.interestCharge, closeTo(600, 0.01));
        expect(penaltyOf(rows), closeTo(900, 0.01));
        // The next bill is the scheduled +22, upcoming, as on client detail.
        expect(rows, hasLength(2));
        expect(rows.last.status, LoanStatus.not_paid);
        expect(rows.last.lateFrom, daysFromToday(22));
        expect(rows.last.interestCharge, closeTo(400, 0.01));
      });

      test('a row stored before #114 counts from its own date (300)', () async {
        stubStored(
          () => storedRows(
            paidDaysAgo: 38,
            submittedDaysAgo: 2,
            storedBefore114: true,
          ),
        );
        final rows = await actionable();

        expect(overdueOf(rows).map((r) => r.id), ['sched-2']);
        expect(rows.first.originalDueAt, isNull);
        expect(penaltyOf(rows), closeTo(300, 0.01));
      });

      test(
          'a top-up before the rejected submission: the stored row is shown '
          'and confirmed as stored (15,000, 500, 7,600)', () async {
        final topUp = AdditionalLoanAmount()
          ..id = 'top-1'
          ..amount = 5000
          ..additionalCharges = 0
          ..advanceCharges = 0
          ..createdAt = daysFromToday(-50)
          ..status = LoanStatus.approved;
        final storedJson = rejectedSubmission(
          paidDue: daysFromToday(-80),
          submittedAt: daysFromToday(-45).add(const Duration(hours: 12)),
          balance: 15000,
          interestCharge: 500,
        ).toJson();

        stubStored(
          () => [
            paidCycle(daysFromToday(-80)),
            LoanScheduleEntity.fromJson(storedJson).toLoanSchedule(),
          ],
        );
        loanCreatedDaysAgo = 110;
        loanTopUps = [topUp];

        final rows = await actionable();
        final stored = rows.firstWhere((r) => r.id == 'sched-2');
        expect(stored.outstandingBalance, closeTo(15000, 0.01));
        expect(stored.interestCharge, closeTo(500, 0.01));
        expect(penaltyOf([stored]), closeTo(7600, 0.01));
        final next = rows.firstWhere((r) => r.id == NO_ID);
        expect(DateUtils.dateOnly(next.dueAt), daysFromToday(-20));
        expect(
          next.interestCharge,
          closeTo(625, 0.01),
          reason: 'the top-up is in the stored balance, not added again',
        );

        // What the bulk handler does with the row before writing it.
        final status = PaymentConfirmationService.applyLateness(
          schedule: stored,
          loan: openTermLoan(createdAt: daysFromToday(-110)),
          collectedAt: DateTime.now(),
          actorId: 'teller-1',
        );
        expect(status, LoanStatus.paid_late);
        expect(stored.penalty, closeTo(7600, 0.01));
        expect(stored.outstandingBalance, closeTo(15000, 0.01));
        expect(stored.interestCharge, closeTo(500, 0.01));
      });

      test(
          'a rejection more than a term old: the Payment Center, client '
          'detail and the borrower show the same rows, 5,100 + 100', () async {
        stubStored(() => storedRows(paidDaysAgo: 80, submittedDaysAgo: 45));
        loanCreatedDaysAgo = 110;

        final paymentCenter = await actionable();
        final overdue = overdueOf(paymentCenter).toList();
        expect(overdue, hasLength(2));
        expect(overdue.first.id, 'sched-2');
        expect(overdue.first.interestCharge, closeTo(583.33, 0.01));
        expect(overdue.last.lateFrom, daysFromToday(-20));
        expect(overdue.last.interestCharge, closeTo(416.67, 0.01));
        expect(paymentCenter.last.lateFrom, daysFromToday(10));
        final stored = storedRows(paidDaysAgo: 80, submittedDaysAgo: 45);
        // The stretch once; the flat 100 once on the -20 bill too (per
        // missed bill, owner 2026-11-19; was 0).
        expect(
          penaltiesOf(overdue, stored),
          [closeTo(5100, 0.01), closeTo(100, 0.01)],
        );

        // What LoansBloc computes for client detail and the borrower: every
        // stored row goes to the engine (loans_bloc.dart, _calculateLoanOpen).
        final loan = openTermLoan(createdAt: daysFromToday(-110));
        final clientSchedules = clientRowsNow(loan, stored);
        final due = borrowerAmountsDue(schedules: clientSchedules, loan: loan);

        expect(
          due.unpaid.map((r) => r.lateFrom),
          paymentCenter.map((r) => r.lateFrom),
        );
        expect(due.remainingPenalty, closeTo(5200, 0.01));
        expect(due.remainingTotal, closeTo(6616.67, 0.01));
        expect(
          clientSchedules.fold<double>(
            0,
            (sum, s) =>
                sum +
                previewPenalty(
                  schedule: s,
                  loan: loan,
                  loanRows: clientSchedules,
                ).total,
          ),
          closeTo(5200, 0.01),
        );
      });
    });

    test('fixed-term rows merge by the day in the business zone (UTC+8)', () {
      // Every test runs under TZ=UTC, so the zone is passed in. A row stored
      // for Sep 15 in Manila comes back from Firestore as Sep 14 16:00Z; the
      // row regenerated on a Manila device reads Sep 15. One cycle.
      LoanSchedule fixedRow(DateTime dueAt, {String id = NO_ID}) =>
          LoanSchedule()
            ..id = id
            ..dueAt = dueAt
            ..status = LoanStatus.not_paid
            ..isOpenTerm = false;
      const manila = Duration(hours: 8);

      final merged = PaymentCenterBloc.mergeUnpaid(
        [fixedRow(DateTime.utc(2026, 9, 14, 16), id: 'sched-3')],
        [fixedRow(DateTime(2026, 9, 15)), fixedRow(DateTime(2026, 10, 15))],
        utcOffset: manila,
      );
      expect(merged.map((s) => s.id), ['sched-3', NO_ID]);
      expect(merged.last.dueAt, DateTime(2026, 10, 15));

      // 15:59Z is still Sep 14 in Manila: a different cycle.
      expect(
        PaymentCenterBloc.mergeUnpaid(
          [fixedRow(DateTime.utc(2026, 9, 14, 15, 59), id: 'sched-3')],
          [fixedRow(DateTime(2026, 9, 15))],
          utcOffset: manila,
        ),
        hasLength(2),
      );
    });
  });

  group('review of #146: payable rows and loan status', () {
    setUp(() {
      AuthenticationService.instance
        ..user = (User()
          ..id = 'teller-1'
          ..userRole = UserRole.admin)
        ..company = (Company()
          ..id = 'co-1'
          ..managementType = CompanyManagementType.selfManaged);
    });

    Future<List<OutlinedButton>> pumpButtons(
      WidgetTester tester,
      Loan loan,
      List<LoanSchedule> rows,
    ) async {
      tester.view
        ..physicalSize = const Size(2400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: [
              for (final row in rows.where((r) => !r.isPlaceholder))
                ClientDetailScheduleItem(
                  index: 2,
                  schedule: row,
                  onMakePayment: (_) {},
                  loan: loan,
                  loanRows: rows,
                ),
            ],
          ),
        ),
      );

      return tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Make payment'),
          )
          .toList();
    }

    testWidgets('a rejected stored row is payable; the bill after it waits',
        (tester) async {
      // Rejected submission (due 2 days ago, cycle due 8 days ago) and the
      // scheduled +22 bill computed after it.
      final loan = openTermLoan(createdAt: daysFromToday(-68));
      final rows = clientRowsNow(loan, [
        paidCycle(daysFromToday(-38)),
        rejectedSubmission(
          paidDue: daysFromToday(-38),
          submittedAt: daysFromToday(-2).add(const Duration(hours: 12)),
        ),
      ]);
      final buttons = await pumpButtons(tester, loan, rows);

      // Rows with a button: the rejected stored row and the computed bill
      // (the paid row has none).
      expect(buttons, hasLength(2));
      expect(buttons[0].onPressed, isNotNull, reason: 'the rejected row');
      expect(buttons[1].onPressed, isNull, reason: 'the later computed bill');
    });

    testWidgets('a pending application: its projected first bill, read only',
        (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68))
        ..status = LoanStatus.pending;
      final rows = clientRowsNow(loan, const []);
      final projected = rows.where((r) => r.id == NO_ID && !r.isPlaceholder);
      expect(projected, hasLength(1));
      expect(DateUtils.dateOnly(projected.single.dueAt), daysFromToday(-38));

      final buttons = await pumpButtons(tester, loan, rows);
      expect(buttons.map((b) => b.onPressed), everyElement(isNull));
      expect(find.textContaining('penalty'), findsNothing);
      expect(borrowerAmountsDue(schedules: rows, loan: loan).unpaid, isEmpty);
      // Its money was never released: projected, not overdue.
      expect(find.text(LoanScheduleWidget.projectedLabel), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets(
        'the principal release approval stored has no Make payment '
        '(#138)', (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68));
      final release = storedRelease(createdAt: daysFromToday(-68));
      final rows = clientRowsNow(loan, [release]);
      await pumpButtons(tester, loan, [release]);

      expect(find.text('Make payment'), findsNothing);
      expect(
        borrowerAmountsDue(schedules: rows, loan: loan)
            .unpaid
            .any((r) => r.id == 'planned'),
        isFalse,
        reason: "not the borrower's next payment either",
      );
    });

    testWidgets('a settled loan: no bill, no Make payment, no penalty',
        (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68))
        ..status = LoanStatus.completed;
      final rows = clientRowsNow(loan, [
        paidCycle(daysFromToday(-38)),
        rejectedSubmission(
          paidDue: daysFromToday(-38),
          submittedAt: daysFromToday(-2).add(const Duration(hours: 12)),
        ),
      ]);
      expect(rows.where((r) => r.id == NO_ID && !r.isPlaceholder), isEmpty);

      final buttons = await pumpButtons(tester, loan, rows);
      expect(buttons.map((b) => b.onPressed), everyElement(isNull));
      expect(find.textContaining('penalty'), findsNothing);
    });
  });

  group('Payment Center (bloc): loan status and rows', () {
    late _Loans loans;
    late _Schedules schedules;
    var status = LoanStatus.approved;

    setUpAll(() {
      registerFallbackValue(Loan());
    });

    setUp(() {
      loans = _Loans();
      schedules = _Schedules();
      status = LoanStatus.approved;
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
          includeAdditionalLoanAmounts:
              any(named: 'includeAdditionalLoanAmounts'),
        ),
      ).thenAnswer((invocation) async {
        final statements =
            invocation.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [openTermLoan(createdAt: daysFromToday(-68))..status = status]
            : <Loan>[];
      });
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => [paidCycle(daysFromToday(-38))]);
    });

    Future<PaymentCenterBloc> selected() async {
      final auth = _Auth();
      when(() => auth.company).thenReturn(Company()..id = 'co-1');
      final bloc = PaymentCenterBloc.withDependencies(
        userRepository: _Users(),
        loanRepository: loans,
        loanScheduleRepository: schedules,
        paymentRepository: _Payments(),
        storageRepository: _Storage(),
        authService: auth,
      )..add(SelectBorrowerEvent(borrower: User()..id = 'u1'));
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(
        (s) => s.status == PaymentCenterStatus.borrowerSelected,
      );
      return bloc;
    }

    test('the single-payment path gets the stored and listed rows', () async {
      final bloc = await selected();
      final rows = bloc.loanRowsOf('loan-1');

      expect(rows.map((r) => r.id), ['sched-1', NO_ID, NO_ID]);
      expect(
        rows.skip(1).map((r) => DateUtils.dateOnly(r.dueAt)),
        [daysFromToday(-8), daysFromToday(22)],
      );
    });

    test(
        'a principal release left unpaid by a rejected submission is not '
        'listed (#138)', () async {
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer(
        (_) async => [
          storedRelease(
            createdAt: daysFromToday(-68),
            status: LoanStatus.not_paid_overdue,
          ),
          paidCycle(daysFromToday(-38)),
        ],
      );
      final bloc = await selected();

      expect(
        bloc.state.borrowerLoans.single.actionableSchedules
            .any((r) => r.id == 'planned'),
        isFalse,
      );
    });

    for (final inactive in [
      LoanStatus.pending,
      LoanStatus.declined,
      LoanStatus.completed,
      LoanStatus.bad_debt,
    ]) {
      test('a ${inactive.name} loan lists nothing to pay', () async {
        status = inactive;
        final bloc = await selected();

        expect(bloc.state.borrowerLoans.single.actionableSchedules, isEmpty);
      });
    }
  });

  group('borrower submissions on an open-term loan (the real confirm)', () {
    // Bills A (due Aug 31) and B (due Sep 30) of the G13 loan (10,000 at 5%,
    // paid cycle Aug 1; 100 once + 1% a day). A was submitted Sep 8, B on
    // Oct 8. Each is settled at its own transfer: A is 8 days late (900), B
    // is 8 days late (900), in either order of confirmation: 1,800 (review
    // of #146: B first charged 3,900 + 900 = 4,800, because the submitted A
    // still counted as unpaid).
    final sep8 = DateTime(2026, 9, 8, 12);
    final oct8 = DateTime(2026, 10, 8, 12);
    late Map<String, Map<String, dynamic>> stored;
    late Map<String, Payment> paymentDocs;
    late List<LoanStatus> loanStatuses;
    late PaymentConfirmationService service;
    var loanPenalties = const [lateFee100, daily1pct];

    LoanSchedule read(String id) =>
        LoanScheduleEntity.fromJson(stored[id]!).toLoanSchedule();

    /// Bills A and B submitted Sep 8 and Oct 8, or both in one submission
    /// on [together].
    void seed({required bool recordTransfer, DateTime? together}) {
      final bills = LoanCalculationService.calculateOpenTermSchedules(
        amount: 10000,
        date: DateTime(2026, 7, 2),
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [paidCycle(DateTime(2026, 8))],
        now: oct8,
      ).schedules;
      LoanSchedule submitted(LoanSchedule bill, String id, DateTime at) => bill
        ..id = id
        ..loanId = 'loan-1'
        ..status = LoanStatus.payment_submitted
        ..paymentId = 'pay-$id'
        ..collectedAt = recordTransfer ? at : null;

      stored = {
        'sched-1': paidCycle(DateTime(2026, 8)).toJson(),
        'A': submitted(bills[0], 'A', together ?? sep8).toJson(),
        'B': submitted(bills[1], 'B', together ?? oct8).toJson(),
      };
      paymentDocs = {
        for (final (id, at) in [
          ('A', together ?? sep8),
          ('B', together ?? oct8),
        ])
          'pay-$id': Payment()
            ..id = 'pay-$id'
            ..loanScheduleId = id
            ..createdAt = at
            ..status = PaymentStatus.pending,
      };
    }

    setUpAll(() {
      registerFallbackValue(Loan());
      registerFallbackValue(LoanSchedule());
      registerFallbackValue(Payment());
    });

    setUp(() {
      final schedules = _Schedules();
      final loans = _Loans();
      final payments = _Payments();
      loanStatuses = [];
      when(() => schedules.get(id: any(named: 'id'))).thenAnswer(
        (invocation) async => read(invocation.namedArguments[#id] as String),
      );
      when(
        () => schedules.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer((_) async => [for (final id in stored.keys) read(id)]);
      when(() => schedules.update(data: any(named: 'data'))).thenAnswer(
        (invocation) async {
          final row = invocation.namedArguments[#data] as LoanSchedule;
          stored[row.id] = row.toJson();
          return row;
        },
      );
      loanPenalties = const [lateFee100, daily1pct];
      when(() => loans.get(id: any(named: 'id'))).thenAnswer(
        (_) async => openTermLoan(createdAt: DateTime(2026, 7, 2))
          ..penalties = List.of(loanPenalties),
      );
      when(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      ).thenAnswer((invocation) async {
        final loan = invocation.namedArguments[#data] as Loan;
        loanStatuses.add(loan.status);
        return loan;
      });
      when(() => payments.get(id: any(named: 'id'))).thenAnswer(
        (invocation) async =>
            paymentDocs[invocation.namedArguments[#id] as String]!,
      );
      when(() => payments.update(data: any(named: 'data'))).thenAnswer(
        (invocation) async => invocation.namedArguments[#data] as Payment,
      );
      service = PaymentConfirmationService(
        loanScheduleRepository: schedules,
        loanRepository: loans,
        paymentRepository: payments,
      );
    });

    for (final recordTransfer in [true, false]) {
      for (final order in [
        ['A', 'B'],
        ['B', 'A'],
      ]) {
        test(
            'confirm ${order.join(' then ')}'
            '${recordTransfer ? '' : ' (rows submitted before the transfer '
                'time was recorded)'}: 900 + 900', () async {
          seed(recordTransfer: recordTransfer);
          for (final id in order) {
            await service.confirm(
              payment: paymentDocs['pay-$id']!,
              confirmedById: 'teller-1',
            );
          }

          for (final id in ['A', 'B']) {
            final row = read(id);
            // A submission is interest only: the interest due, principal 0.
            expect(row.principalPayment, 0, reason: id);
            expect(row.interestPayment, closeTo(500, 0.01), reason: id);
            expect(row.status, LoanStatus.paid_late, reason: id);
            expect(row.daysLate, 8, reason: id);
            expect(row.penalty, closeTo(900, 0.01), reason: id);
            expect(row.paymentId, 'pay-$id');
            expect(paymentDocs['pay-$id']!.status, PaymentStatus.confirmed);
          }
          expect(loanStatuses, [LoanStatus.paid_late, LoanStatus.paid_late]);
        });
      }
    }

    test(
        'the preview equals the charge: B owes 900 before and after it is '
        'submitted', () {
      seed(recordTransfer: true);
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final rows = [for (final id in stored.keys) read(id)];
      final unpaidB = read('B')
        ..status = LoanStatus.not_paid
        ..paymentId = null
        ..collectedAt = null;

      expect(
        previewPenalty(
          schedule: unpaidB,
          loan: loan,
          asOf: oct8,
          loanRows: [rows[0], rows[1], unpaidB],
        ).total,
        closeTo(900, 0.01),
        reason: 'the borrower before submitting (was 0 behind the submitted A)',
      );
      expect(
        resolveLatenessTogether(
          schedules: [read('B')],
          loan: loan,
          collectedAt: oct8,
          loanRows: rows,
        ).single.penalties.total,
        closeTo(900, 0.01),
        reason: 'the Payment Center card (was 3,900)',
      );
    });

    for (final order in [
      ['A', 'B'],
      ['B', 'A'],
    ]) {
      test(
          'ONE submission of both bills (Oct 5), 100 once + 0.1% a day, '
          'confirm ${order.join(' then ')}: the stretch once, 450 + 100',
          () async {
        // Aug 31 -> Oct 5 = 35 days: 35 x 10 = 350 once (second review of
        // #146: 0, each unconfirmed bill counted as already charged), plus
        // the flat 100 on each bill (per missed bill, owner 2026-11-19; was
        // 450 in all): the first confirmed 450, the other 100.
        loanPenalties = const [lateFee100, daily01pct];
        seed(recordTransfer: true, together: DateTime(2026, 10, 5, 12));
        for (final id in order) {
          await service.confirm(
            payment: paymentDocs['pay-$id']!,
            confirmedById: 'teller-1',
          );
        }

        expect(read('A').daysLate, 35);
        expect(read('B').daysLate, 5);
        expect(
          read('A').penalty + read('B').penalty,
          closeTo(550, 0.01),
        );
        expect(
          read(order.first).penalty,
          closeTo(450, 0.01),
          reason: 'the first one confirmed carries the stretch',
        );
        expect(read(order.last).penalty, closeTo(100, 0.01));
      });
    }

    test('a submitted clamp row from an older build carries its 1,100',
        () async {
      // Clamp row: interest Aug 1 -> Nov 5 (96 days) 1,600, 500 shown and
      // paid by the borrower; confirmed, it records 500 paid, so the next
      // bill (Nov 29, 24 days, 400) owes 400 + 1,100 = 1,500 (second
      // review: it recorded 0 and carried nothing).
      stored = {
        'sched-1': paidCycle(DateTime(2026, 8)).toJson(),
        'C': (LoanSchedule()
              ..id = 'C'
              ..loanId = 'loan-1'
              ..companyId = 'co-1'
              ..createdAt = DateTime(2026, 11, 5, 12)
              ..updatedAt = DateTime(2026, 11, 5, 12)
              ..dueAt = DateTime(2026, 11, 5)
              ..status = LoanStatus.payment_submitted
              ..paymentId = 'pay-C'
              ..isOpenTerm = true
              ..outstandingBalance = 10000
              ..principalPayment = 0
              ..interestPayment = 0
              ..interestCharge = 1600
              ..amortization = 500
              ..extraPayment = 0
              ..advanceInterestPayments = 0
              ..interestDayMultiplier = 96 / 30)
            .toJson(),
      };
      paymentDocs = {
        'pay-C': Payment()
          ..id = 'pay-C'
          ..loanScheduleId = 'C'
          ..createdAt = DateTime(2026, 11, 5, 12)
          ..status = PaymentStatus.pending,
      };
      await service.confirm(
        payment: paymentDocs['pay-C']!,
        confirmedById: 'teller-1',
      );

      expect(read('C').interestPayment, 500);
      final next = LoanCalculationService.calculateOpenTermSchedules(
        amount: 10000,
        date: DateTime(2026, 7, 2),
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [read('sched-1'), read('C')],
        now: DateTime(2026, 11, 20, 12),
      ).schedules.single;
      expect(DateUtils.dateOnly(next.dueAt), DateTime(2026, 11, 29));
      expect(next.interestCharge, closeTo(400, 0.01));
      expect(next.amortization, closeTo(1500, 0.01));
    });

    test('the principal release is never confirmed as a payment (#138)',
        () async {
      stored = {
        'planned': storedRelease(
          createdAt: DateTime(2026, 7, 2),
          status: LoanStatus.payment_submitted,
        ).toJson(),
      };
      paymentDocs = {
        'pay-planned': Payment()
          ..id = 'pay-planned'
          ..loanScheduleId = 'planned'
          ..createdAt = DateTime(2026, 7, 5)
          ..status = PaymentStatus.pending,
      };

      await expectLater(
        service.confirm(
          payment: paymentDocs['pay-planned']!,
          confirmedById: 'teller-1',
        ),
        throwsException,
      );
      final row = read('planned');
      expect(row.status, LoanStatus.payment_submitted);
      expect(row.paymentId, isNull, reason: 'not linked to a payment');
      expect(paymentDocs['pay-planned']!.status, PaymentStatus.pending);
      expect(loanStatuses, isEmpty);
    });

    test('reject B: the row is unpaid and overdue again, not settled',
        () async {
      seed(recordTransfer: true);
      await service.reject(
        payment: paymentDocs['pay-B']!,
        confirmedById: 'teller-1',
        reason: 'wrong amount',
      );

      final row = read('B');
      expect(row.status, LoanStatus.not_paid_overdue);
      expect(row.paymentId, isNull);
      expect(row.paidAt, isNull);
      expect(row.collectedAt, isNull);
      expect(paymentDocs['pay-B']!.status, PaymentStatus.rejected);
      expect(loanStatuses, [LoanStatus.not_paid_overdue]);

      // Confirming A afterwards still charges A's own 8 days.
      await service.confirm(
        payment: paymentDocs['pay-A']!,
        confirmedById: 'teller-1',
      );
      expect(read('A').penalty, closeTo(900, 0.01));
    });
  });
}
