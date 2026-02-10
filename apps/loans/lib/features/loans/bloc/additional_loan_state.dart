part of 'additional_loan_bloc.dart';

enum AdditionalLoanStatus {
  initial,
  loading,
  success,
  error,
}

final class AdditionalLoanState extends Equatable {
  const AdditionalLoanState() : this._();

  const AdditionalLoanState._({
    this.status = AdditionalLoanStatus.initial,
    this.isLoading = false,
    this.message,
  });

  const AdditionalLoanState.loading({
    bool isLoading = false,
  }) : this._(
          isLoading: isLoading,
          status: AdditionalLoanStatus.loading,
        );

  const AdditionalLoanState.success(String? message)
      : this._(
          message: message,
          status: AdditionalLoanStatus.success,
        );

  const AdditionalLoanState.error(String message)
      : this._(
          message: message,
          status: AdditionalLoanStatus.error,
        );

  final AdditionalLoanStatus status;
  final bool isLoading;
  final String? message;

  @override
  List<Object?> get props => [
        status,
        isLoading,
        message,
      ];
}
