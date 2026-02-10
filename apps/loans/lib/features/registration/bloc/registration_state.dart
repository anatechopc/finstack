part of 'registration_bloc.dart';

@immutable
sealed class RegistrationState {}

final class RegisterInitial extends RegistrationState {}

final class RegistrationLoadingState extends RegistrationState {

  RegistrationLoadingState({ this.isLoading = false});
  final bool isLoading;
}

final class RegistrationErrorState extends RegistrationState {

  RegistrationErrorState({ required this.message });
  final String message;
}

final class RegistrationSuccessState extends RegistrationState {

  RegistrationSuccessState({ required this.message});
  final String message;
}
