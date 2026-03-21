part of 'payment_center_bloc.dart';

enum PaymentCenterStatus {
  initial,
  loading,
  searchResults,
  borrowerSelected,
  loanExpanded,
  paymentLoading,
  paymentSuccess,
  otpRequested,
  otpVerified,
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
        message,
        otpToken,
        otpExpireAt,
      ];
}
