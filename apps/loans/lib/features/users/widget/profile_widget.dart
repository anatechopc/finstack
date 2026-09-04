import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/companies/bloc/company_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/screens/update_profile_screen.dart';
import 'package:loooans/features/users/widget/default_penalties_section.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/settings_widget.dart';
import 'package:user_repository/user_repository.dart';

class ProfileWidget extends StatelessWidget {
  const ProfileWidget({
    super.key,
    this.buildForCompany = false,
    this.foregroundColor = AppColors.white,
    this.showUpdateButtonBelow = false,
  });

  final bool buildForCompany;
  final Color foregroundColor;
  final bool showUpdateButtonBelow;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TODO(deibeeed): Make row a child of expanded if autocollect is enabled AND double check if expanded affects customer roles
        if (AuthenticationService.instance.user.isCustomer())
          _profile()
        else
          Expanded(
            child: _profile(),
          ),
        // TODO(deibeeed): this is for autocollect feature. Uncomment this when unionbank is setup from user and company.
        //  See https://github.com/anatechopc/loooans/issues/58
        // if (buildForCompany) ...[
        //   Gap(24),
        //   Expanded(
        //     child: Row(
        //       crossAxisAlignment: CrossAxisAlignment.start,
        //       children: [
        //         Expanded(child: _autoCollect()),
        //         Expanded(child: Container())
        //       ],
        //     ),
        //   ),
        // ],
        const Gap(24),
        if (!AuthenticationService.instance.user.isCustomer()) ...[
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: const Text('Settings'),
              onPressed: () {
                _showSettingsDialog(context);
              },
            ),
          ),
          const Gap(16),
        ],
        SizedBox(
          width: double.infinity,
          child: AppWidgets.defaultOutlinedButton(
            child: const Text('Sign out'),
            onPressed: () {
              context.read<AuthenticationBloc>().sigOut();
            },
            foregroundColor: AuthenticationService.instance.user.isCustomer()
                ? AppColors.red
                : AppColors.red2,
          ),
        ),
      ],
    );
  }

  Widget _profile() {
    final authService = AuthenticationService.instance;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: BlocBuilder<UserBloc, UserState>(builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(false),
                const Gap(24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppWidgets.profileIcon(
                      context,
                      avatarOnly: true,
                      user: authService.user,
                    ),
                    if (!showUpdateButtonBelow)
                      _updateProfileButton(context, false),
                  ],
                ),
                const Gap(16),
                ..._buildUserWidgets(context),
                const Gap(24),
                if (showUpdateButtonBelow) ...[
                  Expanded(child: Container()),
                  SizedBox(
                    width: double.infinity,
                    child: AppWidgets.defaultFilledButton(
                      child: const Text('Update profile'),
                      onPressed: () {
                        if (getScreenSize(context: context).index >
                            ScreenSize.medium.index) {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                backgroundColor: AppColors.green1,
                                content: UpdateProfileScreen(
                                  forCompany: !buildForCompany,
                                  showAddress: !AuthenticationService
                                      .instance.hasCompany,
                                ),
                              );
                            },
                          );
                          return;
                        }
                        GoRouter.of(context).goSafe(Paths.profileAction
                            .replaceAll(':action', Paths.actionUpdate),);
                      },
                    ),
                  ),
                ],
                if (!buildForCompany) ...[
                  _bankConnect(),
                ],
              ],
            );
          },),
        ),
        if (buildForCompany) ...[
          const Gap(24),
          Expanded(
            child: BlocBuilder<CompanyBloc, CompanyState>(
                builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(true),
                  const Gap(24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppWidgets.profileIcon(
                        context,
                        avatarOnly: true,
                        user: !buildForCompany ? authService.user : null,
                        company: buildForCompany ? authService.company : null,
                      ),
                      if (!showUpdateButtonBelow)
                        _updateProfileButton(context, true),
                    ],
                  ),
                  const Gap(16),
                  ..._buildCompanyWidgets(),
                  if (AuthenticationService.instance.isAdmin)
                    DefaultPenaltiesSection(foregroundColor: foregroundColor),
                  const Gap(24),
                  if (showUpdateButtonBelow &&
                      AuthenticationService.instance.isAdmin) ...[
                    const Expanded(
                        child: SizedBox(
                      width: 1,
                      height: 1,
                    ),),
                    SizedBox(
                      width: double.infinity,
                      child: AppWidgets.defaultFilledButton(
                        child: const Text('Update profile'),
                        onPressed: () {
                          if (getScreenSize(context: context).index >
                              ScreenSize.medium.index) {
                            showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  backgroundColor: AppColors.green1,
                                  content: UpdateProfileScreen(
                                    forCompany: buildForCompany,
                                  ),
                                );
                              },
                            );
                            return;
                          }
                          GoRouter.of(context).goSafe(Paths.profileAction
                              .replaceAll(':action', Paths.actionUpdate),);
                        },
                      ),
                    ),
                  ],
                ],
              );
            },),
          ),
        ],
      ],
    );
  }

  Widget _title(bool forCompany) {
    return Text(
      !forCompany ? 'Profile' : 'Company profile',
      style: TextStyle(
        color: foregroundColor,
        fontWeight: FontWeight.w600,
        fontSize: 24,
      ),
    );
  }

  Widget _updateProfileButton(BuildContext context, bool forCompany) {
    return AppWidgets.defaultFilledButton(
      child: const Text('Update profile'),
      onPressed: () {
        if (getScreenSize(context: context).index > ScreenSize.medium.index) {
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                backgroundColor: AppColors.green1,
                content: UpdateProfileScreen(
                  forCompany: forCompany,
                ),
              );
            },
          );
          return;
        }
        GoRouter.of(context).goSafe(
            Paths.profileAction.replaceAll(':action', Paths.actionUpdate),);
      },
      backgroundColor: !forCompany ? AppColors.green1 : AppColors.black,
      foregroundColor: !forCompany ? AppColors.black : AppColors.white,
    );
  }

  Widget _bankConnect() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'svg/uborange_w.svg'.assetSafe,
          width: 156,
        ),
        const Gap(16),
        AppWidgets.defaultOutlinedButton(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confirm your',
                style: TextStyle(color: foregroundColor),
              ),
              const Gap(8),
              SvgPicture.asset(
                'svg/uborange_w.svg'.assetSafe,
                width: 100,
              ),
              const Gap(8),
              Text(
                'account',
                style: TextStyle(color: foregroundColor),
              ),
            ],
          ),
          onPressed: () {},
          foregroundColor: AppColors.ubOrange,
        ),
      ],
    );
  }

  Widget _autoCollect() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'svg/uborange_b.svg'.assetSafe,
          width: 156,
        ),
        const Gap(16),
        const Text(
            '''
AutoCollect is a feature that automatically deducts the amortization from the client’s UnionBank account to your UnionBank account.

Enabling this feature will help you in your amortization collection since the client’s amortization will go to your UnionBank account automatically thus, reducing the need to contact the client, reminding them of their dues.

An option to enforce AutoCollect will be added when you add or update a product. '''),
        const Gap(31),
        SizedBox(
          width: double.infinity,
          child: AppWidgets.defaultFilledButton(
            child: const Text('Enable AutoCollect'),
            onPressed: () {},
            // padding: EdgeInsets.symmetric(vertical: 24)
          ),
        ),
      ],
    );
  }

  List<Widget> _buildUserWidgets(BuildContext context) {
    final user = AuthenticationService.instance.user;

    return [
      Text(
        user.completeNameEasternOrder,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      Text(
        user.emailAddress,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            user.mobileNumber,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          if ((user.verificationStatus &
                  UserVerificationStatus.mobileNumberVerified.value) !=
              0)
            Icon(
              Icons.check_circle,
              size: 14,
              color: foregroundColor,
            )
          else
            TextButton(
              onPressed: () =>
                  GoRouter.of(context).go(Paths.mobileVerification),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Verify',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      if (!buildForCompany)
        Text(
          AuthenticationService.instance.address.completeAddress,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      Text(
        user.facebookProfileUrl ?? 'fb.com/',
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
        ),
      ),
    ];
  }

  List<Widget> _buildCompanyWidgets() {
    if (!AuthenticationService.instance.hasCompany) {
      return [];
    }

    final company = AuthenticationService.instance.company;

    return [
      Text(
        company.name,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      Text(
        company.tagLine ?? '<<Update to add tagline>>',
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      Text(
        company.emailAddress,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      // Text(
      //   user.mobileNumber,
      //   style: TextStyle(
      //     color:foregroundColor,
      //     fontSize: 12,
      //   ),
      // ),
      Text(
        AuthenticationService.instance.address.completeAddress,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      // Text(
      //   company.facebookProfileUrl ?? 'fb.com/',
      //   style: TextStyle(
      //     color:foregroundColor,
      //     fontSize: 12,
      //   ),
      // ),
    ];
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final formKey =
            GlobalKey<FormBuilderState>(debugLabel: 'settings_dialog_form');
        return AlertDialog(
          title: const Text('Settings'),
          content: SettingsWidget(
            otherFormKey: formKey,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Update'),
                onPressed: () async {
                  if (formKey.currentState?.saveAndValidate() ?? false) {
                    await SettingsService.instance.updateSettings(
                      formKey.currentState!.simplifiedFields(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settings updated')),);
                    }
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
