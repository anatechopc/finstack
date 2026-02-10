import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class UpdateProfilePortraitHeader extends StatelessWidget {
  const UpdateProfilePortraitHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Personal details',
            style: TextStyle(
              color: AppColors.black,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () {
              GoRouter.of(context).goSafe('${Paths.index}?sec=karma');
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
      ),
    );
  }
}
