import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';

/// What a top-up of [amountText] adds to the loan balance: the amount plus
/// the product's additional charges, as the engine adds a top-up
/// (`topUp.amount + topUp.additionalCharges` in `LoanCalculationService`).
/// An upfront charge is not added and deductions are not subtracted (#127).
/// Empty or unparsable input: 0.
double topUpAddedToLoan(Product product, String? amountText) {
  final amount = double.tryParse(amountText ?? '');
  if (amount == null) return 0;

  return amount +
      ChargeCalculator.applyChargesAndDeductionsDetailed(
        baseAmount: amount,
        charges: product.additionalCharges,
        deductions: product.deductions,
      ).totalAdditionalCharges;
}

/// The cash a top-up of [amountText] hands over:
/// [TopUpOverdueService.proceedsOf] (the amount less deductions and upfront
/// charges), the figure the overdue warning shows. Empty or unparsable
/// input: 0.
double topUpCashHandedOver(Product product, String? amountText) {
  final amount = double.tryParse(amountText ?? '');
  if (amount == null) return 0;

  return TopUpOverdueService.proceedsOf(
    amount: amount,
    charges: product.additionalCharges,
    deductions: product.deductions,
  );
}

/// The form of both top-up dialogs (client detail and the Payment Center):
/// the amount, then, in place of one total (owner, 2026-11-20), what the
/// top-up adds to the loan with the charges added, and the cash it hands
/// over with what is taken from it: the deductions and the upfront charges.
/// The dialogs read the amount through [formKey].
class TopUpAmountForm extends StatefulWidget {
  const TopUpAmountForm({
    required this.formKey,
    required this.product,
    super.key,
  });

  final GlobalKey<FormBuilderState> formKey;

  /// Null when the product could not be loaded: only the amount is shown.
  final Product? product;

  @override
  State<TopUpAmountForm> createState() => _TopUpAmountFormState();
}

class _TopUpAmountFormState extends State<TopUpAmountForm> {
  String? _amountText;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return FormBuilder(
      key: widget.formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 350),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppWidgets.defaultFormBuilderTextField(
              name: 'amount',
              label: 'Add amount',
              validator: FormBuilderValidators.required(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('^[0-9]*[.]?[0-9]*')),
              ],
              onChanged: (value) => setState(() => _amountText = value),
            ),
            if (product != null) ...[
              const Gap(16),
              _line(
                'Added to the loan:',
                topUpAddedToLoan(product, _amountText).toCurrency(),
              ),
              for (final charge in product.additionalCharges)
                if (!charge.isUpfrontCollection)
                  _part('Add: ${charge.description}:', _rate(charge)),
              const Divider(color: AppColors.black),
              _line(
                'Cash handed over:',
                topUpCashHandedOver(product, _amountText).toCurrency(),
              ),
              for (final deduction in product.deductions)
                _part('Less: ${deduction.description}:', _rate(deduction)),
              // Collected from the cash, not added to the loan.
              for (final charge in product.additionalCharges)
                if (charge.isUpfrontCollection)
                  _part(
                    'Less: ${charge.description} (collected upfront):',
                    _rate(charge),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  static String _rate(Charge charge) =>
      charge.isPercentage ? '${charge.amount}%' : '${charge.amount}';

  /// A long label wraps; the figure stays on the right.
  static Widget _line(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.black)),
          ),
          const Gap(8),
          Text(value),
        ],
      );

  /// A charge or deduction under the figure it makes up.
  static Widget _part(String label, String value) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: _line(label, value),
      );
}
