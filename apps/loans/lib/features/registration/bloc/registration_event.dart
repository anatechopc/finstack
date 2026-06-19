part of 'registration_bloc.dart';

@immutable
sealed class RegistrationEvent {}

class SubmitUserRegistrationEvent extends RegistrationEvent {

  SubmitUserRegistrationEvent({
    required this.fields,
    this.adminCreating = false,
  });
  final Map<String, dynamic> fields;

  /// True when an admin is creating this user from the users list (vs a person
  /// self-registering). When true the new account is created on a secondary
  /// Firebase app so it does not replace the admin's current session.
  final bool adminCreating;
}

class SubmitManagedUserRegistrationEvent extends RegistrationEvent {

  SubmitManagedUserRegistrationEvent({
    required this.fields,
  });
  final Map<String, dynamic> fields;
}

class SubmitProviderRegistrationEvent extends RegistrationEvent {

  SubmitProviderRegistrationEvent({required this.fields});
  final Map<String, dynamic> fields;
}
