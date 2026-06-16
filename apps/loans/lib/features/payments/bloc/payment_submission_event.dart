part of 'payment_submission_bloc.dart';

sealed class PaymentSubmissionEvent {}

/// Submit a transaction screenshot as proof for the given [schedules]
/// (one schedule for "Pay now", all remaining unpaid for "Pay in full").
final class SubmitPaymentEvent extends PaymentSubmissionEvent {
  SubmitPaymentEvent({
    required this.schedules,
    required this.loanId,
    required this.fileBytes,
    required this.fileName,
  });
  final List<LoanSchedule> schedules;

  /// The REAL loan id. Runtime-generated open-term schedules carry a
  /// placeholder `loanId`, so the caller must pass the actual loan id here.
  final String loanId;
  final Uint8List fileBytes;
  final String fileName;
}
