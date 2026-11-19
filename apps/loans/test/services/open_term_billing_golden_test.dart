import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenario set G14 — open-term bills keep their cycle dates (owner
// rules R1-R5, 2026-11-14 to 2026-11-19; #144, #120, #117). Every number
// below was derived on paper, and re-derived by a throwaway script that
// does not use the app's code, BEFORE the engine changed.
//
// Conventions: interest = balance x monthly rate x days / 30; days are
// calendar days between local dates; a bill due before today is missed, a
// bill due today or later is the current bill, owed when it falls due.
//
// R1 + R2 — bills keep their dates; every missed bill stays its own row
//   G14a owner's salary-day example: 40,000 at 5%, '15,30', last bill paid
//        Aug 30 2026. Next bills: Sep 15 (Aug 30 -> Sep 15 = 16 days,
//        40,000 x 5% x 16/30 = 1,066.67) and Sep 30 (15 days, 1,000.00).
//        Seen Sep 20: the 15th is missed, the 30th not yet due -> Next
//          payment 1,066.67, Pay in full 2,066.67 (no penalties).
//        Seen Sep 30 with "daily 0.1%" (40 a day on 40,000): both bills
//          are owed, the 15th 15 days late -> 1,066.67 + 1,000 + 15 x 40
//          = 2,666.67 ("missing the 15th means the 30th's payment is both
//          bills plus penalties").
//   G14b the next bill after a late payment is the next SCHEDULED date
//        (10,000 at 5% = 500 per 30 days; loan of Jul 2 2026):
//        '1m', the Aug 1 bill paid late on Aug 5 and stored on its own date,
//          seen Aug 20 -> Aug 31 (Jul 2 + 60), 30 days, 500.00.
//        '1m', a row stored by the old clamp (due_at Aug 5, original_due_at
//          Aug 1, interest charged to Aug 5: 34 days, 566.67, 500 due, 500
//          paid), seen Aug 20 -> Aug 31, interest from Aug 5 = 26 days,
//          433.33; its amount due 433.33 + the 66.67 the clamp row charged
//          but did not bill (R4, review of #146) = 500.00. Before: Aug 5 +
//          30 = Sep 4, 30 days, 500.
//        '15d', clamp row due_at Jul 20 (original Jul 17), seen Aug 3 ->
//          Aug 1 (Jul 2 + 30; Jul 20 -> Aug 1 = 12 days, 200.00), missed,
//          2 days late; then Aug 16 (15 days, 250.00). Before: Jul 20 + 15
//          = Aug 4, 250, 0 days late.
//        #144 reproduction 1, '15,30', clamp row due_at Sep 16 (original
//          Aug 30), seen Oct 20 -> Sep 30 (14 days, 233.33, 20 days late),
//          Oct 15 (15 days, 250.00, 5 days late), Oct 30 (250.00, current).
//          Before: Oct 30 taken from the clock, 44 days, 733.33, 0 days late.
//        #144 reproduction 2, '15,30', loan created Aug 3, nothing stored,
//          seen Sep 20 -> Aug 15 (12 days, 200.00), Aug 30 (15, 250.00),
//          Sep 15 (16, 266.67), Sep 30 (15, 250.00, current). Before: Sep 30
//          from the clock, 58 days, 966.67, 0 days late.
//   G14c three missed bills are owed in full (#120): '1m', paid Aug 1, seen
//        Nov 5 -> Aug 31, Sep 30, Oct 30 (500 each, missed) and Nov 29
//        (current): Next payment 1,500, Pay in full 2,000. Before: one row
//        due Nov 5, 96 days, interest 1,600, amount due capped at 500.
//
// R3 — a balance-based penalty is charged once for the loan per stretch
//   G14d owner's figures: 40,000, '15,30' (installment = 15 days), bills
//        Sep 15 and Sep 30 both paid Oct 2: 17 and 2 days late; the stretch
//        runs Sep 15 -> Oct 2 = 17 days:
//          daily 0.1%      40 x 17               =   680 (per bill: 40 x 19 = 760)
//          monthly 10%     4,000 x ceil(17/30)=1 = 4,000 (per bill: 8,000)
//          per inst. 10%   4,000 x ceil(17/15)=2 = 8,000 (per bill: 4,000 x 3 = 12,000)
//        The penalty is stored on one row (the Sep 15 bill), 0 on the other;
//        both rows are paid_late with their own days late.
//   G14e partial catch-up: only the Sep 15 bill paid Oct 2 -> 680 with that
//        payment; the Sep 30 bill paid Oct 10: the stretch continues from
//        Oct 2, 8 more days -> 320 (680 + 320 = 1,000 = 25 days x 40).
//        "100 once" is charged Oct 2 and not again; monthly
//        ceil(25/30) - ceil(17/30) = 0 more; per installment
//        ceil(25/15) - ceil(17/15) = 0 more.
//        Two stretches: Sep 15 paid Sep 20 (5 days) and Sep 30 paid Oct 5
//        (5 days) -> "100 once" + 5 x 40 = 300 each, 600 in all.
//
// R4 — an interest shortfall carries to the next bill
//   G14f 20,000 at 5%, '1m' (1,000 per 30 days); the Aug 1 bill (1,000)
//        paid 600 on time: the Aug 31 bill owes 1,000 + 400 = 1,400 (its
//        interest charge stays 1,000); the Aug 1 row is paid_on_time with
//        no penalty. Paid 1,000 -> 1,000. A borrower submission records no
//        interest payment (0) and counts as paid in full -> 1,000. The Aug
//        31 bill (1,400) paid 1,000 -> Sep 30 owes 1,400. That bill paid
//        late on Sep 5 with "daily 0.1%": 5 x 0.1% of the 20,000 balance =
//        100 (the carry is part of the bill, not of the penalty base).
//        A bulk payment pays the bills oldest first (1,400 then 1,000):
//        1,800 -> 1,400 + 400; 600 -> 600 + 0 (the second bill stays
//        unpaid); 3,000 -> 1,400 + 1,600 (no credit).
//
// R5 — a top-up mid-cycle splits that cycle on its due row (#117)
//   G14g 10,000 at 5%, paid Aug 1, top-up 2,000 + 100 on Aug 6, seen Aug 15
//        -> the Aug 31 bill = 10,000 x 5% x 5/30 + 12,100 x 5% x 25/30 =
//        83.33 + 504.17 = 587.50 over 30 days; the top-up row shows 83.33
//        and is not a bill (no amount due).
//
// Review of #146 (2026-11-19)
//   G14i only an approved top-up released money (#137): the G14g loan with
//        the top-up pending or declined bills 500.00 on 10,000, and its row
//        shows 10,000 (it does not move the balance); approved -> 587.50.
//   G14j the penalty base is the balance in force each day: Aug 31 and Sep
//        30 missed, a 2,000 top-up on Sep 10 (the Sep 30 bill = 10,000 x 5%
//        x 10/30 + 12,000 x 5% x 20/30 = 166.67 + 400 = 566.67), collected
//        Oct 5 with 0.1% a day: Aug 31..Sep 9 = 10 days x 10 + Sep 10..Oct 4
//        = 25 days x 12 = 400, whichever bill carries it and in preview
//        (was 350 on the Aug 31 bill, 420 when the Sep 30 bill went first).
//   G14k only an active loan bills: an approved loan created May 1 seen Nov
//        19 has 7 bills (May 31 ... Oct 28 missed, Nov 27 current); the same
//        loan declined, completed (settled) or bad debt has none, and a
//        pending application shows only its projected first bill (May 31,
//        500), owed by nobody.
//   G14l a row stored by the old clamp (or an app build not yet updated):
//        due_at Nov 5, interest Aug 1 -> Nov 5 = 96 days = 1,600 charged,
//        500 due, 500 paid -> 1,100 never billed; after the paid Aug 1 row
//        the next bill (Nov 29, 24 days, 400) owes 400 + 1,100 = 1,500,
//        with or without original_due_at, and the same with no earlier
//        stored row: a clamp row (paid on Nov 5) is not within a day of a
//        scheduled date, so it does not move the schedule (third review;
//        the second review's Dec 5, 1,600 is gone).
//   G14m local calendar days in every zone: a loan created at Jul 2 00:30
//        Manila (Jul 1 16:30 UTC) with its first bill stored by a Manila
//        device (Aug 1 00:00 Manila = Jul 31 16:00 UTC): on a UTC device and
//        on a Manila device the next bill is 30 days after that row's local
//        day, 500.00, never a 1-day bill (run this file under TZ=UTC and
//        TZ=Asia/Manila).
//   G14n a salary day missing from a month is the month's last day:
//        '15,30' after Feb 15 2027 -> Feb 28 (13 days, 216.67), Mar 15 (15,
//        250), Mar 30 (15, 250); '15,31' after Apr 15 -> Apr 30 (15, 250),
//        May 15 (15, 250), May 31 (16, 266.67). Before: Mar 2 and May 1.
//   G14o many bills, the current one always last: '15d' from Jan 1 1990 seen
//        Nov 19 2026 (13,471 days) -> 899 bills, the last due Dec 3 2026
//        (current), the one before Nov 18 (was quadratic: 9.4 s, and a
//        1,000-row cap could drop the current bill).
//
// Second review of #146
//   G14p the schedule follows the local creation day; a stored bill within
//        one day of a scheduled date is that bill (third review). Run under
//        TZ=UTC and TZ=Asia/Manila: (1) created Jul 2 00:30 Manila (Jul 1
//        16:30 UTC), first bill stored by the old engine Jul 31 00:00 UTC:
//          UTC: schedule Jul 31, Aug 30; the row is Jul 31 -> Aug 30, 30 d, 500
//          Manila: schedule Aug 1, Aug 31; the row (local Jul 31) is the Aug
//          1 bill -> Aug 31, interest from Jul 31 = 31 d, 516.67
//        (2) created Jul 2 10:00 Manila, a Manila-written Aug 1 row (Jul 31
//        16:00 UTC):
//          UTC: schedule Aug 1, Aug 31; the row (local Jul 31) is the Aug 1
//          bill -> Aug 31, 31 d, 516.67
//          Manila: the row is Aug 1 -> Aug 31, 30 d, 500
//        Never a 1-day bill (was 16.67 due Aug 1). The same loan shows its
//        dates one day apart on a UTC and a Manila device (their calendars
//        differ); the bills are the same ones.
//   G14s an old app build's clamp row as the FIRST stored row does not move
//        the schedule: loan of Jul 2, the Aug 1 bill paid Aug 9 by an old
//        build (due_at Aug 9, no original_due_at, Jul 2 -> Aug 9 = 38 days,
//        633.33 charged, 500 shown and paid -> 133.33 carried), seen Sep 5
//        -> Aug 31 (Aug 9 -> Aug 31 = 22 days, 366.67, due 366.67 + 133.33 =
//        500.00, missed) then Sep 30 (30 days, 500). The second review's
//        anchor gave Sep 8 (30 days, 633.33) then Oct 8. As a second stored
//        row (after a paid Aug 1 row, paid Sep 8 for the Aug 31 bill) it
//        shifts nothing either: next Sep 30, 22 days, 366.67 + 133.33.
//
// Fourth review of #146
//   G14t the principal release approval stores for app-managed companies
//        (balance 0) is not where billing continues: loan of Jul 2, seen Oct
//        5 -> Aug 1, Aug 31, Sep 30 (missed) and Oct 30, 500 each; Pay now
//        1,500, Pay in full 2,000. Whether the row is unconfirmed, was
//        confirmed from a submission before #138 (principal 10,000, interest
//        0) or was paid by a teller (balance -10,000). Before: 0.00 each.
//   G14u the one-day rule also holds for salary days (run under TZ=UTC and
//        TZ=Asia/Manila): '15,30', a Manila-written Aug 15 row (Aug 14 16:00
//        UTC), seen Aug 20 -> next Aug 30 with interest from the row's day:
//        UTC 16 days, 266.67 (was a 1-day 16.67 bill due Aug 15); Manila 15
//        days, 250.
//   G14q a top-up counts from its approval: 2,000 + 100 created Aug 6,
//        approved Sep 5, the Aug 31 bill stored Aug 31 on 10,000 -> Sep 30 =
//        12,100 x 5% + 2,100 x 5% x 25/30 (Aug 6-31, never billed) = 605 +
//        87.50 = 692.50; Oct 30 605; Nov 29 605 (was 500 each). A top-up
//        approved before approval times were recorded keeps the old rule
//        (created before the row -> in it): 500, 500, 500.
//   G14r two bills in ONE submission (Aug 31 and Sep 30, sent Oct 5; 100
//        once + 0.1% a day of 10,000): the stretch Aug 31 -> Oct 5 = 35 days
//        -> 100 + 350 = 450, once, in preview and in either confirmation
//        order (was 0: each unconfirmed bill counted as already charged).

const daily01 = Penalty(
  id: 'daily',
  name: 'Daily',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);
const monthly10 = Penalty(
  id: 'monthly',
  name: 'Monthly',
  amount: 10,
  isPercentage: true,
  frequency: PenaltyFrequency.monthly,
);
const perInstallment10 = Penalty(
  id: 'installment',
  name: 'Per installment',
  amount: 10,
  isPercentage: true,
  frequency: PenaltyFrequency.perInstallment,
);
const once100 = Penalty(id: 'once', name: 'Late fee', amount: 100);

Loan loanOf({
  required String term,
  DateTime? createdAt,
  LoanStatus status = LoanStatus.approved,
  List<Penalty> penalties = const [],
  List<AdditionalLoanAmount> topUps = const [],
}) =>
    Loan()
      ..id = 'loan-1'
      ..createdAt = createdAt ?? DateTime(2026, 7, 2)
      ..status = status
      ..period = 0
      ..term = term
      ..additionalChargeUpfrontCollection = 0
      ..additionalLoanAmounts = List.of(topUps)
      ..penalties = List<Penalty>.of(penalties)
      ..allowLatePayments = false;

/// A stored open-term row. [dueAt] is where its interest ended.
LoanSchedule stored({
  required String id,
  required DateTime dueAt,
  required double balance,
  DateTime? originalDueAt,
  DateTime? createdAt,
  LoanStatus status = LoanStatus.paid_on_time,
  double interestCharge = 0,
  double amortization = 0,
  double interestPayment = 0,
  DateTime? collectedAt,
}) =>
    LoanSchedule()
      ..id = id
      ..loanId = 'loan-1'
      ..companyId = 'co-1'
      ..createdAt = createdAt ?? dueAt
      ..updatedAt = createdAt ?? dueAt
      ..dueAt = dueAt
      ..originalDueAt = originalDueAt
      ..paidAt =
          status == LoanStatus.paid_on_time || status == LoanStatus.paid_late
              ? (collectedAt ?? dueAt)
              : null
      ..collectedAt = collectedAt
      ..status = status
      ..isOpenTerm = true
      ..outstandingBalance = balance
      ..principalPayment = 0
      ..interestPayment = interestPayment
      ..interestCharge = interestCharge
      ..amortization = amortization
      ..extraPayment = 0
      ..advanceInterestPayments = 0
      ..interestDayMultiplier = 1;

List<LoanSchedule> bills({
  required double amount,
  required DateTime start,
  required String term,
  required DateTime now,
  List<LoanSchedule> storedRows = const [],
  List<AdditionalLoanAmount> topUps = const [],
}) =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: amount,
      date: start,
      interestRate: 5,
      term: term,
      companyId: 'co-1',
      paidSchedules: storedRows,
      now: now,
      additionalLoans: topUps,
    ).schedules;

/// What LoansBloc lists for client detail and the borrower.
List<LoanSchedule> clientRows({
  required Loan loan,
  required double amount,
  required DateTime now,
  List<LoanSchedule> storedRows = const [],
}) =>
    LoanCalculationService.calculateOpenTerm(
      amount: amount,
      date: loan.createdAt,
      interestRate: 5,
      term: loan.term,
      companyId: 'co-1',
      paidSchedules: storedRows,
      loan: loan,
      now: now,
    ).schedules;

DateTime dayOf(DateTime d) => DateUtils.dateOnly(d);

void expectBill(
  LoanSchedule s, {
  required DateTime due,
  required int days,
  required double interest,
  double? amountDue,
}) {
  expect(dayOf(s.dueAt), due);
  expect(s.originalDueAt, isNull, reason: 'a bill keeps its own date');
  expect(s.interestDayMultiplier * 30, closeTo(days, 1e-9));
  expect(s.interestCharge, closeTo(interest, 0.01));
  expect(s.amortization, closeTo(amountDue ?? interest, 0.01));
  expect(s.principalPayment, 0);
  expect(s.isOpenTerm, isTrue);
}

void main() {
  group('G14a owner salary-day example (R1, R2)', () {
    final paidAug30 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8, 30), balance: 40000);

    test('seen Sep 20: the missed 15th is owed, the 30th is not yet due', () {
      final now = DateTime(2026, 9, 20, 12);
      final rows = bills(
        amount: 40000,
        start: DateTime(2026, 7, 30),
        term: '15,30',
        now: now,
        storedRows: [paidAug30],
      );

      expect(rows, hasLength(2));
      expectBill(
        rows[0],
        due: DateTime(2026, 9, 15),
        days: 16,
        interest: 1066.67,
      );
      expectBill(rows[1], due: DateTime(2026, 9, 30), days: 15, interest: 1000);

      final loan = loanOf(term: '15,30', createdAt: DateTime(2026, 7, 30));
      final due = borrowerAmountsDue(
        schedules: clientRows(
          loan: loan,
          amount: 40000,
          now: now,
          storedRows: [paidAug30],
        ),
        loan: loan,
        asOf: now,
      );
      expect(due.payNow.map((s) => dayOf(s.dueAt)), [DateTime(2026, 9, 15)]);
      expect(due.nextDueAmount, closeTo(1066.67, 0.01));
      expect(due.remainingTotal, closeTo(2066.67, 0.01));
    });

    test("seen Sep 30: the 30th's payment is both bills plus the penalty", () {
      final now = DateTime(2026, 9, 30, 12);
      final loan = loanOf(
        term: '15,30',
        createdAt: DateTime(2026, 7, 30),
        penalties: const [daily01],
      );
      final due = borrowerAmountsDue(
        schedules: clientRows(
          loan: loan,
          amount: 40000,
          now: now,
          storedRows: [paidAug30],
        ),
        loan: loan,
        asOf: now,
      );

      expect(
        due.payNow.map((s) => dayOf(s.dueAt)),
        [DateTime(2026, 9, 15), DateTime(2026, 9, 30)],
      );
      expect(due.nextDuePenalty, closeTo(600, 0.01));
      expect(due.nextDueAmount, closeTo(2666.67, 0.01));
    });
  });

  group('G14b the next bill is the next scheduled date (R1, #144)', () {
    final start = DateTime(2026, 7, 2);

    test("'1m' after the Aug 1 bill was paid late on Aug 5", () {
      final rows = bills(
        amount: 10000,
        start: start,
        term: '1m',
        now: DateTime(2026, 8, 20, 12),
        storedRows: [
          stored(
            id: 'sched-1',
            dueAt: DateTime(2026, 8),
            balance: 10000,
            status: LoanStatus.paid_late,
            collectedAt: DateTime(2026, 8, 5),
          ),
        ],
      );

      expect(rows, hasLength(1));
      expectBill(
        rows.single,
        due: DateTime(2026, 8, 31),
        days: 30,
        interest: 500,
      );
    });

    test("'1m' after a row stored by the old clamp (due_at Aug 5)", () {
      final rows = bills(
        amount: 10000,
        start: start,
        term: '1m',
        now: DateTime(2026, 8, 20, 12),
        storedRows: [
          stored(
            id: 'sched-1',
            dueAt: DateTime(2026, 8, 5),
            originalDueAt: DateTime(2026, 8),
            balance: 10000,
            status: LoanStatus.paid_late,
            interestCharge: 566.67,
            amortization: 500,
            interestPayment: 500,
          ),
        ],
      );

      expect(rows, hasLength(1));
      expectBill(
        rows.single,
        due: DateTime(2026, 8, 31),
        days: 26,
        interest: 433.33,
        amountDue: 500,
      );
    });

    test("'15d' after a clamp row: Aug 1 missed, Aug 16 current", () {
      final now = DateTime(2026, 8, 3, 12);
      final rows = bills(
        amount: 10000,
        start: start,
        term: '15d',
        now: now,
        storedRows: [
          stored(
            id: 'sched-1',
            dueAt: DateTime(2026, 7, 20),
            originalDueAt: DateTime(2026, 7, 17),
            balance: 10000,
          ),
        ],
      );

      expect(rows, hasLength(2));
      expectBill(rows[0], due: DateTime(2026, 8), days: 12, interest: 200);
      expectBill(rows[1], due: DateTime(2026, 8, 16), days: 15, interest: 250);
      expect(calculateDaysLate(dueAt: rows[0].lateFrom, collectedAt: now), 2);
    });

    test('#144 reproduction 1: salary days after a late payment', () {
      final now = DateTime(2026, 10, 20, 12);
      final rows = bills(
        amount: 10000,
        start: start,
        term: '15,30',
        now: now,
        storedRows: [
          stored(
            id: 'sched-1',
            dueAt: DateTime(2026, 9, 16),
            originalDueAt: DateTime(2026, 8, 30),
            balance: 10000,
            status: LoanStatus.paid_late,
          ),
        ],
      );

      expect(rows, hasLength(3));
      expectBill(
        rows[0],
        due: DateTime(2026, 9, 30),
        days: 14,
        interest: 233.33,
      );
      expectBill(rows[1], due: DateTime(2026, 10, 15), days: 15, interest: 250);
      expectBill(rows[2], due: DateTime(2026, 10, 30), days: 15, interest: 250);
      expect(calculateDaysLate(dueAt: rows[0].lateFrom, collectedAt: now), 20);
      expect(calculateDaysLate(dueAt: rows[1].lateFrom, collectedAt: now), 5);
    });

    test('#144 reproduction 2: salary days on a loan created on an off day',
        () {
      final rows = bills(
        amount: 10000,
        start: DateTime(2026, 8, 3),
        term: '15,30',
        now: DateTime(2026, 9, 20, 12),
      );

      expect(rows, hasLength(4));
      expectBill(rows[0], due: DateTime(2026, 8, 15), days: 12, interest: 200);
      expectBill(rows[1], due: DateTime(2026, 8, 30), days: 15, interest: 250);
      expectBill(
        rows[2],
        due: DateTime(2026, 9, 15),
        days: 16,
        interest: 266.67,
      );
      expectBill(rows[3], due: DateTime(2026, 9, 30), days: 15, interest: 250);
    });
  });

  test('G14c three missed bills are owed in full (R2, #120)', () {
    final now = DateTime(2026, 11, 5, 12);
    final paidAug1 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000);
    final rows = bills(
      amount: 10000,
      start: DateTime(2026, 7, 2),
      term: '1m',
      now: now,
      storedRows: [paidAug1],
    );

    expect(rows, hasLength(4));
    expectBill(rows[0], due: DateTime(2026, 8, 31), days: 30, interest: 500);
    expectBill(rows[1], due: DateTime(2026, 9, 30), days: 30, interest: 500);
    expectBill(rows[2], due: DateTime(2026, 10, 30), days: 30, interest: 500);
    expectBill(rows[3], due: DateTime(2026, 11, 29), days: 30, interest: 500);

    final loan = loanOf(term: '1m');
    final due = borrowerAmountsDue(
      schedules: clientRows(
        loan: loan,
        amount: 10000,
        now: now,
        storedRows: [paidAug1],
      ),
      loan: loan,
      asOf: now,
    );
    expect(due.payNow, hasLength(3));
    expect(due.nextDueAmount, closeTo(1500, 0.01));
    expect(due.remainingTotal, closeTo(2000, 0.01));
  });

  group('G14d-e the penalty is charged once per overdue stretch (R3)', () {
    final paidAug30 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8, 30), balance: 40000);
    final oct2 = DateTime(2026, 10, 2, 12);

    /// The Sep 15 and Sep 30 bills as computed on [now].
    List<LoanSchedule> missed(DateTime now) => bills(
          amount: 40000,
          start: DateTime(2026, 7, 30),
          term: '15,30',
          now: now,
          storedRows: [paidAug30],
        ).sublist(0, 2);

    for (final (penalty, once, perBill) in [
      (daily01, 680.0, 760.0),
      (monthly10, 4000.0, 8000.0),
      (perInstallment10, 8000.0, 12000.0),
    ]) {
      test('G14d ${penalty.name}: both bills paid Oct 2 -> $once', () {
        final loan = loanOf(term: '15,30', penalties: [penalty]);
        final rows = missed(oct2);
        expect(
          rows.map((r) => dayOf(r.dueAt)),
          [DateTime(2026, 9, 15), DateTime(2026, 9, 30)],
        );

        final together = resolveLatenessTogether(
          schedules: rows,
          loan: loan,
          collectedAt: oct2,
          loanRows: [paidAug30, ...rows],
        );
        expect(together.map((r) => r.daysLate), [17, 2]);
        expect(together.map((r) => r.isLate), [true, true]);
        expect(together[0].penalties.total, closeTo(once, 0.01));
        expect(together[1].penalties.total, 0);

        // Per bill, as before R3, it would have been [perBill].
        final perBillTotal = rows.fold<double>(
          0,
          (sum, r) =>
              sum +
              resolveLateness(schedule: r, loan: loan, collectedAt: oct2)
                  .penalties
                  .total,
        );
        expect(perBillTotal, closeTo(perBill, 0.01));

        // The previews on the two unpaid rows add up to the same once.
        final previews = rows
            .map(
              (r) => previewPenalty(
                schedule: r,
                loan: loan,
                asOf: oct2,
                loanRows: [paidAug30, ...rows],
              ).total,
            )
            .toList();
        expect(previews[0], closeTo(once, 0.01));
        expect(previews[1], 0);

        // The bulk confirmation stores it once.
        final context = [paidAug30, ...rows];
        final statuses = [
          for (final r in rows)
            PaymentConfirmationService.applyLateness(
              schedule: r,
              loan: loan,
              collectedAt: oct2,
              actorId: 'teller-1',
              loanRows: context,
            ),
        ];
        expect(statuses, [LoanStatus.paid_late, LoanStatus.paid_late]);
        expect(rows.map((r) => r.daysLate), [17, 2]);
        expect(rows[0].penalty, closeTo(once, 0.01));
        expect(rows[1].penalty, 0);
      });
    }

    test('G14e a partial catch-up continues the stretch: 680 then 320', () {
      final loan = loanOf(term: '15,30', penalties: const [daily01, once100]);
      final rows = missed(oct2);
      final context = [paidAug30, ...rows];

      PaymentConfirmationService.applyLateness(
        schedule: rows[0],
        loan: loan,
        collectedAt: oct2,
        actorId: 'teller-1',
        loanRows: context,
      );
      expect(rows[0].penalty, closeTo(680 + 100, 0.01));

      final oct10 = DateTime(2026, 10, 10, 12);
      expect(
        previewPenalty(
          schedule: rows[1],
          loan: loan,
          asOf: oct10,
          loanRows: context,
        ).total,
        closeTo(320, 0.01),
      );
      PaymentConfirmationService.applyLateness(
        schedule: rows[1],
        loan: loan,
        collectedAt: oct10,
        actorId: 'teller-1',
        loanRows: context,
      );
      expect(rows[1].daysLate, 10);
      expect(rows[1].penalty, closeTo(320, 0.01), reason: 'no second "once"');
    });

    test('G14e monthly and per-installment periods are per stretch', () {
      for (final penalty in [monthly10, perInstallment10]) {
        final loan = loanOf(term: '15,30', penalties: [penalty]);
        final rows = missed(oct2);
        final context = [paidAug30, ...rows];

        PaymentConfirmationService.applyLateness(
          schedule: rows[0],
          loan: loan,
          collectedAt: oct2,
          actorId: 'teller-1',
          loanRows: context,
        );
        PaymentConfirmationService.applyLateness(
          schedule: rows[1],
          loan: loan,
          collectedAt: DateTime(2026, 10, 10, 12),
          actorId: 'teller-1',
          loanRows: context,
        );

        expect(
          rows[0].penalty,
          closeTo(penalty == monthly10 ? 4000 : 8000, 0.01),
        );
        expect(rows[1].penalty, 0, reason: '${penalty.name}: same periods');
      }
    });

    test('G14e two stretches: "once" is charged in each', () {
      final loan = loanOf(term: '15,30', penalties: const [daily01, once100]);
      final rows = missed(DateTime(2026, 9, 20, 12));
      final context = [paidAug30, ...rows];

      PaymentConfirmationService.applyLateness(
        schedule: rows[0],
        loan: loan,
        collectedAt: DateTime(2026, 9, 20, 12),
        actorId: 'teller-1',
        loanRows: context,
      );
      PaymentConfirmationService.applyLateness(
        schedule: rows[1],
        loan: loan,
        collectedAt: DateTime(2026, 10, 5, 12),
        actorId: 'teller-1',
        loanRows: context,
      );

      expect(rows[0].penalty, closeTo(300, 0.01));
      expect(rows[1].penalty, closeTo(300, 0.01));
    });
  });

  group('G14f an interest shortfall carries to the next bill (R4)', () {
    final now = DateTime(2026, 8, 20, 12);

    LoanSchedule aug1({required double paid}) => stored(
          id: 'sched-1',
          dueAt: DateTime(2026, 8),
          balance: 20000,
          interestCharge: 1000,
          amortization: 1000,
          interestPayment: paid,
        );

    List<LoanSchedule> after(LoanSchedule last, {DateTime? seen}) => bills(
          amount: 20000,
          start: DateTime(2026, 7, 2),
          term: '1m',
          now: seen ?? now,
          storedRows: [last],
        );

    test('600 paid against 1,000: the next bill is 1,400', () {
      final loan = loanOf(term: '1m', penalties: const [daily01]);
      final short = aug1(paid: 600);
      final status = PaymentConfirmationService.applyLateness(
        schedule: short,
        loan: loan,
        collectedAt: DateTime(2026, 8, 1, 12),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(short.penalty, 0);

      expectBill(
        after(short).single,
        due: DateTime(2026, 8, 31),
        days: 30,
        interest: 1000,
        amountDue: 1400,
      );
    });

    test('paid in full, or a borrower submission (no amount): 1,000', () {
      expect(after(aug1(paid: 1000)).single.amortization, closeTo(1000, 0.01));
      expect(after(aug1(paid: 0)).single.amortization, closeTo(1000, 0.01));
    });

    test('the carry chains and is not part of the penalty base', () {
      final aug31 = stored(
        id: 'sched-2',
        dueAt: DateTime(2026, 8, 31),
        balance: 20000,
        interestCharge: 1000,
        amortization: 1400,
        interestPayment: 1000,
      );
      final sep30 = after(aug31, seen: DateTime(2026, 9, 10)).single;
      expectBill(
        sep30,
        due: DateTime(2026, 9, 30),
        days: 30,
        interest: 1000,
        amountDue: 1400,
      );

      final late = resolveLateness(
        schedule: after(aug1(paid: 600), seen: DateTime(2026, 9, 5)).first,
        loan: loanOf(term: '1m', penalties: const [daily01]),
        collectedAt: DateTime(2026, 9, 5, 12),
      );
      expect(late.daysLate, 5);
      expect(late.penalties.total, closeTo(100, 0.01));
    });

    test('a bulk payment pays the bills oldest first', () {
      final rows = [
        stored(
          id: NO_ID,
          dueAt: DateTime(2026, 8, 31),
          balance: 20000,
          status: LoanStatus.not_paid,
          amortization: 1400,
        ),
        stored(
          id: NO_ID,
          dueAt: DateTime(2026, 9, 30),
          balance: 20000,
          status: LoanStatus.not_paid,
          amortization: 1000,
        ),
      ];

      List<double> split(double total) =>
          PaymentConfirmationService.splitOpenTermInterest(
            schedules: rows,
            totalInterest: total,
          );

      expect(split(1800), [1400, 400]);
      expect(split(600), [600, 0]);
      expect(split(3000), [1400, 1600]);
    });
  });

  test('G14g a top-up mid-cycle splits that cycle on its due row (R5)', () {
    final topUp = AdditionalLoanAmount()
      ..id = 'al-1'
      ..amount = 2000
      ..additionalCharges = 100
      ..advanceCharges = 0
      ..createdAt = DateTime(2026, 8, 6)
      ..status = LoanStatus.approved;
    final paidAug1 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000);
    final now = DateTime(2026, 8, 15, 12);

    final due = bills(
      amount: 10000,
      start: DateTime(2026, 7, 2),
      term: '1m',
      now: now,
      storedRows: [paidAug1],
      topUps: [topUp],
    ).single;
    expectBill(due, due: DateTime(2026, 8, 31), days: 30, interest: 587.50);
    expect(due.outstandingBalance, closeTo(12100, 0.01));

    final rows = clientRows(
      loan: loanOf(term: '1m', topUps: [topUp]),
      amount: 10000,
      now: now,
      storedRows: [paidAug1],
    );
    expect(rows.map((r) => r.id), [NO_ID, 'sched-1', 'al-1', NO_ID]);
    expect(rows[2].interestCharge, closeTo(83.33, 0.01));
    expect(rows[2].amortization, 0, reason: 'the top-up row is not a bill');
    expect(rows[3].interestCharge, closeTo(587.50, 0.01));
  });

  test('G14h the engine never changes the rows it is given (#145)', () {
    // Review probe of #143, dated from Sep 8 2026: cycle paid 80 days ago
    // (Jun 20), a 5,000 top-up 50 days ago (Jul 20), a submission 45 days
    // ago (Jul 25) that was rejected. The stored rejected row has balance
    // 15,000, interest 500 and penalty 7,600; before the rebuild the top-up
    // loop rewrote it to 20,000 and 125 in the caller's list.
    final paid =
        stored(id: 'sched-1', dueAt: DateTime(2026, 6, 20), balance: 10000);
    final rejected = stored(
      id: 'sched-2',
      dueAt: DateTime(2026, 7, 25),
      originalDueAt: DateTime(2026, 7, 20),
      createdAt: DateTime(2026, 7, 25, 12),
      balance: 15000,
      status: LoanStatus.not_paid_overdue,
      interestCharge: 500,
      amortization: 500,
    )..penalty = 7600;
    final loan = loanOf(
      term: '1m',
      createdAt: DateTime(2026, 5, 21),
      topUps: [
        AdditionalLoanAmount()
          ..id = 'al-1'
          ..amount = 5000
          ..additionalCharges = 0
          ..advanceCharges = 0
          ..createdAt = DateTime(2026, 7, 20)
          ..status = LoanStatus.approved,
      ],
    );
    final storedRows = [rejected, paid];

    final rows = clientRows(
      loan: loan,
      amount: 10000,
      now: DateTime(2026, 9, 8, 12),
      storedRows: storedRows,
    );

    expect(storedRows, [rejected, paid], reason: 'the list is not re-sorted');
    expect(rejected.outstandingBalance, 15000);
    expect(rejected.interestCharge, 500);
    expect(rejected.amortization, 500);
    expect(rejected.penalty, 7600);
    expect(paid.outstandingBalance, 10000);
    expect(
      rows.where((r) => r.id == 'al-1').single.outstandingBalance,
      closeTo(15000, 0.01),
      reason: 'the top-up is already in the stored balance: not added again',
    );
    // The next bills run on 15,000 from where the stored row's interest
    // ended (Jul 25): Aug 19 (May 21 + 90; 25 days, 625.00, missed) and
    // Sep 18 (30 days, 750.00, current).
    final bills = rows.where((r) => r.id == NO_ID && !r.isPlaceholder);
    expect(
      bills.map((r) => dayOf(r.dueAt)),
      [DateTime(2026, 8, 19), DateTime(2026, 9, 18)],
    );
    expect(
      bills.map((r) => r.interestCharge.toStringAsFixed(2)),
      ['625.00', '750.00'],
    );
  });

  group('G14i only an approved top-up moves the balance (#137)', () {
    for (final (status, interest, balance) in [
      (LoanStatus.approved, 587.50, 12100.0),
      (LoanStatus.pending, 500.0, 10000.0),
      (LoanStatus.declined, 500.0, 10000.0),
    ]) {
      test('${status.name}: the Aug 31 bill is $interest', () {
        final topUp = AdditionalLoanAmount()
          ..id = 'al-1'
          ..amount = 2000
          ..additionalCharges = 100
          ..advanceCharges = 0
          ..createdAt = DateTime(2026, 8, 6)
          ..status = status;
        final rows = clientRows(
          loan: loanOf(term: '1m', topUps: [topUp]),
          amount: 10000,
          now: DateTime(2026, 8, 15, 12),
          storedRows: [
            stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000),
          ],
        );

        expect(rows.map((r) => r.id), [NO_ID, 'sched-1', 'al-1', NO_ID]);
        expect(rows[2].outstandingBalance, closeTo(balance, 0.01));
        expect(rows[3].interestCharge, closeTo(interest, 0.01));
        expect(rows[3].outstandingBalance, closeTo(balance, 0.01));
      });
    }
  });

  test('G14j the penalty base is the balance in force each day: 400', () {
    final topUp = AdditionalLoanAmount()
      ..id = 'al-1'
      ..amount = 2000
      ..additionalCharges = 0
      ..advanceCharges = 0
      ..createdAt = DateTime(2026, 9, 10)
      ..status = LoanStatus.approved;
    final loan =
        loanOf(term: '1m', penalties: const [daily01], topUps: [topUp]);
    final paidAug1 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000);
    final oct5 = DateTime(2026, 10, 5, 12);
    List<LoanSchedule> bothBills() => bills(
          amount: 10000,
          start: DateTime(2026, 7, 2),
          term: '1m',
          now: oct5,
          storedRows: [paidAug1],
          topUps: [topUp],
        ).sublist(0, 2);

    final rows = bothBills();
    expect(rows[0].outstandingBalance, closeTo(10000, 0.01));
    expect(rows[1].interestCharge, closeTo(566.67, 0.01));
    expect(rows[1].outstandingBalance, closeTo(12000, 0.01));

    final together = resolveLatenessTogether(
      schedules: rows,
      loan: loan,
      collectedAt: oct5,
      loanRows: [paidAug1, ...rows],
    );
    expect(together.map((r) => r.penalties.total), [closeTo(400, 0.01), 0]);
    expect(
      previewPenalty(
        schedule: rows[0],
        loan: loan,
        asOf: oct5,
        loanRows: [paidAug1, ...rows],
      ).total,
      closeTo(400, 0.01),
    );

    // The Sep 30 bill confirmed first carries the same 400.
    final reversed = bothBills();
    final context = [paidAug1, ...reversed];
    for (final row in reversed.reversed) {
      PaymentConfirmationService.applyLateness(
        schedule: row,
        loan: loan,
        collectedAt: oct5,
        actorId: 'teller-1',
        loanRows: context,
      );
    }
    expect(reversed.map((r) => r.penalty), [0, closeTo(400, 0.01)]);
  });

  group('G14k only an active loan bills', () {
    List<LoanSchedule> billsOf(LoanStatus status) => clientRows(
          loan: loanOf(
            term: '1m',
            createdAt: DateTime(2026, 5),
            status: status,
          ),
          amount: 10000,
          now: DateTime(2026, 11, 19, 12),
        ).where((r) => r.id == NO_ID && !r.isPlaceholder).toList();

    test('approved: 7 bills, May 31 to Nov 27', () {
      final rows = billsOf(LoanStatus.approved);
      expect(rows, hasLength(7));
      expect(dayOf(rows.first.dueAt), DateTime(2026, 5, 31));
      expect(dayOf(rows.last.dueAt), DateTime(2026, 11, 27));
    });

    for (final status in [
      LoanStatus.pending,
      LoanStatus.declined,
      LoanStatus.completed,
      LoanStatus.bad_debt,
    ]) {
      test('${status.name}: nothing owed', () {
        final projected = billsOf(status);
        if (status == LoanStatus.pending) {
          // A pending application shows its projected first bill, read only.
          expect(projected, hasLength(1));
          expect(dayOf(projected.single.dueAt), DateTime(2026, 5, 31));
          expect(projected.single.interestCharge, closeTo(500, 0.01));
        } else {
          expect(projected, isEmpty);
        }
        final loan = loanOf(
          term: '1m',
          createdAt: DateTime(2026, 5),
          status: status,
          penalties: const [daily01],
        );
        final due = borrowerAmountsDue(
          schedules: clientRows(
            loan: loan,
            amount: 10000,
            now: DateTime(2026, 11, 19, 12),
          ),
          loan: loan,
          asOf: DateTime(2026, 11, 19, 12),
        );
        expect(due.unpaid, isEmpty);
        expect(due.remainingTotal, 0);
      });
    }
  });

  group('G14l a clamp row carries what it charged but did not bill', () {
    for (final original in [DateTime(2026, 8, 31), null]) {
      test('original_due_at ${original == null ? 'absent' : 'set'}: 1,500', () {
        final rows = bills(
          amount: 10000,
          start: DateTime(2026, 7, 2),
          term: '1m',
          now: DateTime(2026, 11, 20, 12),
          storedRows: [
            stored(id: 'sched-0', dueAt: DateTime(2026, 8), balance: 10000),
            stored(
              id: 'sched-1',
              dueAt: DateTime(2026, 11, 5),
              originalDueAt: original,
              balance: 10000,
              status: LoanStatus.paid_late,
              interestCharge: 1600,
              amortization: 500,
              interestPayment: 500,
            ),
          ],
        );

        expect(rows, hasLength(1));
        expectBill(
          rows.single,
          due: DateTime(2026, 11, 29),
          days: 24,
          interest: 400,
          amountDue: 1500,
        );
      });
    }

    test(
        'a lone clamp row without original_due_at does not move the '
        'schedule: Nov 29, 400 + 1,100 = 1,500', () {
      final rows = bills(
        amount: 10000,
        start: DateTime(2026, 7, 2),
        term: '1m',
        now: DateTime(2026, 11, 20, 12),
        storedRows: [
          stored(
            id: 'sched-1',
            dueAt: DateTime(2026, 11, 5),
            balance: 10000,
            status: LoanStatus.paid_late,
            interestCharge: 1600,
            amortization: 500,
            interestPayment: 500,
          ),
        ],
      );

      expectBill(
        rows.single,
        due: DateTime(2026, 11, 29),
        days: 24,
        interest: 400,
        amountDue: 1500,
      );
    });
  });

  test('G14m the same bills on a UTC and a Manila device', () {
    // Run under TZ=UTC and TZ=Asia/Manila: the expectations are in the
    // device's own calendar days.
    final created = DateTime.utc(2026, 7, 1, 16, 30);
    final firstBill = bills(
      amount: 10000,
      start: created,
      term: '1m',
      now: created.add(const Duration(days: 1)),
    ).single;
    final createdOn = dayOf(created.toLocal());
    expect(dayOf(firstBill.dueAt), DateUtils.addDaysToDate(createdOn, 30));
    expect(firstBill.interestDayMultiplier * 30, closeTo(30, 1e-9));

    // The first bill as a Manila device stored it, read back in UTC.
    final writtenInManila = stored(
      id: 'sched-1',
      dueAt: DateTime.utc(2026, 7, 31, 16),
      createdAt: DateTime.utc(2026, 7, 31, 16),
      balance: 10000,
    );
    final next = bills(
      amount: 10000,
      start: created,
      term: '1m',
      now: DateTime.utc(2026, 8, 20),
      storedRows: [writtenInManila],
    );
    expect(next, hasLength(1), reason: 'no 1-day bill');
    expect(next.single.interestDayMultiplier * 30, closeTo(30, 1e-9));
    expect(next.single.interestCharge, closeTo(500, 0.01));
    expect(
      dayOf(next.single.dueAt),
      DateUtils.addDaysToDate(dayOf(writtenInManila.dueAt.toLocal()), 30),
    );
  });

  test('G14n a missing salary day is the month end', () {
    final feb = bills(
      amount: 10000,
      start: DateTime(2027),
      term: '15,30',
      now: DateTime(2027, 3, 20, 12),
      storedRows: [
        stored(id: 'sched-1', dueAt: DateTime(2027, 2, 15), balance: 10000),
      ],
    );
    expect(feb, hasLength(3));
    expectBill(feb[0], due: DateTime(2027, 2, 28), days: 13, interest: 216.67);
    expectBill(feb[1], due: DateTime(2027, 3, 15), days: 15, interest: 250);
    expectBill(feb[2], due: DateTime(2027, 3, 30), days: 15, interest: 250);

    final april = bills(
      amount: 10000,
      start: DateTime(2027),
      term: '15,31',
      now: DateTime(2027, 5, 20, 12),
      storedRows: [
        stored(id: 'sched-1', dueAt: DateTime(2027, 4, 15), balance: 10000),
      ],
    );
    expect(april, hasLength(3));
    expectBill(april[0], due: DateTime(2027, 4, 30), days: 15, interest: 250);
    expectBill(april[1], due: DateTime(2027, 5, 15), days: 15, interest: 250);
    expectBill(
      april[2],
      due: DateTime(2027, 5, 31),
      days: 16,
      interest: 266.67,
    );
  });

  test('G14o 899 bills, the current one last', () {
    final watch = Stopwatch()..start();
    final rows = bills(
      amount: 10000,
      start: DateTime(1990),
      term: '15d',
      now: DateTime(2026, 11, 19, 12),
    );
    watch.stop();

    expect(rows, hasLength(899));
    expect(dayOf(rows.last.dueAt), DateTime(2026, 12, 3));
    expect(dayOf(rows[897].dueAt), DateTime(2026, 11, 18));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'bills are generated one after the other (was 9.4 s)',
    );
  });

  group(
      'G14p a stored bill within a day of its date is that bill (UTC and '
      'Manila)', () {
    /// The next bill is the creation day + 60 in the device's calendar, its
    /// interest from the stored row's day (30 or 31 days), never 1 day.
    void expectNextIn30Days(DateTime created, LoanSchedule storedFirst) {
      final next = bills(
        amount: 10000,
        start: created,
        term: '1m',
        now: DateTime.utc(2026, 8, 20),
        storedRows: [storedFirst],
      );
      final due = DateUtils.addDaysToDate(dayOf(created.toLocal()), 60);
      final days = due.difference(dayOf(storedFirst.dueAt.toLocal())).inDays;

      expect(next, hasLength(1), reason: 'no 1-day bill');
      expect(days, inInclusiveRange(29, 31));
      expect(dayOf(next.single.dueAt), due);
      expect(next.single.interestDayMultiplier * 30, closeTo(days, 1e-9));
      expect(
        next.single.interestCharge,
        closeTo(10000 * 0.05 * days / 30, 0.01),
      );
    }

    test('(1) a first bill the old engine stored on Jul 31', () {
      expectNextIn30Days(
        DateTime.utc(2026, 7, 1, 16, 30),
        stored(id: 'sched-1', dueAt: DateTime.utc(2026, 7, 31), balance: 10000),
      );
    });

    test('(2) a Manila-written Aug 1 bill of a loan created 10:00 Manila', () {
      expectNextIn30Days(
        DateTime.utc(2026, 7, 2, 2),
        stored(
          id: 'sched-1',
          dueAt: DateTime.utc(2026, 7, 31, 16),
          balance: 10000,
        ),
      );
    });
  });

  group('G14q a top-up counts from its approval', () {
    List<LoanSchedule> billsWith({DateTime? approvedAt}) => bills(
          amount: 10000,
          start: DateTime(2026, 7, 2),
          term: '1m',
          now: DateTime(2026, 11, 29, 12),
          storedRows: [
            stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000),
            stored(
              id: 'sched-2',
              dueAt: DateTime(2026, 8, 31),
              balance: 10000,
              interestCharge: 500,
              amortization: 500,
            ),
          ],
          topUps: [
            AdditionalLoanAmount()
              ..id = 'al-1'
              ..amount = 2000
              ..additionalCharges = 100
              ..advanceCharges = 0
              ..createdAt = DateTime(2026, 8, 6)
              ..status = LoanStatus.approved
              ..approvedAt = approvedAt,
          ],
        );

    test('approved Sep 5, after the Aug 31 bill was stored: 692.50, 605, 605',
        () {
      final rows = billsWith(approvedAt: DateTime(2026, 9, 5));
      expect(rows, hasLength(3));
      expectBill(
        rows[0],
        due: DateTime(2026, 9, 30),
        days: 30,
        interest: 692.50,
      );
      expectBill(rows[1], due: DateTime(2026, 10, 30), days: 30, interest: 605);
      expectBill(rows[2], due: DateTime(2026, 11, 29), days: 30, interest: 605);
    });

    test('approved before approval times were recorded: the old rule, 500', () {
      final rows = billsWith();
      expect(rows.map((r) => r.interestCharge), [500, 500, 500]);
    });
  });

  group('G14r two bills in one submission owe the stretch once (450)', () {
    final oct5 = DateTime(2026, 10, 5, 12);
    final paidAug1 =
        stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000);
    final loan = loanOf(term: '1m', penalties: const [daily01, once100]);

    /// The Aug 31 and Sep 30 bills, both submitted on Oct 5.
    List<LoanSchedule> submittedTogether() => [
          for (final (i, bill) in bills(
            amount: 10000,
            start: DateTime(2026, 7, 2),
            term: '1m',
            now: oct5,
            storedRows: [paidAug1],
          ).sublist(0, 2).indexed)
            bill
              ..id = 'bill-$i'
              ..status = LoanStatus.payment_submitted
              ..collectedAt = oct5,
        ];

    test('preview: 450 on the Aug 31 bill, 0 on the Sep 30 bill', () {
      final rows = submittedTogether();
      final context = [paidAug1, ...rows];

      expect(
        rows.map(
          (r) =>
              previewPenalty(schedule: r, loan: loan, loanRows: context).total,
        ),
        [closeTo(450, 0.01), 0],
      );
      expect(
        resolveLatenessTogether(
          schedules: rows,
          loan: loan,
          collectedAt: oct5,
          loanRows: context,
        ).map((r) => r.penalties.total),
        [closeTo(450, 0.01), 0],
      );
    });

    for (final reverse in [false, true]) {
      test('confirmed ${reverse ? 'Sep 30 first' : 'Aug 31 first'}: 450 once',
          () {
        final rows = submittedTogether();
        final context = [paidAug1, ...rows];
        for (final row in reverse ? rows.reversed : rows) {
          row.status = PaymentConfirmationService.applyLateness(
            schedule: row,
            loan: loan,
            collectedAt: oct5,
            actorId: 'teller-1',
            loanRows: context,
          );
        }

        expect(
          rows.fold<double>(0, (sum, r) => sum + r.penalty),
          closeTo(450, 0.01),
        );
        expect(rows.map((r) => r.daysLate), [35, 5]);
      });
    }
  });

  group("G14s an old build's clamp row does not move the schedule", () {
    LoanSchedule clampRow(DateTime dueAt) => stored(
          id: 'clamp',
          dueAt: dueAt,
          balance: 10000,
          status: LoanStatus.paid_late,
          interestCharge: 633.33,
          amortization: 500,
          interestPayment: 500,
        );

    test('as the first stored row: Aug 31 (22 days, 500 due), then Sep 30', () {
      final rows = bills(
        amount: 10000,
        start: DateTime(2026, 7, 2),
        term: '1m',
        now: DateTime(2026, 9, 5, 12),
        storedRows: [clampRow(DateTime(2026, 8, 9))],
      );

      expect(rows, hasLength(2));
      expectBill(
        rows[0],
        due: DateTime(2026, 8, 31),
        days: 22,
        interest: 366.67,
        amountDue: 500,
      );
      expectBill(rows[1], due: DateTime(2026, 9, 30), days: 30, interest: 500);
    });

    test('as the second stored row: Sep 30, 22 days', () {
      final rows = bills(
        amount: 10000,
        start: DateTime(2026, 7, 2),
        term: '1m',
        now: DateTime(2026, 9, 10, 12),
        storedRows: [
          stored(id: 'sched-1', dueAt: DateTime(2026, 8), balance: 10000),
          clampRow(DateTime(2026, 9, 8)),
        ],
      );

      expect(rows, hasLength(1));
      expectBill(
        rows.single,
        due: DateTime(2026, 9, 30),
        days: 22,
        interest: 366.67,
        amountDue: 500,
      );
    });
  });

  group('G14t billing never continues from the principal release (#138)', () {
    LoanSchedule release({
      LoanStatus status = LoanStatus.approved,
      double balance = 0,
      double interestPaid = 0,
    }) =>
        stored(
          id: 'planned',
          dueAt: DateTime(2026, 7, 2, 9, 30),
          balance: balance,
          status: status,
          interestPayment: interestPaid,
        )..principalPayment = 10000;

    for (final (name, row) in [
      ('unconfirmed', release()),
      ('confirmed before #138', release(status: LoanStatus.paid_on_time)),
      (
        'paid by a teller',
        release(
          status: LoanStatus.paid_on_time,
          balance: -10000,
          interestPaid: 1,
        ),
      ),
    ]) {
      test('$name: 500 per cycle', () {
        expect(row.isPrincipalRelease, isTrue);
        final now = DateTime(2026, 10, 5, 12);
        final rows = bills(
          amount: 10000,
          start: DateTime(2026, 7, 2, 9, 30),
          term: '1m',
          now: now,
          storedRows: [row],
        );
        expect(rows, hasLength(4));
        expect(rows.map((r) => dayOf(r.dueAt)), [
          DateTime(2026, 8),
          DateTime(2026, 8, 31),
          DateTime(2026, 9, 30),
          DateTime(2026, 10, 30),
        ]);
        expect(
          rows.map((r) => r.interestCharge),
          everyElement(closeTo(500, 0.01)),
        );

        final loan = loanOf(term: '1m', createdAt: DateTime(2026, 7, 2, 9, 30));
        final due = borrowerAmountsDue(
          schedules: clientRows(
            loan: loan,
            amount: 10000,
            now: now,
            storedRows: [row],
          ),
          loan: loan,
          asOf: now,
        );
        expect(due.nextDueAmount, closeTo(1500, 0.01));
        expect(due.remainingTotal, closeTo(2000, 0.01));
      });
    }
  });

  test('G14u a Manila-written salary-day row: no 1-day bill (UTC and Manila)',
      () {
    final row = stored(
      id: 'sched-1',
      dueAt: DateTime.utc(2026, 8, 14, 16),
      balance: 10000,
    );
    final next = bills(
      amount: 10000,
      start: DateTime.utc(2026, 7, 29, 16),
      term: '15,30',
      now: DateTime.utc(2026, 8, 20),
      storedRows: [row],
    );
    final days =
        DateTime(2026, 8, 30).difference(dayOf(row.dueAt.toLocal())).inDays;

    expect(next, hasLength(1), reason: 'no 1-day bill due Aug 15');
    expect(days, inInclusiveRange(15, 16));
    expectBill(
      next.single,
      due: DateTime(2026, 8, 30),
      days: days,
      interest: 10000 * 0.05 * days / 30,
    );
  });
}
