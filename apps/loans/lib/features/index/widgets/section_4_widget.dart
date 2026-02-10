import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class Section4Widget extends StatelessWidget {
  const Section4Widget({super.key});

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
            text: TextSpan(
              text: 'Loooans! at work ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 32,
                color: AppColors.green1,
              ),
              children: [
                TextSpan(
                  text: 'for users',
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ),
        ..._swap(
          _featureDescription(
            featureName: 'Marketplace',
            description:
                'We have a lot of loan providers ready to help your financial needs.',
            textColor: AppColors.green1,
            swap: swap,
          ),
          Image.asset(
            'images/marketplace.png'.assetSafe,
            height: 200,
          ),
        ),
        ..._swap(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 529),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // commented out for now, until we can do a proper release
                // SvgPicture.asset(
                //   'svg/sec_logo.svg'.assetSafe,
                //   width: 265,
                // ),
                SvgPicture.asset(
                  'svg/user_dark.svg'.assetSafe,
                  width: 128,
                ),
              ],
            ),
          ),
          _featureDescription(
              featureName: 'Verified loan providers',
              description:
                  'We are doing an extensive verification process to every loan providers in the marketplace to ensure that they can provide solution to the user’s financial needs.',
              textColor: AppColors.green1,
              alignment: CrossAxisAlignment.end,
              swap: swap,),
          swap: swap,
        ),
        ..._swap(
          _featureDescription(
            featureName: 'Compare quotation',
            description:
            'To help users decide what loan to take, we are enabling quotation comparison in their fingertips, leveraging their financial capabilities.',
            textColor: AppColors.green1,
            swap: swap,
          ),
          Image.asset(
            'images/quotation.png'.assetSafe,
            width: 529,
          ),
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
          Text(
            featureName,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 24,
              color: textColor,
            ),
          ),
          const Gap(16),
          ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: swap ? double.infinity : diffWidth),
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
