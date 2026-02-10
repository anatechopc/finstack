import 'dart:math';

import 'package:loooans_helpers/loooans_helpers.dart';

/// extension function for email validation
extension StringExtensions on String {
  /// checks for valid email
  bool isEmailValid() {
    return RegExp(
      r"^((([a-z]|\d|[!#\$%&'*\+\-\/=\?\^_`{\|}~]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])+(\.([a-z]|\d|[!#\$%&'\*\+\-\/=\?\^_`{\|}~]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])+)*)|((\x22)((((\x20|\x09)*(\x0d\x0a))?(\x20|\x09)+)?(([\x01-\x08\x0b\x0c\x0e-\x1f\x7f]|\x21|[\x23-\x5b]|[\x5d-\x7e]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(\\([\x01-\x09\x0b\x0c\x0d-\x7f]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]))))*(((\x20|\x09)*(\x0d\x0a))?(\x20|\x09)+)?(\x22)))@((([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])*([a-z]|\d|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])))\.)+(([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])|(([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])([a-z]|\d|-|\.|_|~|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])*([a-z]|[\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])))$",
    ).hasMatch(this);
  }

  /// checks for password format validity
  bool isPasswordValidFormat() {
    return RegExp(
            r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',)
        .hasMatch(this);
  }

  /// gets the last values of string
  String last({int count = 5}) {
    if (length <= count) {
      return this;
    }

    return substring(length - count);
  }
}

String get LOOOANS_BASE_URL {
  var environment = '';

  if (const String.fromEnvironment('ENVIRONMENT') ==
      Environments.development.name) {
    environment = 'dev';
  } else if (const String.fromEnvironment('ENVIRONMENT') ==
      Environments.staging.name) {
    environment = 'stg';
  }

  return 'https://${environment.isNotEmpty ? '$environment.' : ''}loooans.com';
}

// const environment = String.fromEnvironment('ENVIRONMENT');

String get LOOOANS_BASE_API_URL {
  return '$LOOOANS_BASE_URL/api';
}

class StringHelper {
  static String generatePassword({
    bool isLetter = true,
    bool isNumber = true,
    bool isSpecial = true,
    int length = 20,
  }) {
    const letterLowerCase = 'abcdefghijklmnopqrstuvwxyz';
    const letterUpperCase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const number = '0123456789';
    const special = r'@#%^*>$@?/[]=+!?~';
    var chars = '';

    if (isLetter) chars += '$letterLowerCase$letterUpperCase';
    if (isNumber) chars += number;
    if (isSpecial) chars += special;

    return List.generate(length, (index) {
      final indexRandom = Random.secure().nextInt(chars.length);
      return chars[indexRandom];
    }).join();
  }

  static String generateId({
    bool isLetter = true,
    bool isNumber = true,
    int length = 20,
  }) {
    return generatePassword(
      isLetter: isLetter,
      isNumber: isNumber,
      isSpecial: false,
      length: length,
    );
  }
}
