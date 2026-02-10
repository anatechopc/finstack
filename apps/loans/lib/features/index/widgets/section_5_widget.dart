import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class Section5Widget extends StatelessWidget {
  const Section5Widget({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceWidth = MediaQuery.sizeOf(context).width;
    final swap = deviceWidth < 883;

    return Wrap(
      // crossAxisAlignment: CrossAxisAlignment.start,
      alignment: swap ? WrapAlignment.center : WrapAlignment.spaceBetween,
      runAlignment: WrapAlignment.center,
      runSpacing: 32,
      children: [
        SizedBox(
          width: double.infinity,
          child: RichText(
            textAlign: TextAlign.end,
            text: TextSpan(
              text: 'Loooans! at work ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 32,
              ),
              children: [
                TextSpan(
                  text: 'for providers',
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ),
        ..._swap(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 529),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SvgPicture.asset(
                  'svg/veriff_logo2.svg'.assetSafe,
                  width: 265,
                ),
                SvgPicture.asset(
                  'svg/user_light.svg'.assetSafe,
                  width: 128,
                ),
              ],
            ),
          ),
          _featureDescription(
            featureName: 'Verified users',
            description:
                'To completely verify user’s validity, we are doing an extensive verification process thru automated verification (coming soon) and manual verification to ensure that the user’s identity is really true. This will increase provider’s confidence to lend money to applicants.',
            alignment: CrossAxisAlignment.end,
            swap: swap,
          ),
          swap: swap,
        ),
        ..._swap(
          _featureDescription(
            featureName: 'Loan management & analytics',
            description:
                'Approve or deny loan applications and track user amortization payments. Analyze your loan business performance with our set of business intelligence tools to help you navigate thru your business enabling your business growth.',
            swap: swap,
          ),
          Image.asset(
            'images/analytics.png'.assetSafe,
            height: 200,
          ),
        ),
        ..._swap(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 529),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SvgPicture.asset(
                  'svg/ads.svg'.assetSafe,
                  width: 148,
                ),
                SvgPicture.asset(
                  'svg/cash.svg'.assetSafe,
                  width: 148,
                ),
              ],
            ),
          ),
          _featureDescription(
            featureName: '',
            featureNameWidget: RichText(
              textAlign: TextAlign.end,
              text: TextSpan(
                text: 'Feature ',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 24,
                ),
                children: [
                  TextSpan(
                    text: '(marketplace)',
                    style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            description:
                'Operate your loan business wisely with our set of value added tools such as AdsPro and AutoCollect. These features will be coming to your loan businesses soon.(These features are readily made available few taps away.)',
            alignment: CrossAxisAlignment.end,
            swap: swap,
          ),
          swap: swap,
        ),
      ],
    );
  }

  Widget _featureDescription({
    required String featureName,
    required String description,
    Color textColor = AppColors.black,
    CrossAxisAlignment alignment = CrossAxisAlignment.start,
    bool swap = false,
    Widget? featureNameWidget,
  }) {
    var textAlign = TextAlign.start;

    if (alignment == CrossAxisAlignment.end) {
      textAlign = TextAlign.end;
    }

    return LayoutBuilder(builder: (context, constraints) {
      // debugPrint('feature: ${constraints.maxWidth}');
      final diffWidth = constraints.maxWidth - 550;

      // debugPrint('diffWidth: $diffWidth');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: swap ? double.infinity : diffWidth,
            ),
            child: featureNameWidget ?? Text(
              featureName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 24,
                color: textColor,
              ),
            ),
          ),
          const Gap(16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: swap ? double.infinity : diffWidth,
            ),
            child: Text(
              description,
              style: TextStyle(
                color: textColor,
              ),
              textAlign: textAlign,
            ),
          ),
        ],
      );
    },);
  }

  List<Widget> _swap(Widget w1, Widget w2, {bool swap = false}) {
    if (swap) {
      return [
        w2,
        w1,
      ];
    }
    return [
      w1,
      w2,
    ];
  }
}
