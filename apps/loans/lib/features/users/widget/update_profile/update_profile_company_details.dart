import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class UpdateProfileCompanyDetails extends StatelessWidget {
  const UpdateProfileCompanyDetails({
    required this.formKey,
    super.key,
  });

  final GlobalKey<FormBuilderState> formKey;

  @override
  Widget build(BuildContext context) {
    if (!AuthenticationService.instance.hasCompany) {
      return Container();
    }

    final company = AuthenticationService.instance.company;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Company details',
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
                company: company,
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
        AppWidgets.defaultFormBuilderTextField(
          name: 'company_name',
          label: 'Company name',
          initialValue: company.name,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'tag_line',
          label: 'Tag line',
          initialValue: company.tagLine,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'tin',
          label: 'TIN',
          initialValue: company.tin,
          helperText:
              'Enter company TIN for SEC registered. if not, enter your personal TIN.',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Text(
          'Your business is',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.black,
          ),
        ),
        FormBuilderRadioGroup<CompanyType>(
          name: 'type',
          initialValue: company.type,
          orientation: OptionsOrientation.vertical,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(borderSide: BorderSide.none),
          ),
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
          activeColor: AppColors.black,
          options: CompanyType.values.map((val) {
            return FormBuilderFieldOption(
              value: val,
              child: Text(
                val.label,
                style: const TextStyle(
                  color: AppColors.black,
                ),
              ),
            );
          }).toList(),
          onChanged: (selected) {
            formKey.currentState?.fields['sec_number_visibility']
                ?.didChange(selected == CompanyType.secRegistered);
          },
        ),
        FormBuilderField(
          initialValue: company.secNumber != null,
          builder: (state) {
            if (state.value == null) {
              return Container();
            }

            var show = false;

            if (state.value is bool) {
              show = state.value!;
            }

            return Visibility(
              visible: show,
              child: AppWidgets.defaultFormBuilderTextField(
                name: 'sec_number',
                label: 'SEC number',
                initialValue: company.secNumber,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                ]),
              ),
            );
          },
          name: 'sec_number_visibility',
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
