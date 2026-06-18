import 'package:flutter/material.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/screen_helpers.dart';

class DisplayWidgets {
  /// it is expected that the amount is in currency form.
  static RichText defaultAmountWidget(
    String amount, {
    int fontSize = 20,
    int subFontSize = 12,
    Color fontColor = AppColors.black,
    bool fontThick = true,
  }) {
    final parsedMoney = amount.substring(1).split('.');

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: Constants.currencySymbol,
            style: TextStyle(
              fontSize: subFontSize.toDouble(),
              fontWeight: FontWeight.w300,
              color: fontColor.withValues(alpha: 0.6),
            ),
          ),
          TextSpan(
            text: ' ${parsedMoney.first}',
            style: TextStyle(
              fontSize: fontSize.toDouble(),
              fontWeight: fontThick ? FontWeight.w600 : null,
              color: fontColor,
            ),
          ),
          TextSpan(
            text: '.${parsedMoney.last}',
            style: TextStyle(
              fontSize: subFontSize.toDouble(),
              fontWeight: FontWeight.w300,
              color: fontColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  static RatingBar defaultRatingBar({
    required ValueChanged<double> onRatingUpdate,
    double initialRating = 5,
    double itemSize = 32,
  }) {
    return RatingBar(
      initialRating: initialRating,
      minRating: 1,
      maxRating: 5,
      itemSize: itemSize,
      ratingWidget: RatingWidget(
        full: const Icon(Icons.star_rounded),
        half: Container(),
        empty: const Icon(Icons.star_border_rounded),
      ),
      onRatingUpdate: onRatingUpdate,
    );
  }

  /// Read-only star rating that fills CONTINUOUSLY by [rating] — a 4.5 shows a
  /// half-filled star, 4.25 a quarter, etc. Use for displaying an average
  /// (unlike [defaultRatingBar], which is for input and renders whole stars).
  static RatingBarIndicator ratingIndicator({
    required double rating,
    double itemSize = 24,
  }) {
    return RatingBarIndicator(
      rating: rating,
      itemSize: itemSize,
      unratedColor: AppColors.black.withValues(alpha: 0.25),
      itemBuilder: (context, _) => const Icon(
        Icons.star_rounded,
        color: AppColors.black,
      ),
    );
  }
}
