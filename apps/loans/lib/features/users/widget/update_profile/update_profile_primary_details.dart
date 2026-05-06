import 'package:collection/collection.dart';
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

class UpdateProfilePrimaryDetails extends StatelessWidget {
  const UpdateProfilePrimaryDetails({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthenticationService.instance.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Primary details',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Center(
          child: Stack(
            children: [
              AppWidgets.profileIcon(
                context,
                avatarOnly: true,
                removeExtraPadding: true,
                user: user,
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.black.withOpacity(0.6),
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
        AppWidgets.defaultFormBuilderTextField(
          name: 'last_name',
          label: 'Last name',
          initialValue: user.lastName,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'first_name',
          label: 'First name',
          initialValue: user.firstName,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'middle_name',
          label: 'Middle name(optional)',
          initialValue: user.middleName,
        ),
        AppWidgets.defaultFormBuilderDatePicker(
            name: 'birth_date',
            label: 'Birth date',
            initialDate: user.birthDate,
            validator: FormBuilderValidators.required(),),
        Builder(
          builder: (context) {
            final lock = computeMobileLock(user.mobileVerifiedAt);
            return AppWidgets.defaultFormBuilderTextField(
              name: 'mobile_number',
              label: 'Mobile number',
              initialValue: user.mobileNumber,
              enabled: !lock.locked,
              helperText:
                  lock.locked ? 'Editable in ${lock.daysLeft} days' : null,
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
            );
          },
        ),
        // AppWidgets.defaultFormBuilderTextField(
        //   name: 'email_address',
        //   label: 'Email address',
        //   initialValue: user.emailAddress,
        //   borderColor: AppColors.black,
        //   validator: FormBuilderValidators.compose([
        //     FormBuilderValidators.required(),
        //     FormBuilderValidators.email(),
        //   ]),
        // ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'facebook_profile',
          label: 'Facebook profile',
          initialValue: user.facebookProfileUrl,
        ),
      ]
          .mapIndexed((index, widget) {
            return [if (index != 0) const Gap(16), widget];
          })
          .flattened
          .toList(),
    );
  }
}
