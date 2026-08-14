import 'package:flutter_test/flutter_test.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  group('RequestOtpException.userMessage', () {
    test('returns the server body verbatim (trimmed) for a 400', () {
      final e = RequestOtpException(
        400,
        'No address is on file for this account, so the country of the '
        'mobile number cannot be determined. Please add an address and try '
        'again.\n',
      );
      expect(
        e.userMessage,
        'No address is on file for this account, so the country of the '
        'mobile number cannot be determined. Please add an address and try '
        'again.',
      );
    });

    test('falls back to a generic message for a 500', () {
      expect(
        RequestOtpException(500, 'internal error details').userMessage,
        'Cannot request OTP',
      );
    });

    test('falls back to a generic message for an empty 400 body', () {
      expect(RequestOtpException(400, '   ').userMessage, 'Cannot request OTP');
    });

    test('toString carries status and body for logs', () {
      expect(
        RequestOtpException(400, 'nope').toString(),
        'RequestOtpException(400): nope',
      );
    });
  });

  group('OtpApiException status window', () {
    // ValidateRequestV2 emits 401 with raw Go/Firebase SDK text — including
    // `firebase admin initialization error: google: could not find default
    // credentials...` — which must never be shown to a user. Only 400 is
    // reserved by the backend for human-readable validation failures.
    test('never echoes a 401 body, however descriptive it looks', () {
      const sdkNoise = 'firebase admin initialization error: google: could '
          'not find default credentials. See the Google Cloud authentication '
          'docs for more information.';
      final e = RequestOtpException(401, sdkNoise);

      expect(e.userMessage, isNot(contains('firebase')));
      expect(e.userMessage, isNot(contains('credentials')));
      expect(e.userMessage, 'Your session has expired. Please sign in again.');
    });

    test('maps a bare Unauthorized body to a sign-in prompt', () {
      expect(
        RequestOtpException(401, 'Unauthorized\n').userMessage,
        'Your session has expired. Please sign in again.',
      );
    });

    for (final status in [402, 403, 404, 409, 418, 429, 499]) {
      test('does not echo the body for a $status', () {
        expect(
          RequestOtpException(status, 'internal detail').userMessage,
          'Cannot request OTP',
        );
      });
    }
  });

  group('userMessageOr', () {
    test('prefers the caller fallback over the type default', () {
      expect(
        RequestOtpException(500, '').userMessageOr('Failed to send OTP'),
        'Failed to send OTP',
      );
    });

    test('still returns the server 400 body when there is one', () {
      expect(
        RequestOtpException(400, 'Fix your address.')
            .userMessageOr('Failed to send OTP'),
        'Fix your address.',
      );
    });

    test('caller fallback does not override the 401 sign-in prompt', () {
      expect(
        RequestOtpException(401, 'Unauthorized')
            .userMessageOr('Failed to send OTP'),
        'Your session has expired. Please sign in again.',
      );
    });
  });

  group('VerifyOtpException', () {
    test('surfaces the actionable 400 reason instead of raw exception text',
        () {
      expect(VerifyOtpException(400, 'OTP expired').userMessage, 'OTP expired');
      expect(
        VerifyOtpException(400, 'OTP not found').userMessage,
        'OTP not found',
      );
    });

    test('falls back to its own generic message', () {
      expect(
        VerifyOtpException(500, 'boom').userMessage,
        'Cannot verify OTP',
      );
    });

    test('toString carries status and body for logs', () {
      expect(
        VerifyOtpException(400, 'nope').toString(),
        'VerifyOtpException(400): nope',
      );
    });
  });
}
