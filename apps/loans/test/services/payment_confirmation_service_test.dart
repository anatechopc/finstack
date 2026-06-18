import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';

void main() {
  group('PaymentConfirmationService.scheduleStatusForConfirmation', () {
    test('on-time when dueAt is in the future', () {
      final due = DateTime.now().add(const Duration(days: 3));
      expect(
        PaymentConfirmationService.scheduleStatusForConfirmation(dueAt: due),
        LoanStatus.paid_on_time,
      );
    });

    test('late when dueAt is in the past', () {
      final due = DateTime.now().subtract(const Duration(days: 3));
      expect(
        PaymentConfirmationService.scheduleStatusForConfirmation(dueAt: due),
        LoanStatus.paid_late,
      );
    });

    test('revertedStatus is overdue when dueAt is past, else not_paid', () {
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
