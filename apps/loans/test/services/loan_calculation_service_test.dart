import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenarios G1-G3 (finstack#112, campaign Gate 1) for
// LoanCalculationService.calculateFixedTerm. Every expected number was
// derived on paper from the formulas BEFORE the test was written (template in
// .claude/skills/finstack-loan-engine-and-reporting-campaign/references/
// golden-scenarios.md).
//
// Assumes a timezone WITHOUT daylight saving (dev boxes are Asia/Manila; CI
// pins TZ=UTC): jiffy adds days as a Duration, so a 15-day hop across a
// fall-back lands at 23:00 the previous day and G2's due dates read a day
// early. See the DST caveat in the reference.
//
// G1 — amount 10000, 3 months, 5%/month, term '1m':
//   P = Pv*R / (1 - (1+R)^-n) = 10000*0.05 / (1 - 1.05^-3)
//     = 500 / (1 - 0.8638376) = 500 / 0.1361624 = 3672.0856
//   loop: interest = OB*R; amort = min(P, OB + interest);
//         principal = amort - interest; OB -= principal
//   | # | beginning OB | interest | principal | ending OB |
//   | 1 |   10000.0000 | 500.0000 | 3172.0856 | 6827.9144 |
//   | 2 |    6827.9144 | 341.3957 | 3330.6899 | 3497.2244 |
//   | 3 |    3497.2244 | 174.8612 | 3497.2244 |    0.0000 |
//   total = 3 * P = 11016.2569; due dates = date + 1, 2, 3 calendar months.
//
// G2 — same loan, term '15d': n doubles to 6, R halves to 0.025:
//   P = 250 / (1 - 1.025^-6) = 250 / 0.1377030 = 1815.4997
//   | # | interest | principal | ending OB |
//   | 1 | 250.0000 | 1565.4997 | 8434.5003 |
//   | 2 | 210.8625 | 1604.6372 | 6829.8631 |
//   | 3 | 170.7466 | 1644.7531 | 5185.1100 |
//   | 4 | 129.6277 | 1685.8720 | 3499.2380 |
//   | 5 |  87.4809 | 1728.0188 | 1771.2192 |
//   | 6 |  44.2805 | 1771.2192 |    0.0000 |
//   total = 6 * P = 10892.9983; due dates step by 15 days from 2026-01-10:
//   Jan 25, Feb 9, Feb 24, Mar 11, Mar 26, Apr 10.
//
// G3 — resume after 1 persisted schedule (OB 36.87, 11%, P 40.92, n = 3):
//   row 1: interest 4.0557, amort min(40.92, 40.9257) = 40.92, OB 0.0057
//   row 2: interest 0.0006, amort min(40.92, 0.0063) = 0.0063, OB 0
//   count = 3 - 1 = 2; the amortization comes from paidSchedules.first.
//
// G1t — the teller records G1's row 1 (PaymentConfirmationService
// .recordTellerPayment, which every teller path calls; finstack#140). The
// row holds OB 6827.9144, the balance after its scheduled principal
// 3172.0856, so the stored balance is 10000 - principal paid:
//   exact 3172.0856 (bulk): OB 6827.9144; rows 2-3 as G1's table, 3672.0856
//     each; total 3 * P = 11016.26.
//   the dialog's 3172.09 (0.0044 above the schedule, the extra payment):
//     OB 6827.91; row 2 interest 341.3955, principal 3330.6901, OB
//     3497.2199; row 3 interest 174.8610, amort min(P, 3672.0809) =
//     3672.0809 (3,672.08); total 3672.09 + 3672.0856 + 3672.0809 =
//     11016.26.
//   1000 extra (4172.09): OB 5827.91, extra 1000.0044; row 2 interest
//     291.3955, principal 3380.6901, OB 2447.2199; row 3 interest 122.3610,
//     amort 2569.5809; total 4672.09 + 3672.0856 + 2569.5809 = 10913.76
//     (10000 principal + 913.76 interest).
//   3000 (short of the schedule): OB 7000, no extra payment.
//   Before the fix the handlers subtracted the principal again: 3655.82
//   (dialog; the dev row PRxL6LHifFWQjITEaQzq), rows 3672.09 + 174.86;
//   2655.82 with the 1000 extra; 3827.91 for 3000.
//   Open-term rows hold the balance before the payment: 10000 paying 2000
//   principal stores 8000; interest only stores 10000 (unchanged).

LoanCalculationResult fixedTerm(String term) =>
    LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: DateTime(2026, 1, 10),
      interestRate: 5,
      term: term,
      companyId: 'co-1',
    );

LoanSchedule persisted() => LoanSchedule()
  ..id = 'real-sched-1'
  ..loanId = 'loan-1'
  ..status = LoanStatus.payment_submitted
  ..dueAt = DateTime(2024, 12, 19)
  ..amortization = 40.92
  ..outstandingBalance = 36.87;

LoanCalculationResult resumed() => LoanCalculationService.calculateFixedTerm(
      amount: 100,
      monthsToPay: 3,
      date: DateTime(2024, 11, 19),
      interestRate: 11,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: [persisted()],
    );

List<DateTime> dueDates(LoanCalculationResult result) =>
    result.schedules.map((s) => DateUtils.dateOnly(s.dueAt)).toList();

void main() {
  group('G1 fixed-term 1m amortization', () {
    test('monthly amortization and total match the hand-computed P', () {
      final result = fixedTerm('1m');

      expect(result.schedules, hasLength(3));
      expect(result.monthlyAmortization, closeTo(3672.09, 0.01));
      expect(result.totalLoanPayment, closeTo(11016.26, 0.05));
    });

    test('each row matches the amortization table', () {
      final result = fixedTerm('1m');
      const interest = [500.00, 341.40, 174.86];
      const principal = [3172.09, 3330.69, 3497.22];
      const balance = [6827.91, 3497.22, 0.0];

      for (var i = 0; i < 3; i++) {
        final row = result.schedules[i];
        expect(row.interestCharge, closeTo(interest[i], 0.01), reason: 'row $i');
        expect(
          row.interestPayment,
          row.interestCharge,
          reason: 'fixed term mirrors interestCharge into interestPayment',
        );
        expect(row.principalPayment, closeTo(principal[i], 0.01), reason: 'row $i');
        expect(row.outstandingBalance, closeTo(balance[i], 0.01), reason: 'row $i');
        expect(row.amortization, closeTo(3672.09, 0.01), reason: 'row $i');
        expect(row.interestDayMultiplier, 1);
        expect(row.isOpenTerm, isFalse);
      }
    });

    test('due dates step by one calendar month', () {
      expect(
        dueDates(fixedTerm('1m')),
        [DateTime(2026, 2, 10), DateTime(2026, 3, 10), DateTime(2026, 4, 10)],
      );
    });
  });

  group('G2 fixed-term 15d halves the rate and doubles the count', () {
    test('six payments at P = 1815.50', () {
      final result = fixedTerm('15d');

      expect(result.schedules, hasLength(6));
      expect(result.monthlyAmortization, closeTo(1815.50, 0.01));
      expect(result.totalLoanPayment, closeTo(10893.00, 0.05));
    });

    test('rows follow the 2.5%-per-period table', () {
      final result = fixedTerm('15d');
      const interest = [250.00, 210.86, 170.75, 129.63, 87.48, 44.28];
      const balance = [8434.50, 6829.86, 5185.11, 3499.24, 1771.22, 0.0];

      for (var i = 0; i < 6; i++) {
        final row = result.schedules[i];
        expect(row.interestCharge, closeTo(interest[i], 0.01), reason: 'row $i');
        expect(row.outstandingBalance, closeTo(balance[i], 0.01), reason: 'row $i');
        expect(row.amortization, closeTo(1815.50, 0.01), reason: 'row $i');
      }
    });

    test('due dates step by 15 days', () {
      expect(
        dueDates(fixedTerm('15d')),
        [
          DateTime(2026, 1, 25),
          DateTime(2026, 2, 9),
          DateTime(2026, 2, 24),
          DateTime(2026, 3, 11),
          DateTime(2026, 3, 26),
          DateTime(2026, 4, 10),
        ],
      );
    });
  });

  group('G3 calculateFixedTerm contract', () {
    // calculateFixedTerm returns ONLY the computed remaining schedules; callers
    // (the teller flow + LoansBloc._calculateLoan) prepend the persisted
    // paidSchedules themselves. This test pins that contract so a future change
    // doesn't reintroduce double-counting in the teller (which does
    // `[...paidSchedules, ...result.schedules]`).
    test('does NOT include the persisted schedules in its output', () {
      final result = resumed();

      expect(
        result.schedules.any((s) => s.id == 'real-sched-1'),
        isFalse,
        reason: 'paidSchedules must not leak into the computed output',
      );
      expect(result.schedules.every((s) => s.id == NO_ID), isTrue);
    });

    test('computes the remaining n-1 rows from the persisted amortization',
        () {
      final result = resumed();

      expect(result.schedules, hasLength(2));
      expect(result.monthlyAmortization, closeTo(40.92, 0.001));
      expect(result.schedules.first.amortization, closeTo(40.92, 0.001));
      expect(result.schedules.first.interestCharge, closeTo(4.0557, 0.0001));
      expect(
        result.schedules.first.outstandingBalance,
        closeTo(0.0057, 0.0001),
      );
      expect(
        DateUtils.dateOnly(result.schedules.first.dueAt),
        DateTime(2025, 1, 19),
      );
    });
  });

  group('G1t the teller records row 1 (#140)', () {
    /// G1's row 1 recorded by a teller paying [principal] (interest as
    /// billed), and the rows the app computes after it.
    ({LoanSchedule stored, List<LoanSchedule> rest, double total}) payRow1(
      double principal,
    ) {
      final row = fixedTerm('1m').schedules.first;
      PaymentConfirmationService.recordTellerPayment(
        row,
        interestPayment: row.interestPayment,
        principalPayment: principal,
      );
      final rest = LoanCalculationService.calculateFixedTerm(
        amount: 10000,
        monthsToPay: 3,
        date: DateTime(2026, 1, 10),
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [row],
      ).schedules;
      final total = rest.fold<double>(
        row.interestPayment + row.principalPayment,
        (sum, s) => sum + s.amortization,
      );

      return (stored: row, rest: rest, total: total);
    }

    test('the scheduled principal: 6,827.91, then two of 3,672.09', () {
      final paid = payRow1(fixedTerm('1m').schedules.first.principalPayment);

      expect(paid.stored.outstandingBalance, closeTo(6827.9144, 0.0001));
      expect(paid.stored.extraPayment, 0);
      expect(paid.rest, hasLength(2));
      expect(
        paid.rest.map((s) => s.amortization),
        everyElement(closeTo(3672.0856, 0.0001)),
      );
      expect(paid.rest.map((s) => s.interestCharge), [
        closeTo(341.3957, 0.0001),
        closeTo(174.8612, 0.0001),
      ]);
      expect(paid.rest.last.outstandingBalance, closeTo(0, 0.0001));
      expect(paid.total, closeTo(11016.2569, 0.0001));
    });

    test("the dialog's 3,172.09: 6,827.91, then 3,672.09 and 3,672.08", () {
      final paid = payRow1(3172.09);

      expect(paid.stored.outstandingBalance, closeTo(6827.91, 0.000001));
      expect(paid.stored.principalPayment, 3172.09);
      expect(paid.stored.extraPayment, closeTo(0.0044, 0.0001));
      expect(paid.rest.map((s) => s.amortization.toStringAsFixed(2)), [
        '3672.09',
        '3672.08',
      ]);
      expect(paid.rest.first.interestCharge, closeTo(341.3955, 0.0001));
      expect(paid.rest.last.outstandingBalance, closeTo(0, 0.0001));
      expect(paid.total.toStringAsFixed(2), '11016.26');
    });

    test('1,000 above the schedule lowers the balance once: 5,827.91', () {
      final paid = payRow1(4172.09);

      expect(paid.stored.outstandingBalance, closeTo(5827.91, 0.000001));
      expect(paid.stored.extraPayment, closeTo(1000.0044, 0.0001));
      expect(paid.rest.map((s) => s.amortization), [
        closeTo(3672.0856, 0.0001),
        closeTo(2569.5809, 0.0001),
      ]);
      expect(paid.rest.last.outstandingBalance, closeTo(0, 0.0001));
      expect(paid.total, closeTo(10913.7565, 0.0001));
    });

    test('a principal short of the schedule: 7,000, no extra payment', () {
      final paid = payRow1(3000);

      expect(paid.stored.outstandingBalance, closeTo(7000, 0.000001));
      expect(paid.stored.extraPayment, 0);
    });

    test('an open-term row holds the balance before the payment', () {
      LoanSchedule bill() => LoanSchedule.create(
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

      final withPrincipal = bill();
      PaymentConfirmationService.recordTellerPayment(
        withPrincipal,
        interestPayment: 500,
        principalPayment: 2000,
      );
      final interestOnly = bill();
      PaymentConfirmationService.recordTellerPayment(
        interestOnly,
        interestPayment: 500,
        principalPayment: 0,
      );

      expect(withPrincipal.outstandingBalance, 8000);
      expect(withPrincipal.principalPayment, 2000);
      expect(withPrincipal.extraPayment, 0);
      expect(interestOnly.outstandingBalance, 10000);
      expect(interestOnly.interestPayment, 500);
    });
  });
}
