import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenario set G15 — the penalty "Based on" option (owner rules,
// 2026-11-14 to 2026-11-19). Every number below was derived on paper BEFORE
// the code changed.
//
// The rules:
//   - A percentage penalty is a percent of "the missed bill" (the bill's
//     amount due, `amortization`) or of "the outstanding balance".
//   - Based on the missed bill: charged per missed bill, each bill counting
//     its own days late, on fixed-term and open-term loans alike.
//   - Based on the outstanding balance: charged once for the loan per
//     overdue stretch (#146's R3 counting): "once" once per stretch, daily
//     per day of the stretch, monthly and per installment per started period
//     of the stretch; a partial catch-up charges up to its collection date
//     and the stretch continues without charging those days again.
//   - A flat amount is charged as entered and has no base. It is charged
//     per missed bill, each bill counting its own days late, on both loan
//     types and whatever `based_on` holds (owner, 2026-11-19; before that
//     decision open-term flat amounts were charged once per stretch).
//   - A penalty saved without `based_on` (null) keeps today's behaviour:
//     the missed installment on fixed-term, the outstanding balance on
//     open-term.
//   - Fixed-term balance base (review of #148, flagged for the owner): the
//     balance in force each day of the stretch, as on open-term loans = the
//     principal still owed that day = the balance before the earliest bill
//     of the stretch not yet paid by then (its balance after its principal
//     + its principal). A bill paid inside the stretch lowers it from its
//     payment day; the bills computed after it start from its stored
//     balance, so the result depends on what the teller payment stores
//     (#140, F7/F8).
//
// Open-term loan (owner's): 40,000 at 5% a month, salary days 15 and 30
// (installment = 15 days), last bill paid Aug 30. "Take each bill as
// 1,000": the Sep 15 and Sep 30 bills are built with an amount due of 1,000
// each (the engine bills the Sep 15 one 1,066.67, see O8).
//   Both paid Oct 2: Sep 15 -> Oct 2 = 17 days late, Sep 30 -> Oct 2 = 2.
//   O1 based on the balance (stretch Sep 15 -> Oct 2 = 17 days):
//        daily 0.1%      40 x 17                    =   680 (Sep 15 row; Sep 30 row 0)
//        monthly 10%     4,000 x ceil(17/30) = 1    = 4,000
//        per inst. 10%   4,000 x ceil(17/15) = 2    = 8,000
//   O2 based on the missed bill (per bill):
//        daily 1%        10 x 17 = 170, 10 x 2 = 20                       -> 190
//        monthly 10%     100 x ceil(17/30) = 100, 100 x ceil(2/30) = 100  -> 200
//        per inst. 10%   100 x ceil(17/15) = 200, 100 x ceil(2/15) = 100  -> 300
//      Previews on Oct 2 show each bill's own amount (170 and 20), and the
//      borrower's Pay now on Oct 2 is 1,000 + 1,000 + 190 = 2,190.
//   O3 the Sep 15 bill missed, paid Sep 30 together with the Sep 30 bill
//      (on time), "10% once based on the missed bill": 100 x 1 on the Sep 15
//      bill (15 days late), 0 on the Sep 30 bill (0 days late)
//      -> 1,000 + 100 + 1,000 = 2,100 (not 2,200).
//   O4 partial catch-up, "1% daily of the missed bill": the Sep 15 bill paid
//      Oct 2 -> 170; the Sep 30 bill paid Oct 10, 10 days late -> 100
//      (each bill its own days; the balance-based G14e gives 680 then 320).
//   O5 mixed, "1% daily of the missed bill" + "0.1% daily of the balance":
//      both paid Oct 2 -> Sep 15 row 170 + 680 = 850, Sep 30 row 20 -> 870;
//      previews 850 and 20. Partial: Sep 15 paid Oct 2 -> 850; Sep 30 paid
//      Oct 10 -> 100 + 8 more stretch days x 40 = 320 -> 420.
//   O6 flat amounts, per missed bill: 100 once -> 100 + 100 = 200; 50 a day
//      -> 50 x 17 = 850 + 50 x 2 = 100 -> 950. A flat 100 once that holds
//      `based_on: outstanding_balance` is still per bill, 200. (Before the
//      owner's decision: 100 and 850 once for the stretch.)
//   O6b partial catch-up, 50 a day flat: the Sep 15 bill paid Oct 2 -> 850;
//      the Sep 30 bill paid Oct 10 counts its own 10 days -> 500 (the
//      stretch would add 8 x 50 = 400; nothing of Sep 15's days again).
//   O7 saved without `based_on`: 0.1% daily -> 680, the same as O1 and as
//      G14d; G12's open-term row (balance 10,000, 5 days late, 100 once +
//      1% daily) -> 100 + 500 = 600.
//   O8 the engine's own bills (Sep 15 = 40,000 x 5% x 16/30 = 1,066.67, Sep
//      30 = 1,000): "1% daily of the missed bill" -> 10.6667 x 17 = 181.33
//      + 10 x 2 = 20 -> 201.33.
//   O9 principal paid inside the stretch (engine bills, 0.1% daily of the
//      balance): the Sep 15 bill paid Oct 2 with 10,000 principal -> 680
//      (17 days on 40,000); stored balance 30,000, so the engine's Sep 30
//      bill is 30,000 x 5% x 15/30 = 750; paid Oct 10 -> 8 more stretch
//      days (Oct 2 to Oct 9) x 30 = 240 (320 had the balance stayed 40,000).
//
// Fixed-term loan: 10,000 at 5% a month, '1m', amortization 2,500; rows as
// the fixed-term engine lays them out (balance after the row's principal):
//   R1 Aug 1   interest 500, principal 2,000, balance 8,000 (paid on time)
//   R2 Aug 31  interest 400, principal 2,100, balance 5,900
//   R3 Sep 30  interest 295, principal 2,205, balance 3,695
//   R2 and R3 paid Oct 5: R2 Aug 31 -> Oct 5 = 35 days late, R3 5 days.
//   F1 based on the missed bill, daily 1% (25 a day): 875 + 125 = 1,000;
//      10% once: 250 + 250 = 500.
//   F2 based on the balance, both unpaid until Oct 5: every day of the
//      stretch Aug 31 -> Oct 5 (35 days) R2 is the earliest unpaid bill, so
//      the balance is R2's 5,900 + 2,100 = 8,000:
//        daily 0.1%      8 x 35                    =   280 (R2; R3 0)
//        10% once        800                       =   800
//        monthly 10%     800 x ceil(35/30) = 2     = 1,600
//      Previews on Oct 5: R2 280, R3 0.
//   F3 partial catch-up, 0.1% daily of the balance: R2 paid Oct 5 alone
//      with its scheduled principal -> 280 (R3 unpaid and late, same
//      stretch); R3 (beginning balance 3,695 + 2,205 = 5,900) paid Oct 10 ->
//      the stretch Aug 31 -> Oct 10 = 40 days, 35 charged; Oct 5 to Oct 9
//      R2 is paid, so 5 x 5.90 = 29.50 (the first version kept 8,000: 40).
//   F7 the review's probe, R2 paid Oct 5 with 5,000 principal (a teller
//      paying 2,900 extra), the Sep 30 bill recomputed by the fixed-term
//      engine from R2 as stored (amortization 2,500, 5% a month):
//        the teller handlers (`recordTellerPayment`) store 5,900 - 2,900
//          extra = 3,000 = 8,000 - 5,000 -> R3 interest 150, principal
//          2,350, beginning 3,000 -> 5 x 3 = 15.
//        (Before #140's fix they stored 5,900 - 2,900 - 2,100 again = 900
//          -> R3 interest 45, amortization 945, beginning 900 -> 4.50.)
//   F8 R2 paid Oct 5 with its scheduled 2,100 (any teller or bulk payment):
//        stored 5,900 - 0 extra = 5,900 -> R3 beginning 5,900 -> 29.50
//          (= F3).
//        (Before #140's fix: 5,900 - 2,100 = 3,800 -> R3 interest 190,
//          principal 2,310, beginning 3,800 -> 19.)
//      R2's own charge is 280 in F7 and F8 (R2 unpaid until Oct 5).
//   F4 mixed, 1% daily of the bill + 0.1% daily of the balance, both paid
//      Oct 5: R2 875 + 280 = 1,155, R3 125 -> 1,280.
//   F5 flat amounts: 100 once -> 100 + 100 = 200; 50 a day -> 50 x 35 +
//      50 x 5 = 2,000.
//   F6 saved without `based_on`: 1% daily -> 875 + 125 = 1,000 (= F1);
//      G12 P1 (amortization 2,500, 5 days late, 100 once + 1% daily) -> 225.
//
// Mutation checks: count a penalty based on the missed bill (and so a flat
// amount) once for the loan (the stretch, still on the bill's amount)
// instead of per bill -> O2, O4, O5, O6, O6b, O8, F1, F4, F5, F6 fail. O3
// does not: its second bill is not late, so once per stretch and per bill
// agree. Keep the fixed-term base at
// the stretch's first bill for the whole stretch -> F3, F7, F8 fail.

const bill = PenaltyBase.missedBill;
const balance = PenaltyBase.outstandingBalance;

const daily = PenaltyFrequency.daily;
const monthly = PenaltyFrequency.monthly;
const perInstallment = PenaltyFrequency.perInstallment;
const once = PenaltyFrequency.once;

Penalty percent(
  double amount,
  PenaltyFrequency frequency, {
  PenaltyBase? basedOn,
  String name = 'Surcharge',
}) =>
    Penalty(
      id: '$name-$amount-${frequency.name}-${basedOn?.name}',
      name: name,
      amount: amount,
      isPercentage: true,
      frequency: frequency,
      basedOn: basedOn,
    );

Penalty flat(
  double amount,
  PenaltyFrequency frequency, {
  PenaltyBase? basedOn,
}) =>
    Penalty(
      id: 'flat-$amount-${frequency.name}',
      name: 'Late fee',
      amount: amount,
      frequency: frequency,
      basedOn: basedOn,
    );

Loan loanOf({required bool openTerm, required List<Penalty> penalties}) =>
    Loan()
      ..id = 'loan-1'
      ..createdAt = DateTime(2026, 7, 30)
      ..status = LoanStatus.approved
      ..period = openTerm ? 0 : 4
      ..term = openTerm ? '15,30' : '1m'
      ..additionalChargeUpfrontCollection = 0
      ..additionalLoanAmounts = []
      ..penalties = List<Penalty>.of(penalties)
      ..allowLatePayments = false;

/// A row as stored or computed. [balance] is the balance after the row's
/// principal; [amountDue] is its `amortization`.
LoanSchedule rowOf({
  required String id,
  required DateTime due,
  required double amountDue,
  required double balance,
  required bool openTerm,
  double principal = 0,
  LoanStatus status = LoanStatus.not_paid_overdue,
  DateTime? collectedAt,
}) =>
    LoanSchedule()
      ..id = id
      ..loanId = 'loan-1'
      ..companyId = 'co-1'
      ..createdAt = due
      ..updatedAt = due
      ..dueAt = due
      ..paidAt = collectedAt
      ..collectedAt = collectedAt
      ..status = status
      ..isOpenTerm = openTerm
      ..outstandingBalance = balance
      ..principalPayment = principal
      ..interestPayment = 0
      ..interestCharge = amountDue - principal
      ..amortization = amountDue
      ..extraPayment = 0
      ..advanceInterestPayments = 0
      ..interestDayMultiplier = 1;

// Open-term fixture.
LoanSchedule paidAug30() => rowOf(
      id: 'aug30',
      due: DateTime(2026, 8, 30),
      amountDue: 1000,
      balance: 40000,
      openTerm: true,
      status: LoanStatus.paid_on_time,
      collectedAt: DateTime(2026, 8, 30),
    );
LoanSchedule sep15() => rowOf(
      id: 'sep15',
      due: DateTime(2026, 9, 15),
      amountDue: 1000,
      balance: 40000,
      openTerm: true,
    );
LoanSchedule sep30() => rowOf(
      id: 'sep30',
      due: DateTime(2026, 9, 30),
      amountDue: 1000,
      balance: 40000,
      openTerm: true,
    );

/// The Aug 30 bill as G14 stores it (nothing recorded), for the engine.
LoanSchedule engineAug30() => LoanSchedule()
  ..id = 'sched-1'
  ..loanId = 'loan-1'
  ..companyId = 'co-1'
  ..createdAt = DateTime(2026, 8, 30)
  ..updatedAt = DateTime(2026, 8, 30)
  ..dueAt = DateTime(2026, 8, 30)
  ..paidAt = DateTime(2026, 8, 30)
  ..status = LoanStatus.paid_on_time
  ..isOpenTerm = true
  ..outstandingBalance = 40000
  ..principalPayment = 0
  ..interestPayment = 0
  ..interestCharge = 0
  ..amortization = 0
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

// Fixed-term fixture.
LoanSchedule r1() => rowOf(
      id: 'r1',
      due: DateTime(2026, 8),
      amountDue: 2500,
      principal: 2000,
      balance: 8000,
      openTerm: false,
      status: LoanStatus.paid_on_time,
      collectedAt: DateTime(2026, 8),
    );
LoanSchedule r2() => rowOf(
      id: 'r2',
      due: DateTime(2026, 8, 31),
      amountDue: 2500,
      principal: 2100,
      balance: 5900,
      openTerm: false,
    );
LoanSchedule r3() => rowOf(
      id: 'r3',
      due: DateTime(2026, 9, 30),
      amountDue: 2500,
      principal: 2205,
      balance: 3695,
      openTerm: false,
    );

final oct2 = DateTime(2026, 10, 2, 12);
final oct5 = DateTime(2026, 10, 5, 12);
final oct10 = DateTime(2026, 10, 10, 12);

/// [rows] paid together on [collectedAt], as every bulk path does:
/// `applyLateness` row by row, oldest first, with the loan's rows. Returns
/// the penalty stored on each row, after checking that the dialog's
/// breakdown (`resolveLatenessTogether`) shows the same.
List<double> payTogether({
  required Loan loan,
  required List<LoanSchedule> rows,
  required List<LoanSchedule> context,
  required DateTime collectedAt,
}) {
  final together = resolveLatenessTogether(
    schedules: rows,
    loan: loan,
    collectedAt: collectedAt,
    loanRows: context,
  );
  for (final row in rows) {
    row.status = PaymentConfirmationService.applyLateness(
      schedule: row,
      loan: loan,
      collectedAt: collectedAt,
      actorId: 'teller-1',
      loanRows: context,
    );
  }
  final stored = rows.map((r) => r.penalty).toList();
  for (var i = 0; i < rows.length; i++) {
    expect(together[i].penalties.total, closeTo(stored[i], 0.005));
  }
  return stored;
}

/// One row paid on its own on [collectedAt].
double payOne({
  required Loan loan,
  required LoanSchedule row,
  required List<LoanSchedule> context,
  required DateTime collectedAt,
}) {
  row.status = PaymentConfirmationService.applyLateness(
    schedule: row,
    loan: loan,
    collectedAt: collectedAt,
    actorId: 'teller-1',
    loanRows: context,
  );
  return row.penalty;
}

List<double> previews({
  required Loan loan,
  required List<LoanSchedule> rows,
  required List<LoanSchedule> context,
  required DateTime asOf,
}) =>
    [
      for (final row in rows)
        previewPenalty(
          schedule: row,
          loan: loan,
          asOf: asOf,
          loanRows: context,
        ).total,
    ];

Matcher amounts(List<double> expected) => pairwiseCompare<double, double>(
      expected,
      (e, a) => (e - a).abs() < 0.005,
      'within 0.005 of',
    );

void main() {
  group("G15 open-term, the owner's loan (40,000, the 15th and 30th)", () {
    for (final (penalty, expected) in [
      (percent(0.1, daily, basedOn: balance), [680.0, 0.0]),
      (percent(10, monthly, basedOn: balance), [4000.0, 0.0]),
      (percent(10, perInstallment, basedOn: balance), [8000.0, 0.0]),
    ]) {
      test(
          'O1 ${penalty.amount}% ${penalty.frequency.name} of the balance, '
          'both paid Oct 2 -> ${expected.first}', () {
        final loan = loanOf(openTerm: true, penalties: [penalty]);
        final rows = [sep15(), sep30()];
        final context = [paidAug30(), ...rows];

        expect(
          previews(loan: loan, rows: rows, context: context, asOf: oct2),
          amounts(expected),
        );
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: context,
            collectedAt: oct2,
          ),
          amounts(expected),
        );
        expect(rows.map((r) => r.daysLate), [17, 2]);
        expect(
          rows.map((r) => r.status),
          [LoanStatus.paid_late, LoanStatus.paid_late],
        );
      });
    }

    for (final (penalty, expected) in [
      (percent(1, daily, basedOn: bill), [170.0, 20.0]),
      (percent(10, monthly, basedOn: bill), [100.0, 100.0]),
      (percent(10, perInstallment, basedOn: bill), [200.0, 100.0]),
    ]) {
      test(
          'O2 ${penalty.amount}% ${penalty.frequency.name} of the missed '
          'bill, both paid Oct 2 -> $expected', () {
        final loan = loanOf(openTerm: true, penalties: [penalty]);
        final rows = [sep15(), sep30()];
        final context = [paidAug30(), ...rows];

        expect(
          previews(loan: loan, rows: rows, context: context, asOf: oct2),
          amounts(expected),
        );
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: context,
            collectedAt: oct2,
          ),
          amounts(expected),
        );
      });
    }

    test("O2 the borrower's Pay now on Oct 2: 1,000 + 1,000 + 190 = 2,190", () {
      final loan = loanOf(
        openTerm: true,
        penalties: [percent(1, daily, basedOn: bill)],
      );
      final due = borrowerAmountsDue(
        schedules: [paidAug30(), sep15(), sep30()],
        loan: loan,
        asOf: oct2,
      );

      expect(due.payNow.map((s) => s.id), ['sep15', 'sep30']);
      expect(due.nextDuePenalty, closeTo(190, 0.005));
      expect(due.nextDueAmount, closeTo(2190, 0.005));
    });

    test(
        'O3 the 15th paid on the 30th with the 30th: 1,000 + 100 + 1,000 '
        '= 2,100', () {
      final loan = loanOf(
        openTerm: true,
        penalties: [percent(10, once, basedOn: bill)],
      );
      final sep30Noon = DateTime(2026, 9, 30, 12);
      final due = borrowerAmountsDue(
        schedules: [paidAug30(), sep15(), sep30()],
        loan: loan,
        asOf: sep30Noon,
      );
      expect(due.payNow.map((s) => s.id), ['sep15', 'sep30']);
      expect(due.nextDuePenalty, closeTo(100, 0.005));
      expect(due.nextDueAmount, closeTo(2100, 0.005));

      final rows = [sep15(), sep30()];
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: [paidAug30(), ...rows],
          collectedAt: sep30Noon,
        ),
        amounts([100, 0]),
      );
      expect(rows.map((r) => r.daysLate), [15, 0]);
      expect(
        rows.map((r) => r.status),
        [LoanStatus.paid_late, LoanStatus.paid_on_time],
      );
    });

    test('O4 partial catch-up, 1% daily of the missed bill: 170, then 100', () {
      final loan = loanOf(
        openTerm: true,
        penalties: [percent(1, daily, basedOn: bill)],
      );
      final first = sep15();
      final second = sep30();
      final context = [paidAug30(), first, second];

      expect(
        payOne(loan: loan, row: first, context: context, collectedAt: oct2),
        closeTo(170, 0.005),
      );
      expect(
        previews(loan: loan, rows: [second], context: context, asOf: oct10),
        amounts([100]),
      );
      expect(
        payOne(loan: loan, row: second, context: context, collectedAt: oct10),
        closeTo(100, 0.005),
      );
      expect(second.daysLate, 10);
    });

    test('O5 mixed: 850 + 20 together; 850 then 420 as a partial catch-up', () {
      final loan = loanOf(
        openTerm: true,
        penalties: [
          percent(1, daily, basedOn: bill, name: 'Bill'),
          percent(0.1, daily, basedOn: balance, name: 'Balance'),
        ],
      );

      final rows = [sep15(), sep30()];
      final context = [paidAug30(), ...rows];
      expect(
        previews(loan: loan, rows: rows, context: context, asOf: oct2),
        amounts([850, 20]),
      );
      final first = previewPenalty(
        schedule: rows[0],
        loan: loan,
        asOf: oct2,
        loanRows: context,
      );
      expect(first.lines.map((l) => l.penalty.name), ['Bill', 'Balance']);
      expect(first.lines.map((l) => l.amount).toList(), amounts([170, 680]));
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: context,
          collectedAt: oct2,
        ),
        amounts([850, 20]),
      );

      final a = sep15();
      final b = sep30();
      final partial = [paidAug30(), a, b];
      expect(
        payOne(loan: loan, row: a, context: partial, collectedAt: oct2),
        closeTo(850, 0.005),
      );
      expect(
        payOne(loan: loan, row: b, context: partial, collectedAt: oct10),
        closeTo(420, 0.005),
      );
    });

    test('O6 flat amounts are per missed bill: 100 + 100, 850 + 100', () {
      for (final (penalty, expected) in [
        (flat(100, once), [100.0, 100.0]),
        (flat(50, daily), [850.0, 100.0]),
        (flat(100, once, basedOn: balance), [100.0, 100.0]),
      ]) {
        final loan = loanOf(openTerm: true, penalties: [penalty]);
        final rows = [sep15(), sep30()];
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: [paidAug30(), ...rows],
            collectedAt: oct2,
          ),
          amounts(expected),
          reason: '${penalty.amount} ${penalty.frequency.name} '
              '${penalty.basedOn}',
        );
      }
    });

    test('O6b partial catch-up, 50 a day flat: 850, then 500 (own 10 days)',
        () {
      final loan = loanOf(openTerm: true, penalties: [flat(50, daily)]);
      final first = sep15();
      final second = sep30();
      final context = [paidAug30(), first, second];

      expect(
        payOne(loan: loan, row: first, context: context, collectedAt: oct2),
        closeTo(850, 0.005),
      );
      expect(
        previews(loan: loan, rows: [second], context: context, asOf: oct10),
        amounts([500]),
      );
      expect(
        payOne(loan: loan, row: second, context: context, collectedAt: oct10),
        closeTo(500, 0.005),
      );
      expect(second.daysLate, 10);
    });

    test('O7 saved without "Based on": the balance, as today (680, 600)', () {
      final legacy = Penalty.fromJson(const {
        'id': 'legacy',
        'name': 'Daily',
        'amount': 0.1,
        'is_percentage': true,
        'frequency': 'daily',
      });
      expect(legacy.basedOn, isNull);
      expect(legacy.baseFor(isOpenTerm: true), balance);

      final loan = loanOf(openTerm: true, penalties: [legacy]);
      final rows = [sep15(), sep30()];
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: [paidAug30(), ...rows],
          collectedAt: oct2,
        ),
        amounts([680, 0]),
      );

      // G12 P4: balance 10,000, 5 days late, 100 once + 1% daily.
      final g12 = loanOf(
        openTerm: true,
        penalties: [
          const Penalty(id: 'late-fee', name: 'Late fee', amount: 100),
          percent(1, daily),
        ],
      );
      final p4 = resolveLateness(
        schedule: rowOf(
          id: 'p4',
          due: DateTime(2026, 8, 15),
          amountDue: 2500,
          balance: 10000,
          openTerm: true,
        ),
        loan: g12,
        collectedAt: DateTime(2026, 8, 20),
      );
      expect(p4.penalties.total, closeTo(600, 0.005));
    });

    test("O8 the engine's own bills: 181.33 + 20 = 201.33", () {
      final stored = engineAug30();
      final rows = LoanCalculationService.calculateOpenTermSchedules(
        amount: 40000,
        date: DateTime(2026, 7, 30),
        interestRate: 5,
        term: '15,30',
        companyId: 'co-1',
        paidSchedules: [stored],
        now: oct2,
      ).schedules.sublist(0, 2);
      expect(
        rows.map((r) => DateUtils.dateOnly(r.dueAt)),
        [DateTime(2026, 9, 15), DateTime(2026, 9, 30)],
      );
      expect(
        rows.map((r) => r.amortization).toList(),
        amounts([1066.67, 1000]),
      );

      final loan = loanOf(
        openTerm: true,
        penalties: [percent(1, daily, basedOn: bill)],
      );
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: [stored, ...rows],
          collectedAt: oct2,
        ),
        amounts([181.33, 20]),
      );
    });

    test('O9 principal paid inside the stretch: 680, then 240 on 30,000', () {
      final loan = loanOf(
        openTerm: true,
        penalties: [percent(0.1, daily, basedOn: balance)],
      );
      final aug30 = engineAug30();
      List<LoanSchedule> engineBills(List<LoanSchedule> stored, DateTime now) =>
          LoanCalculationService.calculateOpenTermSchedules(
            amount: 40000,
            date: DateTime(2026, 7, 30),
            interestRate: 5,
            term: '15,30',
            companyId: 'co-1',
            paidSchedules: stored,
            now: now,
          ).schedules;

      final first = engineBills([aug30], oct2);
      final sep15 = first.first;
      expect(
        payOne(
          loan: loan,
          row: sep15,
          context: [aug30, ...first],
          collectedAt: oct2,
        ),
        closeTo(680, 0.005),
      );
      // A teller's payment of the interest and 10,000 principal.
      sep15
        ..id = 'sep15'
        ..paidAt = oct2
        ..interestPayment = sep15.amortization
        ..principalPayment = 10000
        ..outstandingBalance = 30000;

      final later = engineBills([aug30, sep15], oct10);
      final sep30 = later.first;
      expect(DateUtils.dateOnly(sep30.dueAt), DateTime(2026, 9, 30));
      expect(sep30.outstandingBalance, 30000);
      expect(sep30.amortization, closeTo(750, 0.005));
      expect(
        payOne(
          loan: loan,
          row: sep30,
          context: [aug30, sep15, ...later],
          collectedAt: oct10,
        ),
        closeTo(240, 0.005),
      );
    });
  });

  group('G15 fixed-term (10,000 at 5%, 2,500 a month)', () {
    for (final (penalty, expected) in [
      (percent(1, daily, basedOn: bill), [875.0, 125.0]),
      (percent(10, once, basedOn: bill), [250.0, 250.0]),
    ]) {
      test(
          'F1 ${penalty.amount}% ${penalty.frequency.name} of the missed '
          'bill, R2 and R3 paid Oct 5 -> $expected', () {
        final loan = loanOf(openTerm: false, penalties: [penalty]);
        final rows = [r2(), r3()];
        final context = [r1(), ...rows];

        expect(
          previews(loan: loan, rows: rows, context: context, asOf: oct5),
          amounts(expected),
        );
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: context,
            collectedAt: oct5,
          ),
          amounts(expected),
        );
        expect(rows.map((r) => r.daysLate), [35, 5]);
      });
    }

    for (final (penalty, expected) in [
      (percent(0.1, daily, basedOn: balance), [280.0, 0.0]),
      (percent(10, once, basedOn: balance), [800.0, 0.0]),
      (percent(10, monthly, basedOn: balance), [1600.0, 0.0]),
    ]) {
      test(
          'F2 ${penalty.amount}% ${penalty.frequency.name} of the balance '
          '(8,000), R2 and R3 paid Oct 5 -> ${expected.first}', () {
        final loan = loanOf(openTerm: false, penalties: [penalty]);
        final rows = [r2(), r3()];
        final context = [r1(), ...rows];

        expect(
          previews(loan: loan, rows: rows, context: context, asOf: oct5),
          amounts(expected),
        );
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: context,
            collectedAt: oct5,
          ),
          amounts(expected),
        );
      });
    }

    test(
        'F3 partial catch-up of the balance: 280, then 29.50 (5,900 after '
        'Oct 5)', () {
      final loan = loanOf(
        openTerm: false,
        penalties: [percent(0.1, daily, basedOn: balance)],
      );
      final second = r2();
      final third = r3();
      final context = [r1(), second, third];

      expect(
        payOne(loan: loan, row: second, context: context, collectedAt: oct5),
        closeTo(280, 0.005),
      );
      expect(
        previews(loan: loan, rows: [third], context: context, asOf: oct10),
        amounts([29.50]),
      );
      expect(
        payOne(loan: loan, row: third, context: context, collectedAt: oct10),
        closeTo(29.50, 0.005),
      );
    });

    group('F7-F8 principal paid inside the stretch (engine rows)', () {
      final loan = loanOf(
        openTerm: false,
        penalties: [percent(0.1, daily, basedOn: balance)],
      );

      /// R2 paid on Oct 5 by a teller with [principal], as every teller
      /// handler writes it (`recordTellerPayment`, #140).
      LoanSchedule storedR2(double principal) {
        final row = r2();
        expect(
          payOne(
            loan: loan,
            row: row,
            context: [r1(), row, r3()],
            collectedAt: oct5,
          ),
          closeTo(280, 0.005),
        );
        PaymentConfirmationService.recordTellerPayment(
          row,
          interestPayment: row.interestPayment,
          principalPayment: principal,
        );
        return row..paidAt = oct5;
      }

      /// The Sep 30 bill as the fixed-term engine computes it after R1 and
      /// [r2].
      LoanSchedule nextBill(LoanSchedule r2) =>
          LoanCalculationService.calculateFixedTerm(
            amount: 10000,
            monthsToPay: 5,
            date: DateTime(2026, 7),
            interestRate: 5,
            term: '1m',
            companyId: 'co-1',
            paidSchedules: [r1(), r2],
          ).schedules.first;

      // (principal paid, R2's stored balance = R3's beginning balance, R3's
      // charge on Oct 10). Before #140's fix the handlers stored 900 (4.50)
      // and 3,800 (19).
      for (final (principal, balanceAfter, expected) in [
        (5000.0, 3000.0, 15.0),
        (2100.0, 5900.0, 29.50),
      ]) {
        test('R2 paid Oct 5 with $principal principal: R3 -> $expected', () {
          final second = storedR2(principal);
          expect(second.outstandingBalance, closeTo(balanceAfter, 0.005));

          final third = nextBill(second);
          expect(DateUtils.dateOnly(third.dueAt), DateTime(2026, 9, 30));
          expect(
            third.outstandingBalance + third.principalPayment,
            closeTo(balanceAfter, 0.005),
          );

          final context = [r1(), second, third];
          expect(
            previews(loan: loan, rows: [third], context: context, asOf: oct10),
            amounts([expected]),
          );
          expect(
            payOne(
              loan: loan,
              row: third,
              context: context,
              collectedAt: oct10,
            ),
            closeTo(expected, 0.005),
          );
        });
      }
    });

    test('F4 mixed: R2 875 + 280 = 1,155, R3 125', () {
      final loan = loanOf(
        openTerm: false,
        penalties: [
          percent(1, daily, basedOn: bill, name: 'Bill'),
          percent(0.1, daily, basedOn: balance, name: 'Balance'),
        ],
      );
      final rows = [r2(), r3()];
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: [r1(), ...rows],
          collectedAt: oct5,
        ),
        amounts([1155, 125]),
      );
    });

    test('F5 flat amounts are per bill: 100 + 100, 1,750 + 250', () {
      for (final (penalty, expected) in [
        (flat(100, once), [100.0, 100.0]),
        (flat(50, daily), [1750.0, 250.0]),
        (flat(100, once, basedOn: balance), [100.0, 100.0]),
      ]) {
        final loan = loanOf(openTerm: false, penalties: [penalty]);
        final rows = [r2(), r3()];
        expect(
          payTogether(
            loan: loan,
            rows: rows,
            context: [r1(), ...rows],
            collectedAt: oct5,
          ),
          amounts(expected),
          reason: '${penalty.amount} ${penalty.frequency.name} '
              '${penalty.basedOn}',
        );
      }
    });

    test('F6 saved without "Based on": the missed bill, as today (1,000, 225)',
        () {
      final legacy = Penalty.fromJson(const {
        'id': 'legacy',
        'name': 'Daily',
        'amount': 1,
        'is_percentage': true,
        'frequency': 'daily',
      });
      expect(legacy.basedOn, isNull);
      expect(legacy.baseFor(isOpenTerm: false), bill);

      final loan = loanOf(openTerm: false, penalties: [legacy]);
      final rows = [r2(), r3()];
      expect(
        payTogether(
          loan: loan,
          rows: rows,
          context: [r1(), ...rows],
          collectedAt: oct5,
        ),
        amounts([875, 125]),
      );

      // G12 P1: amortization 2,500, 5 days late, 100 once + 1% daily.
      final g12 = loanOf(
        openTerm: false,
        penalties: [
          const Penalty(id: 'late-fee', name: 'Late fee', amount: 100),
          percent(1, daily),
        ],
      );
      final p1 = resolveLateness(
        schedule: rowOf(
          id: 'p1',
          due: DateTime(2026, 8, 15),
          amountDue: 2500,
          principal: 2000,
          balance: 10000,
          openTerm: false,
        ),
        loan: g12,
        collectedAt: DateTime(2026, 8, 20),
      );
      expect(
        p1.penalties.lines.map((l) => l.amount).toList(),
        amounts([100, 125]),
      );
      expect(p1.penalties.total, closeTo(225, 0.005));
    });
  });
}
