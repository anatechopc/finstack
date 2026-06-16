part of 'payment_submission_bloc.dart';

sealed class PaymentSubmissionEvent {}

/// Submit proof for the next due schedule only.
final class SubmitPayNowEvent extends PaymentSubmissionEvent {
  SubmitPayNowEvent({required this.fileBytes, required this.fileName});
  final Uint8List fileBytes;
  final String fileName;
}

/// Submit proof for the entire remaining balance (all unpaid schedules).
final class SubmitPayInFullEvent extends PaymentSubmissionEvent {
  SubmitPayInFullEvent({required this.fileBytes, required this.fileName});
  final Uint8List fileBytes;
  final String fileName;
}
