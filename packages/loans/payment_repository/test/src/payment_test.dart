import 'package:flutter_test/flutter_test.dart';
import 'package:payment_repository/src/model/payment.dart';
import 'package:payment_repository/src/model/payment_entity.dart';
import 'package:payment_repository/src/model/payment_status.dart';

Map<String, dynamic> baseJson() => <String, dynamic>{
      'created_at': 1726137187726,
      'updated_at': 1726137187726,
      'id': 'pay-1',
      'user_id': 'user-1',
      'loan_schedule_id': 'sched-1',
    };

void main() {
  group('PaymentEntity status lifecycle', () {
    test('defaults to confirmed when status is absent (legacy/teller docs)', () {
      final p = PaymentEntity.fromJson(baseJson());
      expect(p.status, PaymentStatus.confirmed);
    });

    test('round-trips status / rejection_reason / submission_id', () {
      final json = baseJson()
        ..['status'] = 'pending'
        ..['rejection_reason'] = 'blurry'
        ..['submission_id'] = 'sub-9'
        ..['loan_id'] = 'loan-9';
      final p = PaymentEntity.fromJson(json);
      expect(p.status, PaymentStatus.pending);
      expect(p.rejectionReason, 'blurry');
      expect(p.submissionId, 'sub-9');
      expect(p.loanId, 'loan-9');
      final out = p.toJson();
      expect(out['status'], 'pending');
      expect(out['rejection_reason'], 'blurry');
      expect(out['submission_id'], 'sub-9');
      expect(out['loan_id'], 'loan-9');
    });

    test('Payment.create defaults to confirmed; can be pending', () {
      final confirmed = Payment.create(
        userId: 'u',
        loanScheduleId: 's',
        bypassPaymentProof: true,
      );
      expect(confirmed.status, PaymentStatus.confirmed);

      final pending = Payment.create(
        userId: 'u',
        loanScheduleId: 's',
        bypassPaymentProof: true,
        status: PaymentStatus.pending,
        submissionId: 'sub-1',
      );
      expect(pending.status, PaymentStatus.pending);
      expect(pending.submissionId, 'sub-1');
    });
  });
}
