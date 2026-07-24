import 'package:flutter_test/flutter_test.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  group('RequestOtpException.userMessage', () {
    test('returns the server body verbatim (trimmed) for a 400', () {
      final e = RequestOtpException(
        400,
        "Cannot determine the country for the user's mobile number. "
        "Please complete the user's address record.\n",
      );
      expect(
        e.userMessage,
        "Cannot determine the country for the user's mobile number. "
        "Please complete the user's address record.",
      );
    });

    test('falls back to a generic message for a 500', () {
      expect(
        RequestOtpException(500, 'internal error details').userMessage,
        'Cannot request OTP',
      );
    });

    test('falls back to a generic message for an empty 4xx body', () {
      expect(RequestOtpException(400, '   ').userMessage, 'Cannot request OTP');
    });

    test('toString carries status and body for logs', () {
      expect(
        RequestOtpException(400, 'nope').toString(),
        'RequestOtpException(400): nope',
      );
    });
  });
}
