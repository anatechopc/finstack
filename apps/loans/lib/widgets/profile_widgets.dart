import 'package:cached_network_image/cached_network_image.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/users/widget/profile_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:user_repository/user_repository.dart';

class ProfileWidgets {
  static Widget profileIcon(
    BuildContext context, {
    bool avatarOnly = false,
    double? avatarDimension,
    User? user,
    Company? company,
    bool removeExtraPadding = false,
    bool triggerIconClick = false,
  }) {
    CachedNetworkImageProvider? provider;
    var initials = '';

    if (user != null) {
      if (user.profilePhotoUrl != null) {
        provider = CachedNetworkImageProvider(user.profilePhotoUrl!.url);
      } else {
        initials = user.initials;
      }
    } else if (company != null) {
      if (company.companyProfilePhotoUrl != null) {
        provider =
            CachedNetworkImageProvider(company.companyProfilePhotoUrl!.url);
      } else {
        initials = company.name.initials(limit: 2);
      }
    }

    final avatar = InkWell(
      borderRadius: BorderRadius.circular(32),
      splashColor: AppColors.lightBlack,
      onTap: triggerIconClick
          ? () {
              if (AuthenticationService.instance.hasCompany) {
                // show company profile dialog
                var maxHeight = MediaQuery.sizeOf(context).height *
                    0.52; // TODO(deibeeed): Once AutoCollect feature is activated, set the maxHeight to 67%

                if (maxHeight < 400) {
                  maxHeight = 408;
                }

                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      backgroundColor: AppColors.green1,
                      content: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                          maxHeight: maxHeight,
                        ),
                        child: BlocListener<AuthenticationBloc,
                            AuthenticationState>(
                          listener: (context, state) {
                            if (state.status ==
                                AuthenticationStateStatus.logout) {
                              Navigator.of(context, rootNavigator: true).pop();
                            }
                          },
                          child: ProfileWidget(
                            buildForCompany:
                                AuthenticationService.instance.hasCompany,
                            foregroundColor: AppColors.black,
                            showUpdateButtonBelow: true,
                          ),
                        ),
                      ),
                    );
                  },
                );
              } else {
                GoRouter.of(context).goSafe('${Paths.index}?sec=karma');
              }
            }
          : null,
      child: Container(
        width: (avatarDimension ?? 48) + (removeExtraPadding ? 0 : 8),
        height: (avatarDimension ?? 48) + (removeExtraPadding ? 0 : 8),
        padding: !removeExtraPadding ? const EdgeInsets.all(2) : null,
        child: CircleAvatar(
          backgroundColor: AppColors.white,
          backgroundImage: provider,
          child: provider == null ? Text(initials) : null,
        ),
      ),
    );

    if (avatarOnly) {
      return avatar;
    }

    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: 8,
              left: 16,
              right: 50,
            ),
            margin: const EdgeInsets.only(
              right: 8,
              top: 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.white,
            ),
            child: Text(
              'Welcome, ${user?.completeNameEasternOrder}',
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: avatar,
          ),
        ],
      ),
    );
  }
}
