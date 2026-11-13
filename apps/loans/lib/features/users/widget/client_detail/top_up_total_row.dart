import 'package:flutter/material.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:product_repository/product_repository.dart';

/// The top-up dialog total: amount + additional charges − deductions of the
/// top-up record `AdditionalLoanBloc` stores. The bloc runs the same
/// `applyChargesAndDeductionsDetailed` call and discards its `totalAmount`
/// (`additional_loan_bloc.dart:79`), storing the parts this sums. Upfront
/// charges are stored separately and are not in the total. Empty or
/// unparsable input shows 0.
double topUpDialogTotal(Product product, String? amountText) {
  final amount = double.tryParse(amountText ?? '');
  if (amount == null) return 0;

  return ChargeCalculator.applyChargesAndDeductionsDetailed(
    baseAmount: amount,
    charges: product.additionalCharges,
    deductions: product.deductions,
  ).totalAmount;
}

/// The "Total:" line of the top-up (additional loan amount) dialog.
class TopUpTotalRow extends StatelessWidget {
  const TopUpTotalRow({
    required this.product,
    required this.amountText,
    super.key,
  });

  final Product product;
  final String? amountText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Total:'),
        Text(topUpDialogTotal(product, amountText).toCurrency()),
      ],
    );
  }
}
