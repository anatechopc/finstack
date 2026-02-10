part of 'registration_bloc.dart';

@immutable
sealed class RegistrationEvent {}

class SubmitUserRegistrationEvent extends RegistrationEvent {

  SubmitUserRegistrationEvent({
    required this.fields,
  });
  final Map<String, dynamic> fields;
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
