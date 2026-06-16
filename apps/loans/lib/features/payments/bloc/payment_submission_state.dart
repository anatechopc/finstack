part of 'payment_submission_bloc.dart';

enum PaymentSubmissionStatus { initial, submitting, success, error }

final class PaymentSubmissionState extends Equatable {
  const PaymentSubmissionState({
    this.status = PaymentSubmissionStatus.initial,
    this.message,
  });

  final PaymentSubmissionStatus status;
  final String? message;

  PaymentSubmissionState copyWith({
    PaymentSubmissionStatus? status,
    String? message,
  }) =>
      PaymentSubmissionState(status: status ?? this.status, message: message);

  @override
  List<Object?> get props => [status, message];
}
