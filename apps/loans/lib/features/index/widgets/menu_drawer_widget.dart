import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class MenuDrawerWidget extends StatelessWidget {
  const MenuDrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.toString();
    return Material(
      color: AppColors.lightBlack,
      textStyle: const TextStyle(color: AppColors.white),
      child: ListView(
        children: [
          _profileWidget(context),
          ...Constants.allMenu(context: context).where((menu) => menu.show).map((menu) {
            return ListTile(
              selected: currentLocation == menu.redirectPath,
              selectedTileColor: AppColors.green1.withOpacity(0.4),
              contentPadding: const EdgeInsets.all(16),
              onTap: () {
                GoRouter.of(context).go(menu.redirectPath);
              },
              leading: menu.logoPath == null
                  ? null
                  : ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        AppColors.white,
                        BlendMode.srcIn,
                      ),
                      child: SvgPicture.asset(
                        menu.logoPath!.assetSafe,
                        width: 24,
                      ),
                    ),
              title: Text(
                menu.title,
                style: const TextStyle(color: AppColors.white),
              ),
              hoverColor: AppColors.white.withOpacity(0.1),
            );
          }),
        ],
      ),
    );
  }

  Widget _profileWidget(BuildContext context) {
    final authInstance = AuthenticationService.instance;
    final user = authInstance.user;

    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppWidgets.profileIcon(
            context,
            avatarOnly: true,
            avatarDimension: 56,
            user: user,
            company: authInstance.hasCompany ? authInstance.company : null,
          ),
          const Gap(16),
          Text(
            user.completeNameEasternOrder,
            style: const TextStyle(
              fontSize: 16,
            ),
          ),
          const Gap(4),
          Text(
            user.userRole.label,
            style: TextStyle(
              color: AppColors.white.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}
