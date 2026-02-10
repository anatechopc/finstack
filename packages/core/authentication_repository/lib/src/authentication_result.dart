import 'package:authentication_repository/authentication_repository.dart';

class AuthenticationResult {
  AuthenticationResult({
    required this.status,
    this.data,
  });

  AuthenticationStatus status;
  String? data;
}