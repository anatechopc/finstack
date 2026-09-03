import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Builds a [Penalty] from the dialog's form values.
///
/// `amount` is the raw text; a trailing `%` means percentage, the same
/// convention as charges. `frequency` is a [PenaltyFrequency] or absent.
Penalty penaltyFromFields(Map<String, dynamic> fields) {
  final amountStr = (fields['amount'] as String).trim();
  final isPercentage = amountStr.endsWith('%');
  final amount = double.parse(
    isPercentage ? amountStr.substring(0, amountStr.length - 1) : amountStr,
  );

  return Penalty(
    id: StringHelper.generateId(length: 8),
    name: (fields['name'] as String).trim(),
    description: ((fields['description'] as String?) ?? '').trim(),
    amount: amount,
    isPercentage: isPercentage,
    frequency:
        (fields['frequency'] as PenaltyFrequency?) ?? PenaltyFrequency.once,
  );
}

String? _validateAmount(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  if (value.endsWith('%')) {
    final parsed = double.tryParse(value.substring(0, value.length - 1));
    if (parsed == null || parsed <= 0 || parsed > 100) {
      return 'Percentage value should only be between 0 and 100';
    }
  } else {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return 'Amount should be greater than 0';
    }
  }

  return null;
}

/// Shared "add a penalty" dialog used by the company defaults section and the
/// add-product wizard. Resolves to the new [Penalty], or null when dismissed.
Future<Penalty?> showPenaltyDialog(BuildContext context) {
  return showDialog<Penalty>(
    context: context,
    builder: (context) {
      final key = GlobalKey<FormBuilderState>(debugLabel: 'penalty_dialog');

      return AlertDialog(
        title: const Text('Penalty'),
        backgroundColor: AppColors.green1,
        content: FormBuilder(
          key: key,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppWidgets.defaultFormBuilderTextField(
                  name: 'amount',
                  label: 'Amount',
                  helperText: 'Allowed: amount or percentage (e.g 100, 3.5%)',
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    _validateAmount,
                  ]),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp('^[0-9]*[.]?[0-9]*[%]?'),
                    ),
                  ],
                ),
                const Gap(16),
                AppWidgets.defaultFormBuilderTextField(
                  name: 'name',
                  label: 'Name',
                  validator: FormBuilderValidators.required(),
                ),
                const Gap(16),
                AppWidgets.defaultFormBuilderTextField(
                  name: 'description',
                  label: 'Description',
                ),
                const Gap(16),
                FormBuilderDropdown<PenaltyFrequency>(
                  name: 'frequency',
                  initialValue: PenaltyFrequency.once,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: PenaltyFrequency.values
                      .map(
                        (frequency) => DropdownMenuItem(
                          value: frequency,
                          child: Text(frequency.label),
                        ),
                      )
                      .toList(),
                ),
                const Gap(8),
                const Text(
                  'Percentages apply to the installment amount. Daily and '
                  'monthly penalties multiply by how late the payment is; '
                  '"Per installment" follows the product\'s loan term '
                  '(monthly or twice a month). A started period counts in '
                  'full.',
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: const Text('Add'),
              onPressed: () {
                if (!(key.currentState?.saveAndValidate() ?? false)) {
                  return;
                }

                Navigator.of(context, rootNavigator: true).pop(
                  penaltyFromFields(key.currentState!.value),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
