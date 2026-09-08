import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenarios G4-G6 and G9-G10 (finstack#112, campaign Gate 1) for the
// open-term engine. The engine reads the wall clock (it clamps past due dates
// to today, and the 'D1,D2' branch uses today's day-of-month when the start
// day is neither salary day), so every scenario is anchored so that `now`
// cannot matter: start dates are one day in the past or fixed in a future
// month, and additional loans are dated in the past (freshly computed
// schedules carry createdAt = now, which is what positions them). The two
// clock-dependent branches stay uncovered until the clock seam exists; G11
// is parked. Both are tracked in the campaign reference, not here.
//
// Assumes a timezone WITHOUT daylight saving (dev boxes are Asia/Manila; CI
// pins TZ=UTC): jiffy floors day diffs and adds days as a Duration, so
// across a spring-forward a proration comes out one day short and across a
// fall-back a due date lands at 23:00 the previous day, i.e. a calendar day
// early once read as a date. That is an engine defect for DST-zone users
// (campaign D11), not something these scenarios cover.
//
// Derivations (interest = OB * rate * diffDays / 30; 1 month = 30 days):
//   G4a '1m'  start = yesterday: due = start + 30d, diff 30, mult 1.0,
//             interest 10000 * 0.05 = 500; principal 0; OB stays 10000;
//             totalLoanPayment = infinity (open term has no fixed total).
//   G4b '15d' due = start + 15d, diff 15, mult 0.5, interest 250.
//   G5  '1,15' start ON the 1st (Mar 1 next year): due = Mar 15, diff 14,
//             mult 14/30 = 0.4667, interest 233.33.
//   G5b '15,1' identical (the engine min/maxes the two days).
//   G5c '1,15' start ON the 15th (Mar 15 next year): due = Apr 1, diff 17,
//             mult 17/30 = 0.5667, interest 283.33.
//   G6  '1m'  start = Feb 1 of the next non-leap year: due = Mar 3
//             (Feb 1 + 30 CALENDAR days, not "next month"), mult 1.0, 500.
//   G9  paid schedule OB 10000 due 10 days ago; additional loan 2000 + 100
//       charges created 5 days ago:
//             placeholder OB = 10000 + 2000 + 100 = 12100, exactly once
//             (finstack#33 root cause 2 double-counted it);
//             placeholder interest = 10000 * 0.05 * 5/30 = 83.33;
//             the adjacent computed schedule is mutated in place to OB 12100
//             and to the same 83.33 interest — current behaviour, pinned;
//             finstack#117 (owner decision) changes it to 12100*0.05*25/30
//             = 504.17 and flips this test.
//   G10 second additional loan 3000 created 3 days ago, supplied NEWEST-FIRST:
//             processed by createdAt ascending, so A1 OB 12100, then
//             A2 OB = 12100 + 3000 = 15100 with interest 12100*0.05*2/30 =
//             40.33, and the computed schedule ends at 15100. Before
//             finstack#33 the reverse iteration produced 15100/15100/13000.

final DateTime today = DateUtils.dateOnly(DateTime.now());

DateTime daysFromToday(int days) => DateUtils.addDaysToDate(today, days);

({
  List<LoanSchedule> schedules,
  double totalLoanPayment,
  double monthlyAmortization,
}) openTerm({required DateTime start, required String term}) =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: 10000,
      date: start,
      interestRate: 5,
      term: term,
      companyId: 'co-1',
    );

/// Every late field is set because the engine's indexOf() compares rows
/// through Equatable ==; only dueAt, outstandingBalance, createdAt and
/// paidAt influence the numbers.
LoanSchedule paidSchedule({
  required String id,
  required DateTime createdAt,
  required DateTime dueAt,
  required double outstandingBalance,
}) =>
    LoanSchedule()
      ..id = id
      ..loanId = 'loan-1'
      ..companyId = 'co-1'
      ..createdAt = createdAt
      ..updatedAt = createdAt
      ..dueAt = dueAt
      ..paidAt = dueAt
      ..status = LoanStatus.paid_on_time
      ..isOpenTerm = true
      ..outstandingBalance = outstandingBalance
      ..principalPayment = 0
      ..interestPayment = 0
      ..interestCharge = 0
      ..amortization = 0
      ..extraPayment = 0
      ..advanceInterestPayments = 0
      ..interestDayMultiplier = 1;

AdditionalLoanAmount additionalLoan({
  required String id,
  required DateTime createdAt,
  required double amount,
  double charges = 0,
}) =>
    AdditionalLoanAmount()
      ..id = id
      ..amount = amount
      ..additionalCharges = charges
      ..advanceCharges = 0
      ..createdAt = createdAt
      ..status = LoanStatus.approved;

void main() {
  group('G4 open-term proration', () {
    final start = daysFromToday(-1);

    test('G4a 1m: 30-day month, interest only, infinite total', () {
      final r = openTerm(start: start, term: '1m');

      expect(r.schedules, hasLength(1));
      final s = r.schedules.single;
      expect(DateUtils.dateOnly(s.dueAt), daysFromToday(29));
      expect(s.interestDayMultiplier, closeTo(1, 1e-9));
      expect(s.interestCharge, closeTo(500, 0.01));
      expect(s.amortization, closeTo(500, 0.01));
      expect(s.principalPayment, 0);
      expect(s.outstandingBalance, closeTo(10000, 0.01));
      expect(s.isOpenTerm, isTrue);
      expect(
        s.interestPayment,
        0,
        reason: 'open term keeps its interest in interestCharge',
      );
      expect(r.monthlyAmortization, closeTo(500, 0.01));
      expect(
        r.totalLoanPayment,
        double.infinity,
        reason: 'sentinel: open term has no fixed total — change deliberately',
      );
    });

    test('G4b 15d: half a month', () {
      final s = openTerm(start: start, term: '15d').schedules.single;

      expect(DateUtils.dateOnly(s.dueAt), daysFromToday(14));
      expect(s.interestDayMultiplier, closeTo(0.5, 1e-9));
      expect(s.interestCharge, closeTo(250, 0.01));
      expect(s.amortization, closeTo(250, 0.01));
      expect(s.outstandingBalance, closeTo(10000, 0.01));
    });
  });

  group('G5 salary-day terms', () {
    final nextYear = DateTime.now().year + 1;

    test('G5 "1,15": starting on the 1st hops to the 15th (14/30)', () {
      final s =
          openTerm(start: DateTime(nextYear, 3), term: '1,15').schedules.single;

      expect(DateUtils.dateOnly(s.dueAt), DateTime(nextYear, 3, 15));
      expect(s.interestDayMultiplier, closeTo(14 / 30, 1e-9));
      expect(s.interestCharge, closeTo(233.33, 0.01));
    });

    test('G5b "15,1": the order of the two days does not matter', () {
      final s =
          openTerm(start: DateTime(nextYear, 3), term: '15,1').schedules.single;

      expect(DateUtils.dateOnly(s.dueAt), DateTime(nextYear, 3, 15));
      expect(s.interestDayMultiplier, closeTo(14 / 30, 1e-9));
      expect(s.interestCharge, closeTo(233.33, 0.01));
    });

    test('G5c starting on the 15th hops to the 1st of next month (17/30)', () {
      final s = openTerm(start: DateTime(nextYear, 3, 15), term: '1,15')
          .schedules
          .single;

      expect(DateUtils.dateOnly(s.dueAt), DateTime(nextYear, 4));
      expect(s.interestDayMultiplier, closeTo(17 / 30, 1e-9));
      expect(s.interestCharge, closeTo(283.33, 0.01));
    });
  });

  test('G6 month boundary: Feb 1 + 30 calendar days = Mar 3 (non-leap)', () {
    var year = DateTime.now().year + 1;
    while (DateTime(year, 2, 29).month == 2) {
      year++; // skip leap years so Feb has 28 days
    }

    final s = openTerm(start: DateTime(year, 2), term: '1m').schedules.single;

    expect(DateUtils.dateOnly(s.dueAt), DateTime(year, 3, 3));
    expect(s.interestDayMultiplier, closeTo(1, 1e-9));
    expect(s.interestCharge, closeTo(500, 0.01));
  });

  group('G9/G10 additional loans on an open-term loan (finstack#33)', () {
    LoanCalculationResult run(List<AdditionalLoanAmount> additionalLoans) {
      final loan = Loan()
        ..id = 'loan-1'
        ..createdAt = daysFromToday(-40)
        ..additionalChargeUpfrontCollection = 0
        ..additionalLoanAmounts = additionalLoans;

      return LoanCalculationService.calculateOpenTerm(
        amount: 10000,
        date: loan.createdAt,
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [
          paidSchedule(
            id: 'sched-1',
            createdAt: daysFromToday(-40),
            dueAt: daysFromToday(-10),
            outstandingBalance: 10000,
          ),
        ],
        loan: loan,
      );
    }

    AdditionalLoanAmount a1() => additionalLoan(
          id: 'al-1',
          createdAt: daysFromToday(-5),
          amount: 2000,
          charges: 100,
        );

    AdditionalLoanAmount a2() =>
        additionalLoan(id: 'al-2', createdAt: daysFromToday(-3), amount: 3000);

    test('G9 one additional loan raises the balance exactly once', () {
      final s = run([a1()]).schedules;

      expect(s.map((e) => e.id).toList(), [NO_ID, 'sched-1', 'al-1', NO_ID]);
      expect(s[0].isPlaceholder, isTrue);
      expect(s[0].principalLoan, 10000);
      expect(s[0].outstandingBalance, 0);
      expect(
        s[1].outstandingBalance,
        closeTo(10000, 0.01),
        reason: 'a paid row created before the top-up is left alone',
      );

      final placeholder = s[2];
      expect(placeholder.isAdditionalLoanAmount, isTrue);
      expect(placeholder.isPlaceholder, isTrue);
      expect(placeholder.principalLoan, 2000);
      expect(placeholder.outstandingBalance, closeTo(12100, 0.01));
      expect(placeholder.interestDayMultiplier, closeTo(5 / 30, 1e-9));
      expect(placeholder.interestCharge, closeTo(83.33, 0.01));
      expect(DateUtils.dateOnly(placeholder.dueAt), daysFromToday(-5));

      final next = s[3];
      expect(next.isPlaceholder, isFalse);
      expect(DateUtils.dateOnly(next.dueAt), daysFromToday(20));
      expect(
        next.outstandingBalance,
        closeTo(12100, 0.01),
        reason: 'the adjacent computed schedule is updated in place',
      );
      expect(
        next.interestCharge,
        closeTo(83.33, 0.01),
        reason: 'current behaviour: copied from the placeholder instead of '
            '12100 * 5% * 25/30 = 504.17 — flips with finstack#117',
      );
    });

    test('G10 additional loans supplied newest-first are processed oldest-first',
        () {
      final s = run([a2(), a1()]).schedules;

      expect(
        s.map((e) => e.id).toList(),
        [NO_ID, 'sched-1', 'al-1', 'al-2', NO_ID],
      );
      expect(s[2].outstandingBalance, closeTo(12100, 0.01));
      expect(s[3].outstandingBalance, closeTo(15100, 0.01));
      expect(s[3].interestDayMultiplier, closeTo(2 / 30, 1e-9));
      expect(s[3].interestCharge, closeTo(40.33, 0.01));
      expect(s[4].outstandingBalance, closeTo(15100, 0.01));
    });
  });
}
