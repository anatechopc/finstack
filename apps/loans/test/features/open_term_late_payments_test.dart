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

// finstack#114 at widget and bloc level: the screens fed by the real
// open-term engine. Numbers are G13a's (see
// test/services/penalty_open_term_golden_test.dart): balance 10,000 at 5%,
// the paid cycle due 38 days ago, so the next cycle was due 8 days ago and
// is billed as due today with 38 days of interest (633.33); penalties
// "Late fee" 100 once + "Daily surcharge" 1% of the balance per day:
// 100 + 100 x 8 = 900.
//
// The client-detail row, the borrower table and the Payment Center read the
// wall clock, so those scenarios are dated relative to today; the payment
// dialog and the borrower totals take a date and use G13a's fixed dates.
// Like the golden suite this assumes a zone without daylight saving (CI pins
// TZ=UTC): when the 38 days before today cross a clock change, the engine's
// 30-day step lands an hour off and the cycle falls on the previous calendar
// day (campaign D11), so these relative scenarios count 9 days, not 8.
//
// Rejected submission (reviews of #143): the borrower submitted on an
// overdue cycle and the lender rejected it; the row computed that day is
// stored with its id. Like LoansBloc, the Payment Center now hands every
// stored row to the engine as a past cycle, so all screens show the same
// rows and the stored row is never duplicated.
//   Submitted 2 days ago (paid cycle 38 days ago): stored row billed as due
//   that day, 36 days of interest = 600, original due date 8 days ago ->
//   overdue, 100 + 100 x 8 = 900; the next cycle (2 days ago + 30) is
//   upcoming, 0. (First fix: one row, 900; before it 900 + 900 = 1,800 and
//   600 + 633.33 interest; develop 300.) A row stored before #114 has no
//   original due date: 100 + 100 x 2 = 300.
//   Submitted 45 days ago (paid cycle 80 days ago): stored row billed as due
//   45 days ago, 35 days of interest = 583.33, original due 50 days ago ->
//   100 + 100 x 50 = 5,100; next cycle due 45 - 30 = 15 days ago, billed
//   today, 45 days of interest = 750 -> 100 + 100 x 15 = 1,600; together
//   6,700, and Pay in full 500 + 500 + 6,700 = 7,700 on every screen. (The
//   first fix's "after the last paid row" merge showed the Payment Center 1
//   row, 5,100.)

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
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

/// The cycle that fell due 8 days ago, as the app computes it now.
LoanSchedule overdueRowNow() =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: 10000,
      date: daysFromToday(-68),
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: [paidCycle(daysFromToday(-38))],
      now: DateTime.now(),
    ).schedules.single;

/// A submission on [submittedAt] that the lender rejected: the row computed
/// that day, stored with an id, read back from Firestore as overdue.
LoanSchedule rejectedSubmission({
  required DateTime paidDue,
  required DateTime submittedAt,
  bool storedBefore114 = false,
}) {
  final json = (LoanCalculationService.calculateOpenTermSchedules(
    amount: 10000,
    date: paidDue,
    interestRate: 5,
    term: '1m',
    companyId: 'co-1',
    paidSchedules: [paidCycle(paidDue)],
    now: submittedAt,
  ).schedules.single
        ..id = 'sched-2'
        ..loanId = 'loan-1'
        ..status = LoanStatus.not_paid_overdue)
      .toJson();
  if (storedBefore114) {
    json.remove('original_due_at');
  }

  return LoanScheduleEntity.fromJson(json).toLoanSchedule();
}

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

    Future<void> pumpRow(
      WidgetTester tester,
      Loan loan, {
      LoanSchedule? schedule,
    }) async {
      tester.view
        ..physicalSize = const Size(2400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        Scaffold(
          body: ClientDetailScheduleItem(
            index: 2,
            schedule: schedule ?? overdueRowNow(),
            onMakePayment: (_) {},
            loan: loan,
          ),
        ),
      );
    }

    testWidgets('an overdue open-term row shows Overdue and 900 for 8 days',
        (tester) async {
      await pumpRow(tester, openTermLoan(createdAt: daysFromToday(-68)));

      expect(find.text('Make payment'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.textContaining('900.00 penalty · 8 days late'),
        findsOneWidget,
      );
      expect(
        find.textContaining('633.33'),
        findsOneWidget,
        reason: 'interest still accrues to today (G4c)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a loan that allows late payments: Overdue, no penalty',
        (tester) async {
      await pumpRow(
        tester,
        openTermLoan(createdAt: daysFromToday(-68), allowLate: true),
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('penalty'), findsNothing);
    });

    testWidgets('the principal-release row has no Make payment and no penalty',
        (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68));
      final principalRelease = LoanCalculationService.calculateOpenTerm(
        amount: 10000,
        date: loan.createdAt,
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [paidCycle(daysFromToday(-38))],
        loan: loan,
        now: DateTime.now(),
      ).schedules.first;
      expect(principalRelease.isPlaceholder, isTrue);
      expect(principalRelease.status, LoanStatus.not_paid);

      await pumpRow(tester, loan, schedule: principalRelease);

      expect(find.text('Make payment'), findsNothing);
      expect(find.textContaining('penalty'), findsNothing);
    });
  });

  testWidgets('borrower schedule table: overdue label and the penalty',
      (tester) async {
    await tester.pumpApp(
      LoanScheduleWidget(
        amortization: 500,
        schedules: [overdueRowNow()],
        completeTerm: 'Open term',
        buildTable: true,
        tableHeight: 2 * LoanScheduleWidget.rowHeight,
        loan: openTermLoan(createdAt: daysFromToday(-68)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(LoanStatus.not_paid_overdue.label), findsOneWidget);
    expect(find.textContaining('900.00 penalty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('payment dialog breakdown (PaymentPenaltySection)', () {
    final sep8 = DateTime(2026, 9, 8, 12);
    LoanSchedule g13aRow() => LoanCalculationService.calculateOpenTermSchedules(
          amount: 10000,
          date: DateTime(2026, 7, 2),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(DateTime(2026, 8))],
          now: sep8,
        ).schedules.single;

    Future<void> pumpSection(WidgetTester tester, Loan loan) {
      return tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: FormBuilder(
              child: PaymentPenaltySection(
                schedules: [g13aRow()],
                loan: loan,
                initialCollectedAt: DateTime(2026, 9, 8),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('collected on the billing date: 100 once + 8 days x 100',
        (tester) async {
      await pumpSection(tester, openTermLoan(createdAt: DateTime(2026, 7, 2)));

      expect(find.textContaining('Late fee'), findsOneWidget);
      expect(find.textContaining('Daily surcharge'), findsOneWidget);
      expect(find.textContaining('× 8'), findsOneWidget);
      expect(find.textContaining('800.00'), findsOneWidget);
      expect(find.text('Waive penalties'), findsOneWidget);
    });

    testWidgets('allowed late: 8 days shown, nothing to charge or waive',
        (tester) async {
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2), allowLate: true),
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

    List<LoanSchedule> clientSchedules(Loan loan) =>
        LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: loan.createdAt,
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(DateTime(2026, 8))],
          loan: loan,
          now: sep8,
        ).schedules;

    test('the penalty is counted once, on the overdue cycle', () {
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan),
        loan: loan,
        asOf: sep8,
      );

      expect(due.unpaid, hasLength(1), reason: 'placeholders are not due');
      expect(due.nextDue!.isPlaceholder, isFalse);
      expect(DateUtils.dateOnly(due.nextDue!.dueAt), DateTime(2026, 9, 8));
      expect(due.nextDuePenalty, closeTo(900, 0.01));
      expect(due.nextDueAmount, closeTo(1400, 0.01));
      expect(due.remainingPenalty, closeTo(900, 0.01));
      expect(due.remainingTotal, closeTo(1400, 0.01));
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
      expect(due.remainingTotal, closeTo(500, 0.01));
      expect(due.remainingPenalty, 0);
    });

    test('a top-up row is not an installment: only the cycle is due', () {
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

      expect(due.unpaid, hasLength(1));
      expect(due.unpaid.single.isPlaceholder, isFalse);
      expect(
        due.remainingTotal,
        closeTo(due.nextDueAmount, 0.01),
        reason: "the top-up row's copied amortization is not added",
      );
    });

    test('a rejected submission: client detail and borrower count 900 once',
        () {
      // Submitted Sep 6 on the cycle due Aug 31, rejected. LoansBloc hands
      // every stored row to the engine, so the stored row is shown as is and
      // the next cycle (Sep 6 + 30 = Oct 6) is not yet due.
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final rejected = rejectedSubmission(
        paidDue: DateTime(2026, 8),
        submittedAt: DateTime(2026, 9, 6, 12),
      );
      expect(rejected.interestCharge, closeTo(600, 0.01));

      final schedules = LoanCalculationService.calculateOpenTerm(
        amount: 10000,
        date: loan.createdAt,
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [paidCycle(DateTime(2026, 8)), rejected],
        loan: loan,
        now: sep8,
      ).schedules;

      final clientDetailPenalties = schedules.fold<double>(
        0,
        (sum, s) =>
            sum + previewPenalty(schedule: s, loan: loan, asOf: sep8).total,
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

  group('Payment Center (bloc): overdue open-term row', () {
    late _Loans loans;
    late _Schedules schedules;
    var loanCreatedDaysAgo = 68;

    setUpAll(() {
      registerFallbackValue(Loan());
    });

    setUp(() {
      loans = _Loans();
      schedules = _Schedules();
      loanCreatedDaysAgo = 68;
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer((invocation) async {
        final statements =
            invocation.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [openTermLoan(createdAt: daysFromToday(-loanCreatedDaysAgo))]
            : <Loan>[];
      });
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => [paidCycle(daysFromToday(-38))]);
    });

    Future<List<LoanSchedule>> actionable() async {
      final auth = _Auth();
      when(() => auth.company).thenReturn(Company()..id = 'co-1');
      final bloc = PaymentCenterBloc.withDependencies(
        userRepository: _Users(),
        loanRepository: loans,
        loanScheduleRepository: schedules,
        paymentRepository: _Payments(),
        storageRepository: _Storage(),
        authService: auth,
      );
      addTearDown(bloc.close);

      bloc.add(SelectBorrowerEvent(borrower: User()..id = 'u1'));
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == PaymentCenterStatus.borrowerSelected ||
            s.status == PaymentCenterStatus.error,
      );
      expect(state.status, PaymentCenterStatus.borrowerSelected);

      return state.borrowerLoans.single.actionableSchedules;
    }

    test('listed as overdue from its original due date', () async {
      final rows = await actionable();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.isOpenTerm, isTrue);
      expect(row.status, LoanStatus.not_paid_overdue);
      expect(DateUtils.dateOnly(row.dueAt), today, reason: 'billed today');
      expect(row.originalDueAt, daysFromToday(-8));
      expect(row.interestCharge, closeTo(633.33, 0.01));
    });

    test('bulk overdue applies 8 days and 900 to the row', () async {
      final row = (await actionable()).single;

      // What _handleMakeOverduePaymentEvent runs per row before writing it.
      final status = PaymentConfirmationService.applyLateness(
        schedule: row,
        loan: openTermLoan(createdAt: daysFromToday(-68)),
        collectedAt: DateTime.now(),
        actorId: 'teller-1',
      );

      expect(status, LoanStatus.paid_late);
      expect(row.daysLate, 8);
      expect(row.penalty, closeTo(900, 0.01));
      expect(row.toJson()['original_due_at'], isNotNull);
    });

    testWidgets('the overdue tile dates the row by its original due date',
        (tester) async {
      final rows = await tester.runAsync(actionable);

      await tester.pumpApp(
        Scaffold(
          body: OverdueSummaryTile(
            overdueSchedules: rows!,
            onPay: () {},
            readOnly: true,
          ),
        ),
      );

      expect(find.text(daysFromToday(-8).toDefaultDateFormat()), findsOneWidget);
      expect(find.text(today.toDefaultDateFormat()), findsNothing);
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

      void stubStored(List<LoanSchedule> Function() rows) {
        when(
          () => schedules.allByLoanId(
            loanId: any(named: 'loanId'),
            onlyPaid: any(named: 'onlyPaid'),
          ),
        ).thenAnswer((_) async => rows());
      }

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

      Iterable<LoanSchedule> overdueOf(List<LoanSchedule> rows) =>
          rows.where((r) => r.status == LoanStatus.not_paid_overdue);

      test('the stored row is the overdue cycle: 900, interest once',
          () async {
        stubStored(() => storedRows(paidDaysAgo: 38, submittedDaysAgo: 2));
        final rows = await actionable();

        expect(overdueOf(rows).map((r) => r.id), ['sched-2']);
        expect(rows.first.interestCharge, closeTo(600, 0.01));
        expect(penaltyOf(rows), closeTo(900, 0.01));
        // The next cycle (2 days ago + 30) is upcoming, as on client detail.
        expect(rows, hasLength(2));
        expect(rows.last.status, LoanStatus.not_paid);
        expect(rows.last.lateFrom, daysFromToday(28));
      });

      test('a row stored before #114 counts from its own date (300)',
          () async {
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

      test('a rejection more than a term old: the Payment Center, client '
          'detail and the borrower show the same 2 rows, 6,700', () async {
        stubStored(() => storedRows(paidDaysAgo: 80, submittedDaysAgo: 45));
        loanCreatedDaysAgo = 110;

        final paymentCenter = await actionable();
        expect(overdueOf(paymentCenter), hasLength(2));
        expect(paymentCenter.first.id, 'sched-2');
        expect(paymentCenter.first.interestCharge, closeTo(583.33, 0.01));
        expect(paymentCenter.last.lateFrom, daysFromToday(-15));
        expect(paymentCenter.last.interestCharge, closeTo(750, 0.01));
        expect(penaltyOf(paymentCenter), closeTo(6700, 0.01));

        // What LoansBloc computes for client detail and the borrower: every
        // stored row goes to the engine (loans_bloc.dart, _calculateLoanOpen).
        final loan = openTermLoan(createdAt: daysFromToday(-110));
        final clientSchedules = LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: loan.createdAt,
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: storedRows(paidDaysAgo: 80, submittedDaysAgo: 45),
          loan: loan,
          now: DateTime.now(),
        ).schedules;
        final due = borrowerAmountsDue(schedules: clientSchedules, loan: loan);

        expect(
          due.unpaid.map((r) => r.lateFrom),
          paymentCenter.map((r) => r.lateFrom),
        );
        expect(due.remainingPenalty, closeTo(6700, 0.01));
        expect(due.remainingTotal, closeTo(7700, 0.01));
        expect(
          clientSchedules.fold<double>(
            0,
            (sum, s) => sum + previewPenalty(schedule: s, loan: loan).total,
          ),
          closeTo(6700, 0.01),
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
}
