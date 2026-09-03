import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/user_repository.dart';

extension DefaultDateformat on DateTime {
  String toDefaultDateFormat() {
    return Constants.defaultDateFormat.format(toLocal());
  }

  String toDefaultDateFormatExtended() {
    // change to toIso8601String() if we're going to have international support
    return Constants.defaultDateFormatExtended.format(toLocal());
  }

  String toDefaultDateFormatWithDay() {
    return Constants.defaultDateFormatWithDay.format(toLocal());
  }

  String toDefaultDateFormatWithDayExtended() {
    return Constants.defaultDateFormatWithDayExtended.format(toLocal());
  }

  String toDefaultDateMonthFormat() {
    return Constants.defaultDateMonthFormat.format(toLocal());
  }

  String toDefaultDateCompleteMonthFormat() {
    return Constants.defaultDateCompleteMonthFormat.format(toLocal());
  }

  String toWesternDateFormatWithDay() {
    return Constants.westernDateFormatWithDay.format(toLocal());
  }

  String toWesternDateFormat() {
    return Constants.westernDateFormat.format(toLocal());
  }

  String toWesternDateYearMonthFormat() {
    return Constants.westernDateYearMonthFormat.format(toLocal());
  }

  String toDefaultDateYearMonthFormat() {
    return Constants.defaultDateYearMonthFormat.format(toLocal());
  }
}

extension SimplifiedFormBuilderStateFields on FormBuilderState {
  Map<String, dynamic> simplifiedFields() {
    return fields.map((key, value) => MapEntry(key, value.value));
  }
}

extension SafeNavigation on GoRouter {
  // inspired by https://github.com/flutter/flutter/issues/129833#issuecomment-1725216727
  String get location {
    final lastMatch = routerDelegate.currentConfiguration.last;
    final matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : routerDelegate.currentConfiguration;
    final location = matchList.uri.toString();
    return location;
  }

  FutureOr<dynamic> goSafe(String location, {Map<String, dynamic>? extra}) {
    if (isMobilePlatform) {
      return push(location, extra: extra);
    } else {
      go(location, extra: extra);
    }
  }

  void popSafe(String location) {
    if (isMobilePlatform) {
      pop();
    } else {
      go(location);
    }
  }
}

extension FormattingExtension on num {
  String toCurrency({
    bool isDeduction = false,
    bool removeNegative = true,
    bool optionalDecimal = false,
    bool allowEmpty = false,
  }) {
    if (allowEmpty) {
      if (this <= 0) {
        return '';
      }
    }

    var formatted =
        Constants.defaultCurrencyFormat.format(num.parse(toStringAsFixed(2)));

    if (optionalDecimal) {
      formatted = Constants.defaultCurrencyFormatOptionalDecimal.format(this);
    }

    final diff = (formatted.length - 1) - formatted.indexOf('.');

    if (removeNegative && formatted.startsWith('-')) {
      formatted = formatted.substring(1);
    }

    if (isDeduction) {
      return formatted.replaceFirst(' ', ' -');
    }

    if (diff == 1) {
      return '${formatted}0';
    }

    return formatted;
  }

  String toDefaultFormat() {
    final formatted = Constants.defaultNumberFormat.format(this);

    return formatted;
  }
}

extension LoanCalulationExtensions on num {
  /// P = (Pv*R) / [1 - (1 + R)^(-n)]
  ///
  /// Here’s a breakdown of each of the variables:
  ///
  ///     P = Monthly Payment
  ///     Pv = Present Value (starting value of the loan)
  ///     APR = Annual Percentage Rate
  ///     R = Periodic Interest Rate = APR/number of interest periods per year
  ///     n = Total number of interest periods (interest periods per year * number of years)
  ///
  /// source: https://superuser.com/questions/871404/what-would-be-the-the-mathematical-equivalent-of-this-excel-formula-pmt
  ///
  /// NOTE:
  ///   * use this function only to calculate monthly payments of the outstanding balance.
  ///   * monthlyInterest rates should be already in decimal format.
  double calculateMonthlyPayment({
    // required double outstandingBalance,
    required double monthlyInterestRate,
    required int monthsToPay,
    required String term,
  }) {
    var interestRate = monthlyInterestRate;
    var numPayments = monthsToPay;

    if (term == '15d') {
      interestRate /= 2;
      numPayments *= 2;
    }

    final p =
        (this * interestRate) / (1 - pow(1 + interestRate, -1 * numPayments));

    return p;
  }
}

extension UserRoleExtensions on User {
  bool isAdmin() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.admin;
  }

  bool isAppAdmin() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.appAdmin;
  }

  bool isCustomer() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.customer;
  }

  bool isLoanOfficer() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.loanOfficer;
  }

  bool isReviewModerator() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.reviewModerator;
  }

  bool isTeller() {
    if (isPlaceholder) {
      return false;
    }

    return userRole == UserRole.teller;
  }
}

extension StringExtensions on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// get initials of a string.
  /// getting initials will be based on word spacing;
  /// [limit] will limit how many initials will be generated.
  /// 0 means all initials will be rendered.
  String initials({int limit = 0}) {
    final splits = split(' ');
    final firstLetters = splits.map((word) => word[0].toUpperCase()).toList();

    if (limit > 0) {
      return firstLetters.getRange(0, limit).join();
    }

    return firstLetters.join();
  }

  String get assetSafe {
    if (!kIsWeb) {
      return 'assets/$this';
    }

    return 'assets/$this';
  }

  List<int> toIntList() {
    try {
      return replaceAll(' ', '').split(',').map(int.parse).toList();
    } catch (err) {
      rethrow;
    }
  }

  /// for string date NUMBERS to generate ordinal indicator
  String generateOrdinalIndicators() {
    String generateOrdinalIndicator(int number) {
      const defaultOrdinalIndicator = '\u1d57\u02b0';
      return switch (number) {
        1 => '\u02e2\u1d57',
        2 => '\u207f\u1d48',
        3 => '\u02b3\u1d48',
        _ => defaultOrdinalIndicator
      };
    }

    try {
      debugPrint('generateOrdinalIndicators: $this');
      if (contains(',')) {
        final splitTerm = split(',');
        final tempFirstSalaryDay = int.parse(splitTerm[0]);
        final tempSecondSalaryDay = int.parse(splitTerm[1]);
        final firstSalaryDay = min(tempFirstSalaryDay, tempSecondSalaryDay);
        final secondSalaryDay = max(tempFirstSalaryDay, tempSecondSalaryDay);

        return '$firstSalaryDay${generateOrdinalIndicator(
          firstSalaryDay,
        )} and $secondSalaryDay${generateOrdinalIndicator(
          secondSalaryDay,
        )} of the month';
      }

      // test to parse
      final number = int.parse(this);

      return '$number${generateOrdinalIndicator(number)} day';
    } catch (err) {
      debugPrint('generateOrdinalIndicators:err: $err');
      return this;
    }
  }

  // for terms only
  String completeTerm() {
    try {
      final numTerm = int.parse(substring(0, length - 1));
      if (contains('d')) {
        if (numTerm > 1) {
          return '$numTerm days';
        }

        return 'day';
      }

      if (numTerm > 1) {
        return '$numTerm months';
      }

      return 'month';
    } catch (err) {
      return this;
    }
  }
}

extension DurationExtension on Duration {
  String formatted() {
    final negativeSign = isNegative ? '-' : '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(inMinutes.remainder(60).abs());
    final twoDigitSeconds = twoDigits(inSeconds.remainder(60).abs());
    return '$negativeSign${twoDigits(
      inHours,
    )}:$twoDigitMinutes:$twoDigitSeconds';
  }

  String formattedMinutes() {
    final negativeSign = isNegative ? '-' : '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(inMinutes.remainder(60).abs());
    final twoDigitSeconds = twoDigits(inSeconds.remainder(60).abs());
    return '$negativeSign$twoDigitMinutes:$twoDigitSeconds';
  }
}

extension PenaltyLabels on Penalty {
  /// e.g. "₱100.00 / day" or "2.0% / month".
  String get amountLabel {
    final amountStr = isPercentage ? '$amount%' : amount.toCurrency();
    return '$amountStr ${frequency.suffix}';
  }

  /// e.g. "Late fee · ₱100.00 / day".
  String get chipLabel => '$name · $amountLabel';
}
