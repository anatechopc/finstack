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
  RequestOtpEvent({this.purpose = 'mobile_number'});

  /// Which channel to request the OTP on. Currently 'mobile_number' (default)
  /// for SMS or 'email' for email. The backend's request-OTP handler uses
  /// this to decide whether to write an SMS-pending entry in RTDB (for the
  /// Android gateway to pick up) or send an email via Microsoft Graph.
  final String purpose;
}

class VerifyOtpEvent extends AuthenticationEvent {

  VerifyOtpEvent({required this.otp});
  final String otp;
}

class SignOutEvent extends AuthenticationEvent {

  SignOutEvent({ this.silent = false,});
  final bool silent;
}

class ForgotPasswordEvent extends AuthenticationEvent {

  ForgotPasswordEvent({required this.email});
  final String email;
}
