import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/widgets/app_widgets.dart';

class AppTitleWidget extends StatelessWidget {
  const AppTitleWidget({
    super.key,
    this.includeSignUpButton = true,
    this.appNameFontSize = 96,
    this.tagLineFontSize = 24,
  });

  final bool includeSignUpButton;
  final double appNameFontSize;
  final double tagLineFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Constants.appName,
          style: GoogleFonts.urbanist(
            fontSize: appNameFontSize,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        Text(
          Constants.tagLine,
          style: GoogleFonts.urbanist(
            fontSize: tagLineFontSize,
          ),
        ),
        if (includeSignUpButton) ...[
          const Gap(42),
          AppWidgets.defaultOutlinedButton(
            padding: const EdgeInsets.symmetric(
              horizontal: 36,
              vertical: 16,
            ),
            onPressed: () {},
            child: Text(
              'Sign up now',
              style: GoogleFonts.urbanist(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
