part of 'registration_bloc.dart';

@immutable
sealed class RegistrationEvent {}

class SubmitUserRegistrationEvent extends RegistrationEvent {

  SubmitUserRegistrationEvent({
    required this.fields,
  });
  final Map<String, dynamic> fields;
}

class SubmitInvitedUserEvent extends RegistrationEvent {
  SubmitInvitedUserEvent({required this.fields, required this.role});
  final Map<String, dynamic> fields;

  /// The role assigned to the invited user: a staff role for "Add team member"
  /// or [UserRole.customer] for "Add borrower". The server re-validates it.
  final UserRole role;
}

class SubmitProviderRegistrationEvent extends RegistrationEvent {

  SubmitProviderRegistrationEvent({required this.fields});
  final Map<String, dynamic> fields;
}
