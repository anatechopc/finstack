import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  const daily100 = Penalty(
    id: 'p1',
    name: 'Late fee',
    amount: 100,
    frequency: PenaltyFrequency.daily,
  );

  LoanSchedule row() => LoanSchedule()
    ..id = 's1'
    ..loanId = 'l1'
    ..status = LoanStatus.not_paid
    ..dueAt = DateTime(2026, 8, 15)
    ..amortization = 5000
    ..outstandingBalance = 5000
    ..isOpenTerm = false;

  Loan loan({
    bool allowLate = false,
    List<Penalty> penalties = const [daily100],
  }) =>
      Loan()
        ..id = 'l1'
        ..term = '1m'
        ..penalties = List<Penalty>.of(penalties)
        ..allowLatePayments = allowLate;

  group('PaymentConfirmationService.applyLateness', () {
    test('on time: paid_on_time, zero penalty, no snapshot', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 15),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.collectedAt, DateTime(2026, 8, 15));
      expect(s.daysLate, 0);
      expect(s.penalty, 0);
      expect(s.penalties, isEmpty);
      expect(s.penaltyWaivedBy, isNull);
    });

    test('late: paid_late, penalty charged, definitions snapshotted', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_late);
      expect(s.daysLate, 3);
      expect(s.penalty, 300);
      expect(s.penalties.single.id, 'p1');
    });

    test('allow late payments: paid_on_time but days late recorded', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(allowLate: true),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.daysLate, 3);
      expect(s.penalty, 0);
    });

    test('waive zeroes the charge and records who and why', () {
      final s = row();
      PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
        waivePenalty: true,
        waiveReason: '  goodwill  ',
      );
      expect(s.penalty, 0);
      expect(s.penaltyWaivedBy, 'teller-1');
      expect(s.penaltyWaiveReason, 'goodwill');
      expect(s.penalties.single.id, 'p1');
    });

    test('waive without a reason throws before touching the row', () {
      final s = row();
      expect(
        () => PaymentConfirmationService.applyLateness(
          schedule: s,
          loan: loan(),
          collectedAt: DateTime(2026, 8, 18),
          actorId: 'teller-1',
          waivePenalty: true,
          waiveReason: ' ',
        ),
        throwsException,
      );
      expect(s.collectedAt, isNull);
    });

    test('waive on an on-time row is a no-op, no reason needed', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 15),
        actorId: 'teller-1',
        waivePenalty: true,
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.penaltyWaivedBy, isNull);
    });
  });

  group('PaymentConfirmationService.revertedStatus', () {
    test('overdue when dueAt is past, else not_paid', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final future = DateTime.now().add(const Duration(days: 1));
      expect(
        PaymentConfirmationService.revertedStatus(dueAt: past),
        LoanStatus.not_paid_overdue,
      );
      expect(
        PaymentConfirmationService.revertedStatus(dueAt: future),
        LoanStatus.not_paid,
      );
    });
  });
}
