import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/mobile_lock.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class UpdateProfilePortraitPersonalFields extends StatelessWidget {
  const UpdateProfilePortraitPersonalFields({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthenticationService.instance.user;
    final lock = computeMobileLock(user.mobileVerifiedAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Primary details',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(16),
        Center(
          child: Stack(
            children: [
              AppWidgets.profileIcon(
                context,
                avatarOnly: true,
                removeExtraPadding: true,
                user: AuthenticationService.instance.user,
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'svg/upload.svg'.assetSafe,
                    width: 20,
                    colorFilter: const ColorFilter.mode(
                      AppColors.green2,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'last_name',
          label: 'Last name',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'first_name',
          label: 'First name',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'middle_name',
          label: 'Middle name(optional)',
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderDatePicker(
            name: 'birth_date',
            label: 'Birth date',
            validator: FormBuilderValidators.required(),),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'mobile_number',
          label: 'Mobile number',
          enabled: !lock.locked,
          helperText: lock.locked ? 'Editable in ${lock.daysLeft} days' : null,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.maxLength(10),
          ]),
          prefix: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '+63',
              style: TextStyle(
                color: AppColors.black,
              ),
            ),
          ),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'email_address',
          label: 'Email address',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.email(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'facebook_profile',
          label: 'Facebook profile',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
      ],
    );
  }
}
