import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/features/index/widgets/app_footer_widget.dart';
import 'package:loooans/features/index/widgets/app_title_widget.dart';
import 'package:loooans/features/index/widgets/apply_loan_widget.dart';
import 'package:loooans/features/index/widgets/section_4_widget.dart';
import 'package:loooans/features/index/widgets/section_5_widget.dart';
import 'package:loooans/features/products/screen/loan_offers_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});

  static const _loanOffersKey = ValueKey('LoanOffersWidgetKey');

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;
    var padding = const EdgeInsets.all(56);

    if (getScreenSize(context: context) == ScreenSize.compact) {
      padding = const EdgeInsets.all(defaultPaddingSize);
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppWidgets.defaultSliverAppBar(context),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                var boxColor = Colors.transparent;

                if (index.isOdd) {
                  boxColor = AppColors.black;
                }

                return ColoredBox(
                  color: boxColor,
                  child: AppWidgets.rootConstraints(
                      child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: padding,
                      child: switch (index) {
                        0 => _section1(isCompact),
                        1 => const SizedBox(
                            height: 370,
                            child: LoanOffersWidget(
                              key: _loanOffersKey,
                              buildFromIndex: true,
                            ),
                          ),
                        2 => _section3(),
                        3 => const Section4Widget(),
                        4 => const Section5Widget(),
                        5 => _section6(),
                        _ => const AppFooterWdiget(),
                      },
                    ),
                  ),),
                );
              },
              childCount: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section1(bool isCompact) {
    return Wrap(
      alignment: isCompact ? WrapAlignment.center : WrapAlignment.spaceAround,
      runAlignment: WrapAlignment.center,
      runSpacing: 32,
      children: const [
        AppTitleWidget(),
        ApplyLoanWidget(),
      ],
    );
  }

  Widget _section3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'At Loooans!',
          style: GoogleFonts.urbanist(
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(24),
        const Text(
            '''
It is our mission to empower individuals and micro enterprises to leverage their financial capabilities to have a happy and stress free financial life.

We are a group of people that believes financial freedom is for everyone. It is hard do this alone. We need the help of others to attain financial freedom. Starting a business is never easy, especially if you’re income is “just right” for your daily necessities. We understand the need forl help in investing your business.

That’s why here at Loooans! we created a platform to enable individuals and micro business entrepreneurs leverage their current financial capabilities. 
        '''),
      ],
    );
  }

  Widget _section6() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Be part of our movement into a future where every Juan will have a happy and stress-free financial Life',
          style: GoogleFonts.urbanist(
            fontSize: 16,
            color: AppColors.white,
          ),
        ),
        const Gap(16),
        AppWidgets.defaultOutlinedButton(
          padding: const EdgeInsets.symmetric(
            horizontal: 36,
            vertical: 16,
          ),
          foregroundColor: AppColors.green1,
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
    );
  }
}
