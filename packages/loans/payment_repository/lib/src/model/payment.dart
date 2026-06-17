import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/src/model/payment_entity.dart';
import 'package:payment_repository/src/model/payment_status.dart';

class Payment extends PaymentEntity implements BaseModel<PaymentEntity> {
  Payment() : super();

  factory Payment.create({
    required String userId,
    required String loanScheduleId,
    String? loanId,
    ImageUrl? transactionPhotoUrl,
    ImageUrl? signatureUrl,
    String? autoCollectRef,
    bool bypassPaymentProof = false,
    String? comment,
    String? confirmedBy,
    DateTime? confirmedAt,
    PaymentStatus status = PaymentStatus.confirmed,
    String? submissionId,
  }) {
    if (!bypassPaymentProof) {
      if (transactionPhotoUrl == null && autoCollectRef == null) {
        throw Exception(
          'transactionPhotoUrl and autoCollectRef cannot be null at the same time',
        );
      }
    }

    final now = DateTime.timestamp();

    return Payment()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..userId = userId
      ..loanScheduleId = loanScheduleId
      ..loanId = loanId
      ..transactionPhotoUrl = transactionPhotoUrl
      ..signatureUrl = signatureUrl
      ..autoCollectRef = autoCollectRef
      ..confirmedBy = confirmedBy
      ..comment = comment
      ..confirmedAt = confirmedAt
      ..status = status
      ..submissionId = submissionId;
  }

  void markConfirmed({required String confirmedById}) {
    status = PaymentStatus.confirmed;
    confirmedBy = confirmedById;
    confirmedAt = DateTime.timestamp();
    rejectionReason = null;
  }

  void markRejected({required String confirmedById, required String reason}) {
    status = PaymentStatus.rejected;
    confirmedBy = confirmedById;
    confirmedAt = DateTime.timestamp();
    rejectionReason = reason;
  }

  @override
  PaymentEntity toEntity() {
    return this;
  }
}
