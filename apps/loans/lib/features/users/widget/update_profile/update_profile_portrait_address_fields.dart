import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/widgets/app_widgets.dart';

class UpdateProfilePortraitAddressFields extends StatelessWidget {
  const UpdateProfilePortraitAddressFields({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Address',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_1',
          label: 'Address line 1',
          helperText: 'E.g house no., Street, Unit no.',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_2',
          label: 'Address line 2',
          helperText: 'E.g Subdivision, building',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'barangay',
          label: 'Barangay',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'city',
          label: 'City/Municipality',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'province',
          label: 'Province',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'country',
          label: 'Country',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          name: 'zip',
          label: 'Zip code',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
      ],
    );
  }
}
