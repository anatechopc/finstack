import 'package:authentication_repository/authentication_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans_helpers/logging_helpers.dart';

part 'auth_action_state.dart';

/// Drives the branded Firebase password-reset / complete-sign-up action page.
///
/// Verifies the incoming `oobCode` (exposing the email it belongs to) and then
/// confirms the new password. The screen reuses the existing login flow for the
/// actual sign-in once the password has been set.
class AuthActionCubit extends Cubit<AuthActionState> {
  AuthActionCubit(this._authRepository)
      : super(const AuthActionState());

  final AuthenticationRepository _authRepository;
  final log = Logger('auth_action_cubit');

  /// Validates the [oobCode] and, on success, surfaces the email it is for.
  Future<void> verify(String oobCode) async {
    emit(const AuthActionState.verifying());
    try {
      final email = await _authRepository.verifyPasswordResetCode(oobCode);
      emit(AuthActionState.ready(email: email));
    } on AuthenticationException catch (err) {
      log.warning('verify reset code failed: ${err.message}');
      emit(AuthActionState.invalid(errorMessage: err.message));
    } catch (err) {
      log.severe('verify reset code error: $err', err);
      emit(const AuthActionState.invalid(
        errorMessage: 'This link is no longer valid. Please try again.',
      ),);
    }
  }

  /// Sets [newPassword] for the account tied to [oobCode].
  ///
  /// Preserves the verified email across the submit lifecycle so the form stays
  /// usable on failure and the listener can auto-sign-in on success.
  Future<void> submit({
    required String oobCode,
    required String newPassword,
  }) async {
    final email = state.email;
    emit(AuthActionState.submitting(email: email));
    try {
      await _authRepository.confirmPasswordReset(
        code: oobCode,
        newPassword: newPassword,
      );
      emit(AuthActionState.done(email: email));
    } on AuthenticationException catch (err) {
      log.warning('confirm reset failed: ${err.message}');
      emit(AuthActionState.error(email: email, errorMessage: err.message));
    } catch (err) {
      log.severe('confirm reset error: $err', err);
      emit(AuthActionState.error(
        email: email,
        errorMessage: 'Could not set your password. Please try again.',
      ),);
    }
  }
}
