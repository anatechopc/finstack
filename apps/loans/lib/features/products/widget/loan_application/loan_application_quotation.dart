import 'package:flutter/material.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';

class LoanApplicationQuotation extends StatelessWidget {
  const LoanApplicationQuotation({
    required this.loanAmount,
    required this.period,
    required this.interestRate,
    super.key,
  });

  final double loanAmount;
  final int period;
  final double interestRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: defaultBorderRadius,
        border: Border.all(),
      ),
      child: QuotationWidget(
        loanAmount: loanAmount,
        period: period,
        interestRate: interestRate,
      ),
    );
  }
}
