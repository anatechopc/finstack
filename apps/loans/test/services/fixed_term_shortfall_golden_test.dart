import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';

// Golden scenario set G16 — a fixed-term principal shortfall (finstack#152,
// owner decision 2026-11-19). Every number below was derived by hand (and
// checked in a throwaway script that is not the code under test) BEFORE the
// engine changed.
//
// The rules:
//   1. The next bill is its amortization plus the principal the previous
//      row left unpaid (the row's billed principal, amortization -
//      interestCharge, less the principal recorded; to the centavo). The
//      last bill clears the whole remaining balance, rounding included.
//      Rounding (review of #156): a bill that carries a shortfall is in
//      centavos, the figures the dialog fills in: amount = the
//      amortization to the centavo + the carry, interest to the centavo
//      (rounded once), principal = amount - that interest, and the next
//      row starts from the balance after that principal. The projection
//      then equals the rows after payment, and the shown bills sum to what
//      is owed. The last bill on a balance in whole centavos (after payments
//      at the dialog's figures) rounds its interest once too, so its fills
//      add up to it (the 960-case grid). Other bills keep the unrounded
//      amortization (G1, unchanged).
//   2. A shortfall on the last bill (owner, 2026-11-20): no extra bill;
//      the last bill stays open, overdue after its due date, until it is
//      paid. Its rest is a second row of the same bill (same due date, no
//      interest, `partPaidAt` = when the short payment was collected), so
//      each payment is its own stored row; screens show one bill per due
//      date (`oneBillPerDueDate`). Penalties within the bill (default, for
//      the owner to confirm): every penalty counts its periods from the
//      bill's due date, and the rest is charged only the periods after
//      those the short payment was charged (daily: the days after it;
//      monthly: a month that starts after it; once: nothing more), so no
//      period of the bill is charged twice (re-check of #156).
//   4. A penalty on the missed bill is a percent of the carried bill's full
//      amount; one on the balance reads the balance in force (unchanged).
//   The loan is completed only when every bill is paid AND a paid row left
//   no more than 0.005 owed.
//
// G1 loan: 10,000, 3 months, 5%, '1m', dated 2026-01-10. P = 3,672.0856
// (golden G1). Bills due Feb 10, Mar 10, Apr 10.
//
// G16a, the owner's example. Bill 1 paid 500 + 3,000 (billed principal
//   3,172.0856): stored balance 7,000; shortfall 172.0856 -> 172.09.
//   Bill 2: 3,672.09 + 172.09 = 3,844.18; interest 7,000 x 5% = 350;
//     principal 3,494.18; balance 3,505.82.
//   Bill 3: interest 175.291 → 175.29 (a whole-centavo balance),
//     principal 3,505.82, amount 3,681.11, the same before and after bill 2
//     is paid as the dialog fills it (350.00 + 3,494.18, no extra payment).
//   Shown bills 3,844.18 + 3,681.11 = 7,525.29 = owed 7,000 + 350 +
//   175.29. Total paid 3,500 + 3,844.18 + 3,681.11 = 11,025.29 (on time
//   11,016.26). Before the fix: bills 2 and 3 were 3,672.09 each, the
//   stored balance after bill 3 was 189.72, and nothing billed it. First
//   version of this PR: bill 2 3,844.1756 (principal 3,494.1756), bill 3
//   3,681.1156, shown 7,525.30, one centavo more than owed.
//   The dev row holds the amortization unrounded (3,672.0856463124487):
//   the same figures.
//   Interest not in whole centavos (second review of #156): bill 1 paid
//   500 + 2,999.50 → balance 7,000.50, carry 172.59, bill 2 3,844.68,
//   interest 350.025 → 350.03 (rounded once), principal 3,844.68 − 350.03
//   = 3,494.65, balance 3,505.85; bill 3 3,505.85 + 175.2925 → 175.29 =
//   3,681.14. Shown 3,844.68 + 3,681.14 = 7,525.82 = owed 7,000.50 +
//   350.03 + 175.29. Before: the dialog filled 350.03 + 3,494.66 =
//   3,844.69.
//
// G16b, short on bill 2 of 3. Bill 1 paid 500 + 3,172.09: balance 6,827.91.
//   Bill 2: interest 341.3955, principal 3,330.6901; paid 341.40 + 3,000:
//   stored balance 3,827.91 (shortfall 330.69). Bill 3, the last, clears
//   it: interest 191.3955 → 191.40, principal 3,827.91, amount 4,019.31
//   (not P + 330.69 = 4,002.78: the last bill is the balance plus its
//   interest). Total paid 3,672.09 + 3,341.40 + 4,019.31 = 11,032.80.
//   Before the fix bill 3 was 3,672.09 and 347.22 was left.
//
// G16c, short on the last bill. Bills 1 and 2 paid at their billed
//   principal: balances 6,827.9144 and 3,497.2244. Bill 3: interest
//   174.8612, principal 3,497.2244; paid 174.8612 + 3,000: stored balance
//   497.2244. The rest of bill 3: due Apr 10, 497.2244, interest 0,
//   balance after 0; screens list 3 bills, bill 3 showing 497.22. Paid on
//   Apr 20 under 1% a day of the missed bill (the short payment was on
//   time, so from the due date): 10 x 4.972244 = 49.7224. Paid short again
//   with 400: the rest is 97.2244, still due Apr 10, still 3 bills. Paid in
//   full: total 2 x 3,672.0856 + 3,174.8612 + 497.2244 = 11,016.2569 (no
//   new interest); bill 3 shows 174.8612 + 3,497.2244 as one paid row.
//
// G16i, the last bill short, with penalties (owner, 2026-11-20; 100 once +
//   1% a day of the missed bill; bills 1 and 2 paid on time at their
//   billed principal; bill 3 is 3,672.0856 = 174.8612 + 3,497.2244, due Apr
//   10):
//   Short, late: Apr 15, 174.86 + 3,000: 100 + 5 x 36.720856 = 283.6043,
//     balance 497.2244. The rest counts from Apr 15 and the 100 was
//     charged: paid Apr 25, 10 x 4.972244 = 49.7224 (counted from Apr 10
//     with the 100 again it would be 174.5837). Bill 3 shown paid late,
//     174.86 + 3,497.2244, penalty 333.3267, 15 days late.
//   Short twice: Apr 15 as above (283.6043); Apr 20, 300 of 497.2244: 5 x
//     4.972244 = 24.8612, balance 197.2244; the rest counts from Apr 20:
//     paid Apr 30, 10 x 1.972244 = 19.7224. Penalty 328.1879.
//   Short on time, then late: Apr 10, 174.86 + 3,000: 0; the rest paid Apr
//     30, from the due date and the bill's first lateness: 100 + 20 x
//     4.972244 = 199.4449.
//   (Daily: days(due → rest) − days(due → short) = the days after the
//   short payment; once: 1 − 1 = 0 after a late short payment.)
//
// G16j, 5% a month of the missed bill (re-check of #156): bill 3 paid
//   short Apr 15, 5 days late: months(5) = 1, 5% x 3,672.0856 = 183.6043;
//   balance 497.2244. The rest paid Apr 30, 20 days after the due date:
//   months(20) − months(5) = 1 − 1 = 0, nothing more (counted from Apr 15
//   it was a new month, 5% x 497.2244 = 24.8612). Paid May 15, 35 days
//   after: months(35) − months(5) = 2 − 1 = 1, 24.8612; bill 3 208.4655.
//
// G16d, no carry. Bill 1 paid at its billed principal: bills 2 and 3 are
//   3,672.0856 (G1t). A sub-centavo shortfall: bill 1 paid 3,172.09, bill 2
//   paid 3,330.69 against 3,330.6901 (0.0001 short, 0.00 to the centavo):
//   balance 3,497.22, bill 3 = 3,497.22 + 174.861 → 174.86 = 3,672.08.
//
// G16e, extra. Bill 1 paid 4,172.09 (1,000.0044 above): balance 5,827.91,
//   bills 3,672.0856 and 2,569.5809 (G1t, unchanged).
//
// G16f, '15d' (G2: 6 bills, R 2.5%, P 1,815.4997). Bill 1 paid 250 + 1,000
//   (billed principal 1,565.4997): balance 9,000, shortfall 565.50.
//   | bill | amount    | interest | principal | balance   |
//   | 2    | 2381.0000 | 225.0000 | 2156.0000 | 6844.0000 |
//   | 3    | 1815.4997 | 171.1000 | 1644.3997 | 5199.6003 |
//   | 4    | 1815.4997 | 129.9900 | 1685.5097 | 3514.0906 |
//   | 5    | 1815.4997 |  87.8523 | 1727.6474 | 1786.4431 |
//   | 6    | 1831.1042 |  44.6611 | 1786.4431 |    0.0000 |
//   Due Feb 9, Feb 24, Mar 11, Mar 26, Apr 10. Shown bills sum 9,658.60 =
//   owed 9,000 + interest 658.6033. Total paid 10,908.6034 (on time
//   10,893.00).
//
// G16g, completion. Every bill paid and a paid row at 0.005 or less:
//   completed. G16c's three paid bills (497.2244 owed): not completed; the
//   rest of bill 3 paid: completed. 0.006 owed: not completed.
//
// G16h, early payoff or payment (#155; `isEarlyPayoff`, which both payment
//   dialogs ask before recording). A payment whose principal is at most
//   the row's bill (+ 0.005) is a payment; only more than the bill that
//   also clears the balance before the row goes to settlement.
//   Bill 1 paid 500 + 2,900: carry 272.09, balance 7,100; bill 2 3,944.18
//     = 355.00 + 3,589.18, balance after 3,510.82. The old check (principal
//     >= balance after) sent 3,589.18 to settlement. From a carry of 185.03
//     it trips: 500 + 2,987.05 (185.04) → bill 2 principal 3,506.48,
//     balance after 3,506.47; 2,987.06 (185.03) gives 3,506.47 against
//     3,506.47; 2,987.07 (185.02) gives 3,506.46, no trip.
//   Bill 2 paid as filled, bill 3 (last) = 3,510.82 + 175.541 → 175.54 = 3,686.36:
//     principal 3,510.82 is a payment (balance after 0). Paid 175.54 +
//     3,000: the rest of the last bill, 510.82, is a payment.
//   Grid (the review's probe): 960 bill-1 principals from 2,212.09 to
//     3,171.68, centavos varied: the fills of bill 2, of the last bill and
//     of the rest of a short-paid last bill add up to the shown bill, and
//     none is an early payoff.
//   Settlement: 7,100 on bill 2 (all owed before it); 3,510.83 on the last
//   bill. 5,000 on bill 2 is an extra payment, not settlement.
//   Open-term, unchanged: principal >= the balance (10,000) settles.
//
// Rule 4. G16a's bill 2 (3,844.18) unpaid on Mar 20, 10 days late: 1% a
//   day of the missed bill = 384.418; 0.1% a day of the balance in force
//   (3,505.82 + 3,494.18 = 7,000) = 70.00.

final created = DateTime(2026, 1, 10);

LoanCalculationResult engine(List<LoanSchedule> stored, {String term = '1m'}) =>
    LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: created,
      interestRate: 5,
      term: term,
      companyId: 'co-1',
      paidSchedules: List.of(stored),
    );

/// [row] recorded by a teller (every teller path calls
/// `recordTellerPayment`) and stored with an id.
LoanSchedule pay(
  LoanSchedule row, {
  required double interest,
  required double principal,
}) {
  PaymentConfirmationService.recordTellerPayment(
    row,
    interestPayment: interest,
    principalPayment: principal,
  );

  return row
    ..id = 'sched-${row.dueAt.month}-${row.dueAt.day}-${row.amortization}'
    ..loanId = 'loan-1'
    ..status = LoanStatus.paid_on_time;
}

/// Pays the next bill the engine computes after [stored].
List<LoanSchedule> payNext(
  List<LoanSchedule> stored, {
  double? interest,
  double? principal,
  String term = '1m',
}) {
  final next = engine(stored, term: term).schedules.first;

  return [
    ...stored,
    pay(
      next,
      interest: interest ?? next.interestPayment,
      principal: principal ?? next.principalPayment,
    ),
  ];
}

double totalPaid(List<LoanSchedule> stored) => stored.fold<double>(
      0,
      (sum, s) => sum + s.interestPayment + s.principalPayment,
    );

DateTime day(DateTime d) => DateUtils.dateOnly(d);

class _Payments extends Mock implements PaymentRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Loans extends Mock implements LoanRepository {}

void main() {
  group("G16a the owner's example", () {
    final bill1 = payNext(const [], interest: 500, principal: 3000);

    test('bill 1: 500 + 3,000 stores 7,000, no extra payment', () {
      expect(bill1.single.outstandingBalance, closeTo(7000, 0.000001));
      expect(bill1.single.extraPayment, 0);
    });

    test('bill 2 adds the 172.09 shortfall: 3,844.18; bill 3 clears it', () {
      final rest = engine(bill1).schedules;

      expect(rest, hasLength(2));
      final (bill2, bill3) = (rest.first, rest.last);
      expect(bill2.amortization, closeTo(3844.18, 0.000001));
      expect(bill2.interestCharge, closeTo(350, 0.000001));
      expect(bill2.interestPayment, closeTo(350, 0.000001));
      expect(bill2.principalPayment, closeTo(3494.18, 0.000001));
      expect(bill2.outstandingBalance, closeTo(3505.82, 0.000001));
      expect(day(bill2.dueAt), DateTime(2026, 3, 10));
      expect(bill3.interestCharge, closeTo(175.29, 0.000001));
      expect(bill3.principalPayment, closeTo(3505.82, 0.000001));
      expect(bill3.amortization, closeTo(3681.11, 0.000001));
      expect(bill3.amortization.toStringAsFixed(2), '3681.11');
      expect(bill3.outstandingBalance, closeTo(0, 0.000001));
      expect(day(bill3.dueAt), DateTime(2026, 4, 10));
    });

    test('the dev row as stored (amortization 3,672.0856463124487): '
        '3,844.18, then 3,681.11; the shown bills sum to what is owed', () {
      final devRow = LoanSchedule()
        ..id = 'dAz09ZDes7ZEeIUXypcY'
        ..loanId = 'AlWAkiTsiUIvG7Ia6g8D'
        ..companyId = 'co-1'
        ..status = LoanStatus.paid_late
        ..dueAt = DateTime(2026, 10, 4)
        ..amortization = 3672.0856463124487
        ..interestCharge = 500
        ..interestPayment = 500
        ..principalPayment = 3000
        ..extraPayment = 0
        ..outstandingBalance = 7000
        ..isOpenTerm = false;
      final rest = LoanCalculationService.calculateFixedTerm(
        amount: 10000,
        monthsToPay: 3,
        date: DateTime(2026, 9, 4),
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [devRow],
      ).schedules;

      expect(rest.map((s) => s.amortization.toStringAsFixed(2)), [
        '3844.18',
        '3681.11',
      ]);
      expect(rest.first.principalPayment.toStringAsFixed(2), '3494.18');
      expect(rest.last.principalPayment.toStringAsFixed(2), '3505.82');
      final shown = rest.fold<int>(
        0,
        (sum, s) => sum + (s.amortization * 100).round(),
      );
      final owed = devRow.outstandingBalance +
          rest.fold<double>(0, (sum, s) => sum + s.interestCharge);
      expect(shown, (owed * 100).round(), reason: '7,525.29 both');
      expect(shown, 752529);
    });

    test('interest not in whole centavos (500 + 2,999.50): the parts add up '
        'to the bill, 350.03 + 3,494.65 = 3,844.68', () {
      final rest = engine(
        payNext(const [], interest: 500, principal: 2999.50),
      ).schedules;
      final (bill2, bill3) = (rest.first, rest.last);

      expect(bill2.amortization.toStringAsFixed(2), '3844.68');
      expect(bill2.interestPayment.toStringAsFixed(2), '350.03');
      expect(bill2.principalPayment.toStringAsFixed(2), '3494.65');
      expect(
        double.parse(bill2.interestPayment.toStringAsFixed(2)) +
            double.parse(bill2.principalPayment.toStringAsFixed(2)),
        closeTo(bill2.amortization, 0.000001),
      );
      expect(bill2.outstandingBalance, closeTo(3505.85, 0.000001));
      expect(bill3.amortization, closeTo(3681.14, 0.000001));
      final shown = rest.fold<int>(
        0,
        (sum, s) => sum + (s.amortization * 100).round(),
      );
      final owed = 7000.50 +
          rest.fold<double>(0, (sum, s) => sum + s.interestCharge);
      expect(shown, 752582);
      expect((owed * 100).round(), 752582);
    });

    test("the borrower's Pay now is bill 2: 3,844.18", () {
      final due = borrowerAmountsDue(
        schedules: [...bill1, ...engine(bill1).schedules],
        loan: Loan()
          ..id = 'loan-1'
          ..period = 3
          ..term = '1m'
          ..status = LoanStatus.paid_on_time
          ..penalties = [],
        asOf: DateTime(2026, 3),
      );

      expect(due.payNow, hasLength(1));
      expect(due.nextDueAmount, closeTo(3844.18, 0.000001));
      expect(due.remainingTotal, closeTo(3844.18 + 3681.11, 0.000001));
    });

    test(
        'bill 2 paid as the dialog fills it: bill 3 stays 175.29 + 3,505.82 '
        '= 3,681.11; total 11,025.29', () {
      final two = payNext(bill1, interest: 350, principal: 3494.18);
      expect(two.last.outstandingBalance, closeTo(3505.82, 0.000001));
      expect(two.last.extraPayment, 0);

      final bill3 = engine(two).schedules.single;
      expect(bill3.interestCharge, closeTo(175.29, 0.000001));
      expect(bill3.principalPayment, closeTo(3505.82, 0.000001));
      expect(bill3.amortization, closeTo(3681.11, 0.000001));
      expect(bill3.amortization.toStringAsFixed(2), '3681.11');

      final three = payNext(two);
      expect(three.last.outstandingBalance, closeTo(0, 0.000001));
      expect(engine(three).schedules, isEmpty);
      expect(totalPaid(three).toStringAsFixed(2), '11025.29');
    });
  });

  group('G16b short on bill 2 of 3', () {
    final two = payNext(
      payNext(const [], interest: 500, principal: 3172.09),
      interest: 341.40,
      principal: 3000,
    );

    test('bill 2: 341.40 + 3,000 stores 3,827.91', () {
      expect(two.last.outstandingBalance, closeTo(3827.91, 0.000001));
      expect(two.last.extraPayment, 0);
    });

    test('bill 3, the last, clears the balance: 4,019.31', () {
      final bill3 = engine(two).schedules.single;

      expect(bill3.interestCharge, closeTo(191.40, 0.000001));
      expect(bill3.principalPayment, closeTo(3827.91, 0.000001));
      expect(bill3.amortization, closeTo(4019.31, 0.000001));
      expect(bill3.outstandingBalance, closeTo(0, 0.000001));
      expect(
        totalPaid(payNext(two)),
        closeTo(11032.80, 0.000001),
      );
    });
  });

  group('G16c short on the last bill', () {
    final three = payNext(payNext(payNext(const [])), principal: 3000);
    final apr10 = DateTime(2026, 4, 10);

    test('bill 3: 3,000 of 3,497.22 stores 497.22', () {
      expect(three.map((s) => s.outstandingBalance), [
        closeTo(6827.9144, 0.0001),
        closeTo(3497.2244, 0.0001),
        closeTo(497.2244, 0.0001),
      ]);
    });

    test('the rest of bill 3, 497.22 on Apr 10, no interest; 3 bills shown',
        () {
      final rest = engine(three).schedules.single;

      expect(day(rest.dueAt), apr10);
      expect(rest.amortization, closeTo(497.2244, 0.0001));
      expect(rest.principalPayment, closeTo(497.2244, 0.0001));
      expect(rest.interestCharge, 0);
      expect(rest.interestPayment, 0);
      expect(rest.outstandingBalance, 0);
      expect(rest.status, LoanStatus.not_paid);
      expect(rest.partPaidAt, three.last.dueAt, reason: 'no collection date');
      expect(rest.isOpenTerm, isFalse);
      expect(rest.isPrincipalRelease, isFalse);

      final shown = LoanCalculationService.oneBillPerDueDate([...three, rest]);
      expect(shown, hasLength(3));
      expect(identical(shown.last, rest), isTrue, reason: 'the open bill');
    });

    test('paid Apr 20 under 1% a day of the missed bill: 49.72', () {
      final remainder = engine(three).schedules.single;
      final loan = Loan()
        ..id = 'loan-1'
        ..period = 3
        ..term = '1m'
        ..status = LoanStatus.paid_on_time
        ..allowLatePayments = false
        ..penalties = [
          const Penalty(
            id: 'p-bill',
            name: 'Surcharge',
            amount: 1,
            isPercentage: true,
            frequency: PenaltyFrequency.daily,
            basedOn: PenaltyBase.missedBill,
          ),
        ];

      final penalty = previewPenalty(
        schedule: remainder,
        loan: loan,
        asOf: DateTime(2026, 4, 20, 12),
        loanRows: [...three, remainder],
      );
      expect(penalty.total, closeTo(49.7224, 0.0001));
    });

    test('paid short again with 400: the rest is 97.22, still bill 3', () {
      final four = payNext(three, principal: 400);
      expect(four.last.outstandingBalance, closeTo(97.2244, 0.0001));

      final again = engine(four).schedules.single;
      expect(day(again.dueAt), apr10);
      expect(again.amortization, closeTo(97.2244, 0.0001));
      expect(
        LoanCalculationService.oneBillPerDueDate([...four, again]),
        hasLength(3),
      );
    });

    test('paid in full: nothing left, total 11,016.26 (no new interest); '
        'bill 3 is one paid row', () {
      final four = payNext(three);

      expect(four.last.outstandingBalance, closeTo(0, 0.000001));
      expect(engine(four).schedules, isEmpty);
      expect(totalPaid(four), closeTo(11016.2569, 0.0001));
      final shown = LoanCalculationService.oneBillPerDueDate(four);
      expect(shown, hasLength(3));
      expect(shown.last.amortization, closeTo(3672.0856, 0.0001));
      expect(shown.last.interestPayment, closeTo(174.8612, 0.0001));
      expect(shown.last.principalPayment, closeTo(3497.2244, 0.0001));
      expect(shown.last.outstandingBalance, closeTo(0, 0.000001));
      expect(four, hasLength(4), reason: 'each payment stays its own row');
    });
  });

  group('G16i the last bill short, with penalties (owner, 2026-11-20)', () {
    final loan = Loan()
      ..id = 'loan-1'
      ..period = 3
      ..term = '1m'
      ..status = LoanStatus.paid_on_time
      ..allowLatePayments = false
      ..penalties = [
        const Penalty(id: 'p-fee', name: 'Late fee', amount: 100),
        const Penalty(
          id: 'p-day',
          name: 'Daily',
          amount: 1,
          isPercentage: true,
          frequency: PenaltyFrequency.daily,
          basedOn: PenaltyBase.missedBill,
        ),
      ];

    /// The next bill after [stored] collected on [on], as every teller path
    /// records it: lateness and penalties first, then the amounts (the
    /// billed principal unless [principal]).
    List<LoanSchedule> collect(
      List<LoanSchedule> stored,
      DateTime on, {
      double? principal,
    }) {
      final next = engine(stored).schedules.first;
      final status = PaymentConfirmationService.applyLateness(
        schedule: next,
        loan: loan,
        collectedAt: on,
        actorId: 'teller-1',
        loanRows: LoanCalculationService.oneBillPerDueDate([...stored, next]),
      );
      PaymentConfirmationService.recordTellerPayment(
        next,
        interestPayment: next.interestPayment,
        principalPayment: principal ?? next.principalPayment,
      );

      return [
        ...stored,
        next
          ..id = 'sched-${stored.length + 1}'
          ..loanId = 'loan-1'
          ..status = status
          ..paidAt = on,
      ];
    }

    final onTime = collect(
      collect(const [], DateTime(2026, 2, 10, 12)),
      DateTime(2026, 3, 10, 12),
    );

    test('short and late: 283.60, then the rest from the short payment, '
        '49.72 (not 174.58); one paid bill 3', () {
      final short = collect(onTime, DateTime(2026, 4, 15, 12), principal: 3000);
      expect(onTime.map((s) => s.penalty), [0, 0]);
      expect(short.last.penalty, closeTo(283.6043, 0.0001));
      expect(short.last.status, LoanStatus.paid_late);
      expect(short.last.outstandingBalance, closeTo(497.2244, 0.0001));

      final rest = engine(short).schedules.single;
      expect(rest.partPaidAt, DateTime(2026, 4, 15, 12));
      expect(
        LoanCalculationService.oneBillPerDueDate([...short, rest]),
        hasLength(3),
      );
      expect(
        previewPenalty(
          schedule: rest,
          loan: loan,
          asOf: DateTime(2026, 4, 25, 12),
        ).total,
        closeTo(49.7224, 0.0001),
      );

      final paid = collect(short, DateTime(2026, 4, 25, 12));
      expect(paid.last.penalty, closeTo(49.7224, 0.0001));
      expect(paid.last.outstandingBalance, closeTo(0, 0.000001));
      expect(engine(paid).schedules, isEmpty);
      final shown = LoanCalculationService.oneBillPerDueDate(paid);
      expect(shown, hasLength(3));
      expect(shown.last.status, LoanStatus.paid_late);
      expect(shown.last.penalty, closeTo(333.3267, 0.0001));
      expect(shown.last.daysLate, 15);
      expect(shown.last.principalPayment, closeTo(3497.2244, 0.0001));
    });

    test('short twice: 283.60, 24.86, then 19.72 from the second', () {
      final short = collect(onTime, DateTime(2026, 4, 15, 12), principal: 3000);
      final again = collect(short, DateTime(2026, 4, 20, 12), principal: 300);
      expect(again.last.penalty, closeTo(24.8612, 0.0001));
      expect(again.last.outstandingBalance, closeTo(197.2244, 0.0001));

      final rest = engine(again).schedules.single;
      expect(rest.partPaidAt, DateTime(2026, 4, 20, 12));
      expect(rest.amortization, closeTo(197.2244, 0.0001));
      expect(
        LoanCalculationService.oneBillPerDueDate([...again, rest]),
        hasLength(3),
      );

      final paid = collect(again, DateTime(2026, 4, 30, 12));
      expect(paid.last.penalty, closeTo(19.7224, 0.0001));
      final shown = LoanCalculationService.oneBillPerDueDate(paid);
      expect(shown, hasLength(3));
      expect(shown.last.penalty, closeTo(328.1879, 0.0001));
      expect(shown.last.daysLate, 20);
    });

    test('short on time, then the rest late: 100 + 20 days, 199.44', () {
      final short = collect(onTime, DateTime(2026, 4, 10, 12), principal: 3000);
      expect(short.last.penalty, 0);
      expect(short.last.status, LoanStatus.paid_on_time);

      final paid = collect(short, DateTime(2026, 4, 30, 12));
      expect(paid.last.penalty, closeTo(199.4449, 0.0001));
      expect(paid.last.status, LoanStatus.paid_late);
      final shown = LoanCalculationService.oneBillPerDueDate(paid);
      expect(shown.last.status, LoanStatus.paid_late);
      expect(shown.last.penalty, closeTo(199.4449, 0.0001));
    });
  });

  group('G16j a monthly penalty within a part-paid last bill (re-check of '
      '#156)', () {
    final monthly = Loan()
      ..id = 'loan-1'
      ..period = 3
      ..term = '1m'
      ..status = LoanStatus.paid_on_time
      ..allowLatePayments = false
      ..penalties = [
        const Penalty(
          id: 'p-month',
          name: 'Monthly',
          amount: 5,
          isPercentage: true,
          frequency: PenaltyFrequency.monthly,
          basedOn: PenaltyBase.missedBill,
        ),
      ];

    /// [stored]'s next bill collected on [on] under [monthly].
    List<LoanSchedule> collect(
      List<LoanSchedule> stored,
      DateTime on, {
      double? principal,
    }) {
      final next = engine(stored).schedules.first;
      final status = PaymentConfirmationService.applyLateness(
        schedule: next,
        loan: monthly,
        collectedAt: on,
        actorId: 'teller-1',
        loanRows: LoanCalculationService.oneBillPerDueDate([...stored, next]),
      );
      PaymentConfirmationService.recordTellerPayment(
        next,
        interestPayment: next.interestPayment,
        principalPayment: principal ?? next.principalPayment,
      );

      return [
        ...stored,
        next
          ..id = 'sched-${stored.length + 1}'
          ..loanId = 'loan-1'
          ..status = status
          ..paidAt = on,
      ];
    }

    final short = collect(
      collect(
        collect(const [], DateTime(2026, 2, 10, 12)),
        DateTime(2026, 3, 10, 12),
      ),
      DateTime(2026, 4, 15, 12),
      principal: 3000,
    );

    test('bill 3 paid short 5 days late: one month, 5% of 3,672.09', () {
      expect(short.last.penalty, closeTo(183.6043, 0.0001));
      expect(short.last.outstandingBalance, closeTo(497.2244, 0.0001));
    });

    test('the rest paid 20 days after the due date: no second month '
        '(the first month was charged on the full bill; was 24.86)', () {
      final rest = engine(short).schedules.single;
      expect(
        previewPenalty(
          schedule: rest,
          loan: monthly,
          asOf: DateTime(2026, 4, 30, 12),
        ).total,
        0,
      );
      final paid = collect(short, DateTime(2026, 4, 30, 12));
      expect(paid.last.penalty, 0);
      expect(paid.last.status, LoanStatus.paid_late);
      expect(
        LoanCalculationService.oneBillPerDueDate(paid).last.penalty,
        closeTo(183.6043, 0.0001),
      );
    });

    test('the rest paid 35 days after the due date: one more month, 5% of '
        'the 497.22 still owed', () {
      final paid = collect(short, DateTime(2026, 5, 15, 12));
      expect(paid.last.penalty, closeTo(24.8612, 0.0001));
      expect(
        LoanCalculationService.oneBillPerDueDate(paid).last.penalty,
        closeTo(208.4655, 0.0001),
      );
    });
  });

  test('the grid: 960 bill-1 principals; the fills add up to the shown '
      'bill and none is an early payoff', () {
    String fill(double amount) => amount.toStringAsFixed(2);
    int cents(String text) => (double.parse(text) * 100).round();
    final mismatches = <String>[];

    // Screens show `toCurrency`, which formats `toStringAsFixed(2)`; the
    // dialogs fill the same.
    void check(String what, LoanSchedule bill) {
      final (interest, principal) =
          (fill(bill.interestPayment), fill(bill.principalPayment));
      if (cents(interest) + cents(principal) != cents(fill(bill.amortization))) {
        mismatches.add('$what: $interest + $principal for '
            '${fill(bill.amortization)}');
      }
      if (PaymentConfirmationService.isEarlyPayoff(
        bill,
        principal: double.parse(principal),
      )) {
        mismatches.add('$what: early payoff at $principal');
      }
    }

    for (var k = 0; k < 960; k++) {
      final principal = (221209 + 100 * k + k % 100) / 100;
      var stored = payNext(const [], interest: 500, principal: principal);
      final bill2 = engine(stored).schedules.first;
      check('k=$k bill 2', bill2);
      stored = payNext(
        stored,
        interest: double.parse(fill(bill2.interestPayment)),
        principal: double.parse(fill(bill2.principalPayment)),
      );
      final bill3 = engine(stored).schedules.single;
      check('k=$k bill 3', bill3);
      stored = payNext(
        stored,
        interest: double.parse(fill(bill3.interestPayment)),
        principal: (bill3.principalPayment * 50).round() / 100,
      );
      check('k=$k rest of bill 3', engine(stored).schedules.single);
    }

    expect(mismatches, isEmpty);
  });

  group('G16d no carry', () {
    test('bill 1 at its billed principal: bills 2 and 3 are 3,672.09', () {
      final rest = engine(payNext(const [])).schedules;

      expect(
        rest.map((s) => s.amortization),
        everyElement(closeTo(3672.0856, 0.0001)),
      );
      expect(rest.last.outstandingBalance, closeTo(0, 0.000001));
    });

    test('0.0001 short is 0.00 to the centavo: bill 3 is 3,672.08', () {
      final two = payNext(
        payNext(const [], interest: 500, principal: 3172.09),
        interest: 341.40,
        principal: 3330.69,
      );
      expect(two.last.outstandingBalance, closeTo(3497.22, 0.000001));

      final bill3 = engine(two).schedules.single;
      expect(bill3.amortization, closeTo(3672.08, 0.000001));
      expect(bill3.outstandingBalance, closeTo(0, 0.000001));
    });
  });

  test('G16e 1,000 extra lowers the balance once: 3,672.09 + 2,569.58', () {
    final one = payNext(const [], interest: 500, principal: 4172.09);
    expect(one.single.outstandingBalance, closeTo(5827.91, 0.000001));
    expect(one.single.extraPayment, closeTo(1000.0044, 0.0001));

    expect(engine(one).schedules.map((s) => s.amortization), [
      closeTo(3672.0856, 0.0001),
      closeTo(2569.5809, 0.0001),
    ]);
  });

  test("G16f '15d': 1,000 of 1,565.50 carries 565.50 to bill 2", () {
    final one = payNext(
      const [],
      interest: 250,
      principal: 1000,
      term: '15d',
    );
    expect(one.single.outstandingBalance, closeTo(9000, 0.000001));

    final rest = engine(one, term: '15d').schedules;
    expect(rest.map((s) => s.amortization), [
      closeTo(2381, 0.000001),
      closeTo(1815.4997, 0.0001),
      closeTo(1815.4997, 0.0001),
      closeTo(1815.4997, 0.0001),
      closeTo(1831.1042, 0.0001),
    ]);
    expect(rest.first.principalPayment, closeTo(2156, 0.000001));
    expect(rest.map((s) => s.interestCharge), [
      closeTo(225, 0.0001),
      closeTo(171.1000, 0.0001),
      closeTo(129.9900, 0.0001),
      closeTo(87.8523, 0.0001),
      closeTo(44.6611, 0.0001),
    ]);
    expect(rest.map((s) => s.outstandingBalance), [
      closeTo(6844, 0.000001),
      closeTo(5199.6003, 0.0001),
      closeTo(3514.0906, 0.0001),
      closeTo(1786.4431, 0.0001),
      closeTo(0, 0.0001),
    ]);
    // The shown bills sum to what is owed: 9,658.60.
    expect(
      rest.fold<int>(0, (sum, s) => sum + (s.amortization * 100).round()),
      965860,
    );
    expect(
      ((9000 + rest.fold<double>(0, (sum, s) => sum + s.interestCharge)) *
              100)
          .round(),
      965860,
    );
    expect(rest.map((s) => day(s.dueAt)), [
      DateTime(2026, 2, 9),
      DateTime(2026, 2, 24),
      DateTime(2026, 3, 11),
      DateTime(2026, 3, 26),
      DateTime(2026, 4, 10),
    ]);
    expect(
      rest.fold<double>(totalPaid(one), (sum, s) => sum + s.amortization),
      closeTo(10908.6034, 0.0001),
    );
  });

  group('G16h a payment, or an early payoff for settlement (#155)', () {
    bool payoff(LoanSchedule row, double principal) =>
        PaymentConfirmationService.isEarlyPayoff(row, principal: principal);

    final one = payNext(const [], interest: 500, principal: 2900);
    final bill2 = engine(one).schedules.first;
    final two = payNext(one, principal: 3589.18);
    final bill3 = engine(two).schedules.single;
    final remainder =
        engine(payNext(two, interest: 175.54, principal: 3000)).schedules.single;

    test('bill 2 carrying 272.09: 3,589.18 is a payment (the old check '
        'settled it)', () {
      expect(bill2.amortization, closeTo(3944.18, 0.000001));
      expect(bill2.principalPayment, closeTo(3589.18, 0.000001));
      expect(bill2.outstandingBalance, closeTo(3510.82, 0.000001));
      expect(bill2.principalPayment >= bill2.outstandingBalance, isTrue);
      expect(payoff(bill2, 3589.18), isFalse);
    });

    test('185.04 short trips the old check and is a payment; 185.02 never '
        'tripped it', () {
      final next = engine(
        payNext(const [], interest: 500, principal: 2987.05),
      ).schedules.first;

      expect(next.principalPayment, closeTo(3506.48, 0.000001));
      expect(next.outstandingBalance, closeTo(3506.47, 0.000001));
      expect(next.principalPayment >= next.outstandingBalance, isTrue);
      expect(payoff(next, 3506.48), isFalse);
      final under = engine(
        payNext(const [], interest: 500, principal: 2987.07),
      ).schedules.first;
      expect(under.principalPayment, closeTo(3506.46, 0.000001));
      expect(under.principalPayment < under.outstandingBalance, isTrue);
      expect(payoff(under, 3506.46), isFalse);
    });

    test('the last bill and the remainder row paid as billed are payments',
        () {
      expect(bill3.amortization, closeTo(3686.36, 0.000001));
      expect(bill3.outstandingBalance, closeTo(0, 0.000001));
      expect(payoff(bill3, 3510.82), isFalse);
      expect(remainder.amortization, closeTo(510.82, 0.000001));
      expect(remainder.outstandingBalance, 0);
      expect(payoff(remainder, 510.82), isFalse);
    });

    test('more than the bill that clears what is owed is settlement', () {
      expect(payoff(bill2, 7100), isTrue);
      expect(payoff(bill2, 7099.996), isTrue, reason: 'within 0.005');
      expect(payoff(bill2, 5000), isFalse, reason: 'an extra payment');
      expect(payoff(bill3, 3510.83), isTrue);
    });

    test('open-term is unchanged: principal of at least the balance', () {
      final bill = LoanSchedule.create(
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

      expect(payoff(bill, 10000), isTrue);
      expect(payoff(bill, 9999.99), isFalse);
      expect(payoff(bill, 0), isFalse);
    });
  });

  group('rule 4: the carried bill missed for 10 days', () {
    final bill1 = payNext(const [], interest: 500, principal: 3000);
    final rest = engine(bill1).schedules;

    Loan loanWith(Penalty penalty) => Loan()
      ..id = 'loan-1'
      ..period = 3
      ..term = '1m'
      ..status = LoanStatus.not_paid_overdue
      ..allowLatePayments = false
      ..penalties = [penalty];

    double penaltyOn(Penalty penalty) => previewPenalty(
          schedule: rest.first,
          loan: loanWith(penalty),
          asOf: DateTime(2026, 3, 20, 12),
          loanRows: [...bill1, ...rest],
        ).total;

    test('1% a day of the missed bill: 384.42 of 3,844.18', () {
      expect(
        penaltyOn(
          const Penalty(
            id: 'p-bill',
            name: 'Surcharge',
            amount: 1,
            isPercentage: true,
            frequency: PenaltyFrequency.daily,
            basedOn: PenaltyBase.missedBill,
          ),
        ),
        closeTo(384.418, 0.000001),
      );
    });

    test('0.1% a day of the balance in force: 70.00 of 7,000', () {
      expect(
        penaltyOn(
          const Penalty(
            id: 'p-balance',
            name: 'Surcharge',
            amount: 0.1,
            isPercentage: true,
            frequency: PenaltyFrequency.daily,
            basedOn: PenaltyBase.outstandingBalance,
          ),
        ),
        closeTo(70, 0.000001),
      );
    });
  });

  group('G16g the loan completes only when no principal is owed', () {
    late _Schedules schedules;
    late _Loans loans;
    late PaymentConfirmationService svc;
    late List<LoanSchedule> stored;

    setUpAll(() => registerFallbackValue(Loan()));

    setUp(() {
      schedules = _Schedules();
      loans = _Loans();
      svc = PaymentConfirmationService(
        loanScheduleRepository: schedules,
        loanRepository: loans,
        paymentRepository: _Payments(),
      );
      when(
        () => schedules.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer((_) async => stored);
      when(() => loans.get(id: any(named: 'id'))).thenAnswer(
        (_) async => Loan()
          ..id = 'loan-1'
          ..period = 3
          ..term = '1m'
          ..status = LoanStatus.paid_on_time,
      );
      when(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#data] as Loan);
    });

    Future<bool> completes() async {
      await svc.completeLoanIfFullyPaid('loan-1');
      final updates = verify(
        () => loans.update(
          data: captureAny(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      );

      return updates.callCount == 1 &&
          (updates.captured.single as Loan).status == LoanStatus.completed;
    }

    final shortLast = payNext(payNext(payNext(const [])), principal: 3000);

    test("G16c's three bills paid, 497.22 owed: not completed", () async {
      stored = shortLast;
      await svc.completeLoanIfFullyPaid('loan-1');
      verifyNever(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      );
    });

    test("G16c's remainder paid: completed", () async {
      stored = payNext(shortLast);
      expect(await completes(), isTrue);
    });

    test("G16a's three bills paid: completed", () async {
      stored = payNext(
        payNext(
          payNext(const [], interest: 500, principal: 3000),
          interest: 350,
          principal: 3494.18,
        ),
      );
      expect(await completes(), isTrue);
    });

    for (final (owed, completed) in [(0.006, false), (0.005, true)]) {
      test('every bill paid, $owed owed: completed $completed', () async {
        final rows = payNext(payNext(payNext(const [])));
        rows.last.outstandingBalance = owed;
        stored = rows;
        await svc.completeLoanIfFullyPaid('loan-1');
        if (completed) {
          verify(
            () => loans.update(
              data: any(named: 'data'),
              updateView: any(named: 'updateView'),
            ),
          ).called(1);
        } else {
          verifyNever(
            () => loans.update(
              data: any(named: 'data'),
              updateView: any(named: 'updateView'),
            ),
          );
        }
      });
    }
  });
}
