import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenarios G1-G3 (finstack#112, campaign Gate 1) for
// LoanCalculationService.calculateFixedTerm. Every expected number was
// derived on paper from the formulas BEFORE the test was written (template in
// .claude/skills/finstack-loan-engine-and-reporting-campaign/references/
// golden-scenarios.md).
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

DateTime ymd(DateTime d) => DateTime(d.year, d.month, d.day);

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

void main() {
  group('G1 fixed-term 1m amortization', () {
    final result = fixedTerm('1m');

    test('monthly amortization and total match the hand-computed P', () {
      expect(result.schedules, hasLength(3));
      expect(result.monthlyAmortization, closeTo(3672.09, 0.01));
      expect(result.totalLoanPayment, closeTo(11016.26, 0.05));
    });

    test('each row matches the amortization table', () {
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
        result.schedules.map((s) => ymd(s.dueAt)).toList(),
        [DateTime(2026, 2, 10), DateTime(2026, 3, 10), DateTime(2026, 4, 10)],
      );
    });
  });

  group('G2 fixed-term 15d halves the rate and doubles the count', () {
    final result = fixedTerm('15d');

    test('six payments at P = 1815.50', () {
      expect(result.schedules, hasLength(6));
      expect(result.monthlyAmortization, closeTo(1815.50, 0.01));
      expect(result.totalLoanPayment, closeTo(10893.00, 0.05));
    });

    test('rows follow the 2.5%-per-period table', () {
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
        result.schedules.map((s) => ymd(s.dueAt)).toList(),
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
      expect(result.schedules.first.interestCharge, closeTo(4.0557, 0.001));
      expect(result.schedules.first.outstandingBalance, closeTo(0.0057, 0.001));
      expect(ymd(result.schedules.first.dueAt), DateTime(2025, 1, 19));
    });
  });
}
