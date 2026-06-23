import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:user_repository/user_repository.dart';

part 'set_password_state.dart';

/// Drives the branded self-hosted `/set-password` page.
///
/// Unlike the Firebase oobCode flow, the token can only be validated by
/// consuming it, so there is no pre-validation step: the form is shown
/// immediately and the token is checked server-side on submit. On success the
/// backend returns the account email and the screen reuses the existing login
/// flow to auto-sign-in.
class SetPasswordCubit extends Cubit<SetPasswordState> {
  SetPasswordCubit(this._userRepository) : super(const SetPasswordState());

  final UserRepository _userRepository;
  final log = Logger('set_password_cubit');

  /// Sets [newPassword] for the account tied to [token].
  ///
  /// A bad/expired/used token (or a weak password) comes back as a 400 from the
  /// backend, which we surface as an `invalidToken` state with a friendly
  /// "request a new link" message. Anything else is a generic error.
  Future<void> submit({
    required String token,
    required String newPassword,
  }) async {
    emit(const SetPasswordState.submitting());
    try {
      final email = await _userRepository.setPassword(
        token: token,
        newPassword: newPassword,
      );
      emit(SetPasswordState.done(email: email));
    } catch (err) {
      if (err.toString().contains('400')) {
        log.warning('set password rejected (invalid/expired token): $err');
        emit(
          const SetPasswordState.invalidToken(
            errorMessage:
                'This link is invalid or has expired. Please request a new one.',
          ),
        );
      } else {
        log.severe('set password error: $err', err);
        emit(
          const SetPasswordState.error(
            errorMessage: 'Could not set your password. Please try again.',
          ),
        );
      }
    }
  }
}
