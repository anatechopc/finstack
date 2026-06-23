part of 'auth_action_cubit.dart';

enum AuthActionStatus {
  verifying,
  ready,
  invalid,
  submitting,
  done,
  error,
}

final class AuthActionState {
  const AuthActionState() : this._();
  const AuthActionState._({
    this.status = AuthActionStatus.verifying,
    this.email,
    this.errorMessage,
  });

  const AuthActionState.verifying()
      : this._(status: AuthActionStatus.verifying);

  const AuthActionState.ready({required String email})
      : this._(status: AuthActionStatus.ready, email: email);

  const AuthActionState.invalid({required String errorMessage})
      : this._(status: AuthActionStatus.invalid, errorMessage: errorMessage);

  const AuthActionState.submitting({String? email})
      : this._(status: AuthActionStatus.submitting, email: email);

  const AuthActionState.done({String? email})
      : this._(status: AuthActionStatus.done, email: email);

  const AuthActionState.error({required String errorMessage, String? email})
      : this._(
          status: AuthActionStatus.error,
          email: email,
          errorMessage: errorMessage,
        );

  final AuthActionStatus status;
  final String? email;
  final String? errorMessage;
}
