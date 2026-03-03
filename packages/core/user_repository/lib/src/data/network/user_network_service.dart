import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:loooans_helpers/loooans_helpers.dart';
import 'package:user_repository/src/model/request_otp_response.dart';

/// user network services
class UserNetworkService {
  /// Calls the addUser api service to add
  /// user to firebase auth.
  Future<String> createUserAccess({
    required String displayName,
    required String email,
    required String password,
    required String idToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$LOOOANS_BASE_API_URL/users/add'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'displayName': displayName,
          'email': email,
          'password': password,
        }),
      );

      debugPrint('response status code: ${response.statusCode}');
      debugPrint('response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        return data['data']['uid'] as String;
      }

      throw HttpException(
        'Something went wrong while creating user access: ${response.reasonPhrase}',
      );
    } catch (err) {
      rethrow;
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

  Future<bool> verifyPaymentOtp({
    required String idToken,
    required String token,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/verify/payment-otp'),
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
        'Verify payment OTP error: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['verified'] as bool;
  }

  Future<void> verifyUserEmail({
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/verify/email'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException('Verify user email error: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> updateUserEmail({
    required String idToken,
    required String emailAddress,
    bool isVerified = false,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/update/email'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email_address': emailAddress,
        'is_verified': isVerified,
      }),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException('Verify user email error: ${response.statusCode} ${response.body}');
    }
  }
}
