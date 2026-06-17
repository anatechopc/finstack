import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// Shows the add/edit payout account dialog. Returns the entered record, or
/// `null` if the user cancels. When [existing] is provided the fields are
/// prefilled and the dialog renders in "edit" mode.
Future<({String bankName, String accountName, String accountNumber})?>
    showBankDetailsFormDialog(
  BuildContext context, {
  BankDetails? existing,
}) {
  return showDialog<({String bankName, String accountName, String accountNumber})>(
    context: context,
    builder: (_) => _BankDetailsFormDialog(existing: existing),
  );
}

class _BankDetailsFormDialog extends StatefulWidget {
  const _BankDetailsFormDialog({this.existing});

  final BankDetails? existing;

  @override
  State<_BankDetailsFormDialog> createState() => _BankDetailsFormDialogState();
}

class _BankDetailsFormDialogState extends State<_BankDetailsFormDialog> {
  final _formKey = GlobalKey<FormBuilderState>(debugLabel: 'bank_details_form');

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEditing = existing != null;

    return AlertDialog(
      title: Text(
        isEditing ? 'Edit payout account' : 'Add payout account',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 500,
        child: FormBuilder(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppWidgets.defaultFormBuilderTextField(
                name: 'bank_name',
                label: 'Bank name',
                initialValue: existing?.bankName,
                validator: FormBuilderValidators.required(),
              ),
              const Gap(16),
              AppWidgets.defaultFormBuilderTextField(
                name: 'account_name',
                label: 'Account name',
                initialValue: existing?.accountName,
                validator: FormBuilderValidators.required(),
              ),
              const Gap(16),
              AppWidgets.defaultFormBuilderTextField(
                name: 'account_number',
                label: 'Account number',
                initialValue: existing?.accountNumber,
                validator: FormBuilderValidators.required(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                onPressed: _onSave,
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultOutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onSave() {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      return;
    }
    final values = _formKey.currentState!.value;
    Navigator.of(context).pop(
      (
        bankName: (values['bank_name'] as String).trim(),
        accountName: (values['account_name'] as String).trim(),
        accountNumber: (values['account_number'] as String).trim(),
      ),
    );
  }
}
