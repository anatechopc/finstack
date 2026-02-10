part of 'payment_bloc.dart';

enum PaymentStatus {
  initial,
  loading,
  success,
  error,
}

final class PaymentState extends Equatable {
  const PaymentState() : this._();

  const PaymentState._({
    this.status = PaymentStatus.initial,
    this.isLoading = false,
    this.message,
  });

  const PaymentState.loading({
    bool isLoading = false,
  }) : this._(
          isLoading: isLoading,
          status: PaymentStatus.loading,
        );

  const PaymentState.success(String? message)
      : this._(
          message: message,
          status: PaymentStatus.success,
        );

  const PaymentState.error(String message)
      : this._(
          message: message,
          status: PaymentStatus.error,
        );

  final PaymentStatus status;
  final bool isLoading;
  final String? message;

  @override
  List<Object?> get props => [
        status,
        isLoading,
        message,
      ];
}
