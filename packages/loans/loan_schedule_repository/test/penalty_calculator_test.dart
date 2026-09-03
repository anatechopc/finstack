import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  const daily100 = Penalty(
    id: 'p1',
    name: 'Late fee',
    amount: 100,
    frequency: PenaltyFrequency.daily,
  );
  const monthly2pct = Penalty(
    id: 'p2',
    name: 'Surcharge',
    amount: 2,
    isPercentage: true,
    frequency: PenaltyFrequency.monthly,
  );
  const once500 = Penalty(id: 'p3', name: 'Bounced cheque', amount: 500);
  const weekly50 = Penalty(
    id: 'p4',
    name: 'Weekly',
    amount: 50,
    frequency: PenaltyFrequency.weekly,
  );

  group('calculateDaysLate', () {
    test('collected on the due date is not late', () {
      expect(
        calculateDaysLate(
          dueAt: DateTime(2026, 8, 15),
          collectedAt: DateTime(2026, 8, 15, 23, 59),
        ),
        0,
      );
    });

    test('collected before the due date is not late', () {
      expect(
        calculateDaysLate(
          dueAt: DateTime(2026, 8, 15),
          collectedAt: DateTime(2026, 8, 10),
        ),
        0,
      );
    });

    test('counts calendar days across a month boundary', () {
      expect(
        calculateDaysLate(
          dueAt: DateTime(2026, 8, 15),
          collectedAt: DateTime(2026, 9, 3),
        ),
        19,
      );
    });

    test('ignores time of day', () {
      expect(
        calculateDaysLate(
          dueAt: DateTime(2026, 8, 15, 9),
          collectedAt: DateTime(2026, 8, 16, 1),
        ),
        1,
      );
    });
  });

  group('computePenalties', () {
    test('nothing when not late', () {
      final result = computePenalties(
        amountDue: 5000,
        penalties: [daily100],
        daysLate: 0,
      );

      expect(result.total, 0);
      expect(result.lines, isEmpty);
    });

    test('nothing when the loan has no penalties', () {
      final result = computePenalties(
        amountDue: 5000,
        penalties: const [],
        daysLate: 10,
      );

      expect(result.total, 0);
      expect(result.lines, isEmpty);
    });

    test('daily fixed penalty multiplies by days', () {
      final result = computePenalties(
        amountDue: 5000,
        penalties: [daily100],
        daysLate: 19,
      );

      expect(result.total, 1900);
      expect(result.lines.single.periods, 19);
      expect(result.lines.single.amount, 1900);
    });

    test('monthly percentage rounds a started month up', () {
      final result = computePenalties(
        amountDue: 5000,
        penalties: [monthly2pct],
        daysLate: 31,
      );

      expect(result.total, 200);
      expect(result.lines.single.periods, 2);
    });

    test('once charges a single period however late', () {
      expect(
        computePenalties(amountDue: 5000, penalties: [once500], daysLate: 90)
            .total,
        500,
      );
    });

    test('weekly: 7 days is one week, 8 days is two', () {
      expect(
        computePenalties(amountDue: 5000, penalties: [weekly50], daysLate: 7)
            .total,
        50,
      );
      expect(
        computePenalties(amountDue: 5000, penalties: [weekly50], daysLate: 8)
            .total,
        100,
      );
    });

    test('spec worked example: 19 days late totals 2000', () {
      final result = computePenalties(
        amountDue: 5000,
        penalties: [daily100, monthly2pct],
        daysLate: 19,
      );

      expect(result.total, 2000);
      expect(result.lines.map((l) => l.amount), [1900, 100]);
      expect(result.lines.map((l) => l.penalty), [daily100, monthly2pct]);
    });
  });

  group('previewPenalty', () {
    LoanSchedule schedule({
      LoanStatus status = LoanStatus.not_paid,
      bool isOpenTerm = false,
    }) {
      return LoanSchedule.create(
        dueAt: DateTime(2026, 8, 15),
        loanId: 'l1',
        outstandingBalance: 20000,
        principalPayment: 4500,
        interestCharge: 500,
        amortization: 5000,
        interestDayMultiplier: 1,
        companyId: 'c1',
        status: status,
        isOpenTerm: isOpenTerm,
      );
    }

    Loan loan({
      bool allowLatePayments = false,
      List<Penalty> penalties = const [monthly2pct],
    }) {
      return Loan.create(
        userId: 'u1',
        companyId: 'c1',
        productId: 'pr1',
        amount: 20000,
        additionalCharges: 0,
        deductions: 0,
        period: 4,
        requirements: const [],
        isForceCollect: false,
        status: LoanStatus.approved,
        dueAt: null,
        reason: 'test',
        interestRate: 3,
        term: '1m',
        amortization: 5000,
        penalties: penalties,
        allowLatePayments: allowLatePayments,
      );
    }

    final asOf = DateTime(2026, 9, 3);

    test('overdue row on a term loan uses amortization as the base', () {
      final result = previewPenalty(
        schedule: schedule(),
        loan: loan(),
        asOf: asOf,
      );

      expect(result.total, 100);
    });

    test('open-term row uses outstanding balance as the base', () {
      final result = previewPenalty(
        schedule: schedule(isOpenTerm: true),
        loan: loan(),
        asOf: asOf,
      );

      expect(result.total, 400);
    });

    test('allow late payments suppresses the penalty', () {
      final result = previewPenalty(
        schedule: schedule(),
        loan: loan(allowLatePayments: true),
        asOf: asOf,
      );

      expect(result.total, 0);
    });

    test('a submitted-but-unconfirmed row still previews', () {
      final result = previewPenalty(
        schedule: schedule(status: LoanStatus.payment_submitted),
        loan: loan(),
        asOf: asOf,
      );

      expect(result.total, 100);
    });

    test('a paid row has no preview', () {
      final result = previewPenalty(
        schedule: schedule(status: LoanStatus.paid_on_time),
        loan: loan(),
        asOf: asOf,
      );

      expect(result.total, 0);
    });

    test('a row not yet due has no preview', () {
      final result = previewPenalty(
        schedule: schedule(),
        loan: loan(),
        asOf: DateTime(2026, 8, 10),
      );

      expect(result.total, 0);
    });
  });
}
