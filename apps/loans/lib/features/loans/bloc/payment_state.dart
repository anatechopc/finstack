part of 'payment_bloc.dart';

enum PaymentStatus {
  initial,
  loading,
  success,
  error,
  otpRequested,
  otpVerified,
}

final class PaymentState extends Equatable {
  const PaymentState() : this._();

  const PaymentState._({
    this.status = PaymentStatus.initial,
    this.isLoading = false,
    this.message,
    this.token,
    this.expireAt,
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

  const PaymentState.otpRequested({
    required String token,
    required int expireAt,
  }) : this._(
          token: token,
          expireAt: expireAt,
          status: PaymentStatus.otpRequested,
        );

  const PaymentState.otpVerified()
      : this._(status: PaymentStatus.otpVerified);

  final PaymentStatus status;
  final bool isLoading;
  final String? message;
  final String? token;
  final int? expireAt;

  @override
  List<Object?> get props => [
        status,
        isLoading,
        message,
        token,
        expireAt,
      ];
}
