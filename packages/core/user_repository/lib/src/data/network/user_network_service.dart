import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:loooans_helpers/loooans_helpers.dart';
import 'package:user_repository/src/model/request_otp_response.dart';

/// user network services
class UserNetworkService {
  /// Creates a user server-side (Firebase Auth account + Firestore doc) via the
  /// addUser Cloud Function. [user] and [address] are the client-serialized
  /// entity JSON maps. Returns the server-minted uid and whether the invite
  /// email was sent.
  Future<({String uid, bool inviteSent})> createUser({
    required String role,
    required Map<String, dynamic> user,
    required String idToken,
    Map<String, dynamic>? address,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/add'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'role': role,
        'user': user,
        if (address != null) 'address': address,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = data['data'] as Map<String, dynamic>;
      return (
        uid: payload['uid'] as String,
        inviteSent: payload['inviteSent'] as bool? ?? false,
      );
    }

    throw HttpException(
      'Create user failed: ${response.statusCode} ${response.body}',
    );
  }

  /// Requests a set-password / reset link email for [email]. Backs both the
  /// admin "Resend invite" action and the login "Forgot password" link. The
  /// endpoint always succeeds and never reveals whether the account exists.
  Future<void> sendPasswordSetupLink({required String email}) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/password/setup-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException(
        'Send password setup link failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<RequestOtpResponse> requestOtp({
    required String idToken,
    String purpose = 'mobile_number',
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/request/otp'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'purpose': purpose,
      }),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException('Request OTP error: ${response.statusCode} ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return RequestOtpResponse.fromJson(body);
  }

  Future<RequestOtpResponse> requestOtpForUser({
    required String idToken,
    required String targetUserId,
    String reason = 'payment',
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/request/otp'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'purpose': 'mobile_number',
        'target_user_id': targetUserId,
        'reason': reason,
      }),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException(
        'Request OTP for user error: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return RequestOtpResponse.fromJson(body);
  }

  Future<bool> verifyOtp({
    required String idToken,
    required String token,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/verify/otp'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'otp': otp,
      }),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException(
        'Verify OTP error: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['verified'] as bool;
  }

}
