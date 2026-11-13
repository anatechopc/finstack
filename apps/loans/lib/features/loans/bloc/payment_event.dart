part of 'payment_bloc.dart';

sealed class PaymentEvent extends Equatable {
  const PaymentEvent();
}

final class PayLoanScheduleEvent extends PaymentEvent {
  const PayLoanScheduleEvent({
    required this.loan,
    required this.schedule,
    required this.payment,
    this.fileName,
    this.fileBytes,
    this.signatureBytes,
    this.interestPayment = 0,
    this.force = false,
    this.otpVerified = false,
    this.collectedAt,
    this.waivePenalty = false,
    this.waiveReason,
  });

  final Loan loan;
  final LoanSchedule schedule;
  final double payment;
  final double interestPayment;
  final String? fileName;
  final Uint8List? fileBytes;
  final Uint8List? signatureBytes;
  final bool force;
  final bool otpVerified;

  /// When the money was actually received. Null means now.
  final DateTime? collectedAt;

  /// Provider chose to waive the computed penalty. Needs [waiveReason].
  final bool waivePenalty;
  final String? waiveReason;

  @override
  List<Object?> get props => [
        loan,
        schedule,
        payment,
        interestPayment,
        fileName,
        fileBytes,
        signatureBytes,
        force,
        otpVerified,
        collectedAt,
        waivePenalty,
        waiveReason,
      ];
}

final class RequestPaymentOtpEvent extends PaymentEvent {
  const RequestPaymentOtpEvent({required this.borrowerUserId});
  final String borrowerUserId;
  @override
  List<Object?> get props => [borrowerUserId];
}

final class VerifyPaymentOtpEvent extends PaymentEvent {
  const VerifyPaymentOtpEvent({required this.token, required this.otp});
  final String token;
  final String otp;
  @override
  List<Object?> get props => [token, otp];
}
