import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/bank_details/widget/payout_accounts_section.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_repository/user_repository.dart';

class SettingsWidget extends StatelessWidget {
  const SettingsWidget({super.key, this.otherFormKey});
  final GlobalKey<FormBuilderState>? otherFormKey;

  @override
  Widget build(BuildContext context) {
    GlobalKey<FormBuilderState> formKey;

    final auth = AuthenticationService.instance;
    final isLenderAdmin = auth.hasCompany &&
        auth.user.userRole.index > UserRole.customer.index &&
        auth.company.managementType == CompanyManagementType.selfManaged;

    if (otherFormKey != null) {
      formKey = otherFormKey!;
    } else {
      formKey = GlobalKey<FormBuilderState>(debugLabel: 'settings_form');
    }

    return FormBuilder(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FormBuilderSwitch(
            name: 'enable_classic_ui',
            title: const Text('Use classic UI'),
            initialValue: SettingsService.instance.appUseClassicUI,
            activeTrackColor: AppColors.green1_6,
          ),
          const Gap(16),
          FormBuilderSwitch(
            name: 'enable_force_payment_confirmation',
            title: const Text('Force payment confirmation'),
            initialValue: SettingsService.instance.forcePaymentConfirmation,
            activeTrackColor: AppColors.green1_6,
          ),
          const Gap(16),
          FormBuilderSwitch(
            name: 'enable_product_add_ons',
            title: const Text('Enable product add-ons'),
            initialValue: SettingsService.instance.enableProductAddOns,
            activeTrackColor: AppColors.green1_6,
          ),
          if (isLenderAdmin) ...[
            const Gap(16),
            const PayoutAccountsSection(),
          ],
          if (otherFormKey == null)
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Update'),
                onPressed: () async {
                  if (formKey.currentState?.saveAndValidate() ?? false) {
                    await SettingsService.instance.updateSettings(
                      formKey.currentState!.simplifiedFields(),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings updated')),);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
