import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class LoanApplicationTitle extends StatelessWidget {
  const LoanApplicationTitle({
    required this.isFullScreen,
    super.key,
  });

  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    final isMinMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (isFullScreen) ...[
          const Text(
            'Loan application',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 24,
            ),
          ),
          const Gap(16),
        ],
        if (isFullScreen && isMinMedium)
          InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () {
              // TODO: replace with real id
              GoRouter.of(context)
                  .goSafe('${Paths.index}?sec=offers&id=123abc');
            },
            child: SvgPicture.asset(
              'svg/close.svg'.assetSafe,
              colorFilter: const ColorFilter.mode(
                AppColors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
      ],
    );
  }
}
