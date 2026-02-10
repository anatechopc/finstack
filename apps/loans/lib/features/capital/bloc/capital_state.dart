part of 'capital_bloc.dart';

enum CapitalStateStatus {
  initial,
  loading,
  error,
  success;
}

final class CapitalState {
  CapitalState(): this._();

  const CapitalState._({
    this.status = CapitalStateStatus.initial,
    this.isLoading = false,
    this.message,
  });

  const CapitalState.loading({ bool isLoading = false,}): this._(
    isLoading: isLoading,
    status: CapitalStateStatus.loading,
  );

  const CapitalState.error({ required String message}): this._(
    message: message,
    status: CapitalStateStatus.error,
  );


  const CapitalState.success({ String? message}): this._(
    message: message,
    status: CapitalStateStatus.success,
  );

  final bool isLoading;
  final String? message;
  final CapitalStateStatus status;
}
