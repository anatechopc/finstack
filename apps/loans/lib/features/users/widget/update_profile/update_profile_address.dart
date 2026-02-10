import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/widgets/app_widgets.dart';

class UpdateProfileAddress extends StatelessWidget {
  const UpdateProfileAddress({super.key});

  @override
  Widget build(BuildContext context) {
    final address = AuthenticationService.instance.address;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Address',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_1',
          label: 'Address line 1',
          initialValue: address.line1,
          helperText: 'E.g house no., Street, Unit no.',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_2',
          label: 'Address line 2',
          initialValue: address.line2,
          helperText: 'E.g Subdivision, building',
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'barangay',
          label: 'Barangay',
          initialValue: address.barangay,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'city',
          label: 'City/Municipality',
          initialValue: address.city,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'province',
          label: 'Province',
          initialValue: address.province,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'country',
          label: 'Country',
          initialValue: address.country,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'zip',
          label: 'Zip code',
          initialValue: address.zipCode,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
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
