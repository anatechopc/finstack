part of 'set_password_cubit.dart';

enum SetPasswordStatus {
  ready,
  submitting,
  done,
  invalidToken,
  error,
}

final class SetPasswordState {
  const SetPasswordState() : this._();
  const SetPasswordState._({
    this.status = SetPasswordStatus.ready,
    this.email,
    this.errorMessage,
  });

  const SetPasswordState.ready() : this._();

  const SetPasswordState.submitting()
      : this._(status: SetPasswordStatus.submitting);

  const SetPasswordState.done({required String email})
      : this._(status: SetPasswordStatus.done, email: email);

  const SetPasswordState.invalidToken({required String errorMessage})
      : this._(
          status: SetPasswordStatus.invalidToken,
          errorMessage: errorMessage,
        );

  const SetPasswordState.error({required String errorMessage})
      : this._(status: SetPasswordStatus.error, errorMessage: errorMessage);

  final SetPasswordStatus status;
  final String? email;
  final String? errorMessage;
}
