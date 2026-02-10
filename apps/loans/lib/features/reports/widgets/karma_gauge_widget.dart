import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class KarmaGaugeWidget extends StatelessWidget {
  const KarmaGaugeWidget({
    super.key,
    this.expand = false,
    this.showCredit = false,
  });

  final bool expand;
  final bool showCredit;

  @override
  Widget build(BuildContext context) {
    var gaugeName = 'karma_gauge_80';

    if (showCredit) {
      gaugeName = 'karma_gauge_80_green';
    }
    Widget gauge = SvgPicture.asset(
      'svg/$gaugeName.svg'.assetSafe,
      height: 250,
    );

    if (expand) {
      gauge = Expanded(
        child: gauge,
      );
    }

    if (showCredit) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your credit karma',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () {
                    GoRouter.of(context).go(Paths.index);
                  },
                  child: SvgPicture.asset('svg/icon_arrow_down.svg'.assetSafe),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                gauge,
                const Gap(16),
                _creditKarmaScoreWidget(),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _creditKarmaContainer(context),
          gauge,
        ],
      ),
    );
  }

  Widget _creditKarmaContainer(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _creditKarmaWidget(context),
        const Gap(48),
        _creditKarmaScoreWidget(),
      ],
    );
  }

  Widget _creditKarmaWidget(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Credit\nKarma',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            height: 1,
            color: showCredit ? AppColors.white : AppColors.black,
          ),
        ),
        const Gap(8),
        InkWell(
          onTap: () {
            GoRouter.of(context).goSafe('${Paths.index}?sec=karma');
          },
          child: SvgPicture.asset(
            'svg/icon_arrow_up.svg'.assetSafe,
            colorFilter: const ColorFilter.mode(
              AppColors.black,
              BlendMode.srcIn,
            ),
          ),
        ),
      ],
    );
  }

  Widget _creditKarmaScoreWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                  text: '+20',
                  style: TextStyle(
                    fontSize: 12,
                    color: showCredit ? AppColors.white : AppColors.black,
                  ),),
              TextSpan(
                text: ' pts',
                style: TextStyle(
                  fontSize: 12,
                  color: showCredit
                      ? AppColors.white.withOpacity(0.5)
                      : AppColors.black.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '80',
                style: TextStyle(
                  fontSize: 64,
                  color: showCredit ? AppColors.white : AppColors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: '.06%',
                style: TextStyle(
                  fontSize: 12,
                  color: showCredit
                      ? AppColors.white.withOpacity(0.5)
                      : AppColors.black.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
        Text(
          'very good payor',
          style: TextStyle(
            color: showCredit ? AppColors.white : AppColors.black,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
