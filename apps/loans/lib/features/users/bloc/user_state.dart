part of 'user_bloc.dart';

enum UserStatus {
  initial,
  loading,
  success,
  error,
  selected,
  selectedCoMaker,
  selectedCoMakers,
  unselected,
  unselectedCoMaker,
  refresh,
  requireMobileVerify
}

final class UserState {
  const UserState() : this._();

  const UserState._({
    this.user,
    this.message,
    this.isLoading = false,
    this.status = UserStatus.initial,
    this.users = const [],
  });

  const UserState.loading({bool isLoading = false})
      : this._(
          isLoading: isLoading,
          status: UserStatus.loading,
        );

  const UserState.success(
    String? message, {
    User? user,
  }) : this._(
          message: message,
          status: UserStatus.success,
          user: user,
        );

  const UserState.error(String message)
      : this._(
          message: message,
          status: UserStatus.error,
        );

  const UserState.selected({required User user})
      : this._(
          user: user,
          status: UserStatus.selected,
        );

  const UserState.selectedCoMaker({required User user})
      : this._(
          user: user,
          status: UserStatus.selectedCoMaker,
        );

  const UserState.selectedCoMakers({required List<User> users})
      : this._(
          users: users,
          status: UserStatus.selectedCoMaker,
        );

  const UserState.unselected()
      : this._(
          status: UserStatus.unselected,
        );

  const UserState.unselectedCoMaker()
      : this._(
          status: UserStatus.unselectedCoMaker,
        );

  const UserState.refresh()
      : this._(
          status: UserStatus.refresh,
        );

  const UserState.requireMobileVerify({required User user})
      : this._(
          user: user,
          status: UserStatus.requireMobileVerify,
        );

  final User? user;
  final String? message;
  final bool isLoading;
  final UserStatus status;
  final List<User> users;
}
