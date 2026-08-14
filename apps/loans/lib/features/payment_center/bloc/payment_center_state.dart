part of 'payment_center_bloc.dart';

enum PaymentCenterStatus {
  initial,
  loading,
  searchResults,
  borrowerSelected,
  loanExpanded,
  paymentLoading,
  paymentSuccess,
  otpLoading,
  otpRequested,
  otpVerified,

  /// An OTP step failed but the flow is still recoverable — the user can
  /// resend or correct the code. Kept distinct from [error] because the
  /// screen-level listener pops the topmost root route on [error], which
  /// during the OTP step is the OTP dialog itself: reporting a recoverable
  /// OTP failure as [error] would tear down the payment the message is
  /// telling the user how to fix.
  otpError,
  error,
}

final class PaymentCenterState extends Equatable {
  const PaymentCenterState({
    this.status = PaymentCenterStatus.initial,
    this.isLoading = false,
    this.selectedBorrower,
    this.searchResults = const [],
    this.borrowerLoans = const [],
    this.coMakerLoans = const [],
    this.expandedLoanSchedules = const {},
    this.pendingSubmissions = const {},
    this.message,
    this.otpToken,
    this.otpExpireAt,
  });

  final PaymentCenterStatus status;
  final bool isLoading;
  final User? selectedBorrower;
  final List<User> searchResults;
  final List<BorrowerLoanGroup> borrowerLoans;
  final List<BorrowerLoanGroup> coMakerLoans;
  final Map<String, List<LoanSchedule>> expandedLoanSchedules;

  /// Borrower-submitted payments awaiting confirm/reject, keyed by loan id and
  /// grouped per submission.
  final Map<String, List<PendingSubmission>> pendingSubmissions;
  final String? message;
  final String? otpToken;
  final int? otpExpireAt;

  PaymentCenterState copyWith({
    PaymentCenterStatus? status,
    bool? isLoading,
    User? selectedBorrower,
    List<User>? searchResults,
    List<BorrowerLoanGroup>? borrowerLoans,
    List<BorrowerLoanGroup>? coMakerLoans,
    Map<String, List<LoanSchedule>>? expandedLoanSchedules,
    Map<String, List<PendingSubmission>>? pendingSubmissions,
    String? message,
    String? otpToken,
    int? otpExpireAt,
  }) {
    return PaymentCenterState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      selectedBorrower: selectedBorrower ?? this.selectedBorrower,
      searchResults: searchResults ?? this.searchResults,
      borrowerLoans: borrowerLoans ?? this.borrowerLoans,
      coMakerLoans: coMakerLoans ?? this.coMakerLoans,
      expandedLoanSchedules:
          expandedLoanSchedules ?? this.expandedLoanSchedules,
      pendingSubmissions: pendingSubmissions ?? this.pendingSubmissions,
      message: message,
      otpToken: otpToken ?? this.otpToken,
      otpExpireAt: otpExpireAt ?? this.otpExpireAt,
    );
  }

  @override
  List<Object?> get props => [
        status,
        isLoading,
        selectedBorrower,
        searchResults,
        borrowerLoans,
        coMakerLoans,
        expandedLoanSchedules,
        pendingSubmissions,
        message,
        otpToken,
        otpExpireAt,
      ];
}
