part of 'user_bloc.dart';

@immutable
sealed class UserEvent extends Equatable {
  const UserEvent();
}

final class SelectUserEvent extends UserEvent {

  const SelectUserEvent({required this.userId});
  final String userId;

  @override
  List<Object?> get props => [
        userId,
      ];
}

final class UpdateUserEvent extends UserEvent {

  const UpdateUserEvent({
    required this.fields,
    required this.user,
  });
  final Map<String, dynamic> fields;
  final User user;

  @override
  List<Object?> get props => [
        fields,
        user,
      ];
}
