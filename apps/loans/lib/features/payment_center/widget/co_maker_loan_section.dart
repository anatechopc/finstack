import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/payment_center/model/borrower_loan_group.dart';
import 'package:loooans/features/payment_center/widget/loan_card_widget.dart';

class CoMakerLoanSection extends StatelessWidget {
  const CoMakerLoanSection({
    required this.loans,
    super.key,
  });

  final List<BorrowerLoanGroup> loans;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Co-maker Loans',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const Gap(12),
        if (loans.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No co-maker loans found',
                style: TextStyle(color: Colors.black),
              ),
            ),
          )
        else
          ...loans.map(
            (group) => LoanCardWidget(
              group: group,
              readOnly: true,
              onPay: (_) {},
            ),
          ),
      ],
    );
  }
}
