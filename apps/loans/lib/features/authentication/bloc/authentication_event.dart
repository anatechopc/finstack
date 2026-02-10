part of 'authentication_bloc.dart';

@immutable
sealed class AuthenticationEvent {}

class LoginEvent extends AuthenticationEvent {

  LoginEvent({
    required this.email,
    required this.password,
  });
  final String email;
  final String password;
}

class RequestOtpEvent extends AuthenticationEvent {

}

class VerifyOtpEvent extends AuthenticationEvent {

  VerifyOtpEvent({required this.otp});
  final String otp;
}

class SignOutEvent extends AuthenticationEvent {

  SignOutEvent({ this.silent = false,});
  final bool silent;
}
