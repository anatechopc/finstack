/// An exception thrown when there's something wrong
/// happening in the authentication code.
class AuthenticationException implements Exception {
  ///
  AuthenticationException({required this.message});

  /// error message
  final String message;
}

/// thrown when an error in session occurs
class SessionException implements Exception {
  ///
  SessionException({
    required this.deviceName,
    required this.lastLogin,
    required this. message,
  });

  final String deviceName;
  final DateTime lastLogin;
  final String message;
}
