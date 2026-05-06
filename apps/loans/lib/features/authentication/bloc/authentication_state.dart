part of 'authentication_bloc.dart';

enum AuthenticationStateStatus {
  initial,
  loading,
  success,
  error,
  verify,
  requestOtp,
  logout,
}

final class AuthenticationState {

  const AuthenticationState() : this._();
  const AuthenticationState._({
    this.status = AuthenticationStateStatus.initial,
    this.isLoading = false,
    this.verifyStatus = UserVerificationStatus.unverified,
    this.message,
    this.token,
    this.expireAt,
    this.canResendAt,
  });

  const AuthenticationState.loading({bool isLoading = false})
      : this._(
          isLoading: isLoading,
          status: AuthenticationStateStatus.loading,
        );

  const AuthenticationState.success({String? message})
      : this._(
          message: message,
          status: AuthenticationStateStatus.success,
        );

  const AuthenticationState.error({required String message})
      : this._(
          message: message,
          status: AuthenticationStateStatus.error,
        );

  const AuthenticationState.verify({
    required UserVerificationStatus verifyStatus,
  }) : this._(
          verifyStatus: verifyStatus,
          status: AuthenticationStateStatus.verify,
        );

  const AuthenticationState.requestOtp({
    required String token,
    required int expireAt,
    required DateTime canResendAt,
  }) : this._(
          token: token,
          expireAt: expireAt,
          canResendAt: canResendAt,
          status: AuthenticationStateStatus.requestOtp,
        );

  const AuthenticationState.logout()
      : this._(status: AuthenticationStateStatus.logout);

  final AuthenticationStateStatus status;
  final bool isLoading;
  final String? message;
  final UserVerificationStatus verifyStatus;
  final String? token;
  final int? expireAt;
  final DateTime? canResendAt;
}
