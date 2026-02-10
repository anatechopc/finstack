part of 'cash_pool_bloc.dart';

enum CashPoolStateStatus {
  initial,
  loading,
  success,
  cashPoolDisplayProcessed,
  error,
}

final class CashPoolState {

  const CashPoolState() : this._();

  const CashPoolState._({
    this.message,
    this.status = CashPoolStateStatus.initial,
    this.isLoading = false,
    this.cashPoolDisplay,
  });

  const CashPoolState.loading({bool isLoading = false})
      : this._(
          status: CashPoolStateStatus.loading,
          isLoading: isLoading,
        );

  const CashPoolState.success(String message)
      : this._(
          message: message,
          status: CashPoolStateStatus.success,
        );

  const CashPoolState.error(String message)
      : this._(
          message: message,
          status: CashPoolStateStatus.error,
        );

  const CashPoolState.cashPoolDisplayProcessed(CashPoolDisplay cashPoolDisplay)
      : this._(
          cashPoolDisplay: cashPoolDisplay,
          status: CashPoolStateStatus.cashPoolDisplayProcessed,
        );
  final String? message;
  final CashPoolStateStatus status;
  final bool isLoading;
  final CashPoolDisplay? cashPoolDisplay;
}
