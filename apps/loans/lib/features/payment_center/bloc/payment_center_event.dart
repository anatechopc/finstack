part of 'payment_center_bloc.dart';

sealed class PaymentCenterEvent extends Equatable {
  const PaymentCenterEvent();
}

final class SearchBorrowersEvent extends PaymentCenterEvent {
  const SearchBorrowersEvent({required this.query});
  final String query;

  @override
  List<Object?> get props => [query];
}

final class SelectBorrowerEvent extends PaymentCenterEvent {
  const SelectBorrowerEvent({required this.borrower});
  final User borrower;

  @override
  List<Object?> get props => [borrower];
}

final class ClearBorrowerEvent extends PaymentCenterEvent {
  const ClearBorrowerEvent();

  @override
  List<Object?> get props => [];
}

final class ExpandLoanEvent extends PaymentCenterEvent {
  const ExpandLoanEvent({required this.loanId, required this.loan});
  final String loanId;
  final Loan loan;

  @override
  List<Object?> get props => [loanId, loan];
}

final class CollapseLoanEvent extends PaymentCenterEvent {
  const CollapseLoanEvent({required this.loanId});
  final String loanId;

  @override
  List<Object?> get props => [loanId];
}

final class MakePaymentEvent extends PaymentCenterEvent {
  const MakePaymentEvent({
    required this.loan,
    required this.schedule,
    required this.payment,
    this.interestPayment = 0,
    this.fileName,
    this.fileBytes,
    this.signatureBytes,
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

final class MakeOverduePaymentEvent extends PaymentCenterEvent {
  const MakeOverduePaymentEvent({
    required this.loan,
    required this.schedules,
    required this.totalPrincipalPayment,
    required this.totalInterestPayment,
    this.fileName,
    this.fileBytes,
    this.signatureBytes,
    this.force = false,
    this.otpVerified = false,
    this.collectedAt,
    this.waivePenalty = false,
    this.waiveReason,
  });

  final Loan loan;
  final List<LoanSchedule> schedules;
  final double totalPrincipalPayment;
  final double totalInterestPayment;
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
        schedules,
        totalPrincipalPayment,
        totalInterestPayment,
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

final class RequestOtpEvent extends PaymentCenterEvent {
  const RequestOtpEvent({required this.borrowerUserId});
  final String borrowerUserId;

  @override
  List<Object?> get props => [borrowerUserId];
}

final class VerifyOtpEvent extends PaymentCenterEvent {
  const VerifyOtpEvent({required this.token, required this.otp});
  final String token;
  final String otp;

  @override
  List<Object?> get props => [token, otp];
}

final class RefreshBorrowerDataEvent extends PaymentCenterEvent {
  @override
  List<Object?> get props => [];
}

final class ConfirmSubmissionEvent extends PaymentCenterEvent {
  const ConfirmSubmissionEvent({
    required this.payments,
    this.collectedAt,
    this.waivePenalty = false,
    this.waiveReason,
  });
  final List<Payment> payments;
  final DateTime? collectedAt;
  final bool waivePenalty;
  final String? waiveReason;

  @override
  List<Object?> get props => [payments, collectedAt, waivePenalty, waiveReason];
}

final class RejectSubmissionEvent extends PaymentCenterEvent {
  const RejectSubmissionEvent({required this.payments, required this.reason});
  final List<Payment> payments;
  final String reason;

  @override
  List<Object?> get props => [payments, reason];
}
