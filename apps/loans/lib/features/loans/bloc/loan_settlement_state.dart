part of 'loan_settlement_bloc.dart';

enum LoanSettlementStatus {
  initial,
  loading,
  success,
  error,
  confirmSettlement,
}

final class LoanSettlementState extends Equatable {
  const LoanSettlementState() : this._();

  const LoanSettlementState._({
    this.status = LoanSettlementStatus.initial,
    this.isLoading = false,
    this.message,
    this.remainingBalance,
    this.userId,
    this.closeDialog = false,
  });

  const LoanSettlementState.loading({
    bool isLoading = false,
  }) : this._(
          isLoading: isLoading,
          status: LoanSettlementStatus.loading,
        );

  const LoanSettlementState.success(
    String? message, {
    bool closeDialog = false,
  }) : this._(
          message: message,
          status: LoanSettlementStatus.success,
          closeDialog: closeDialog,
        );

  const LoanSettlementState.error(String message)
      : this._(
          message: message,
          status: LoanSettlementStatus.error,
        );

  const LoanSettlementState.confirmSettlement(
    double remainingBalance,
    String userId,
  ) : this._(
          status: LoanSettlementStatus.confirmSettlement,
          remainingBalance: remainingBalance,
          userId: userId,
        );

  final LoanSettlementStatus status;
  final bool isLoading;
  final String? message;
  final double? remainingBalance;
  final String? userId;
  final bool closeDialog;

  @override
  List<Object?> get props => [
        status,
        isLoading,
        message,
        remainingBalance,
        userId,
        closeDialog,
      ];
}
