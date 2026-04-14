import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payment_center/model/borrower_loan_group.dart';
import 'package:loooans/features/payment_center/widget/loan_card_widget.dart';
import 'package:loooans/widgets/app_widgets.dart';

class BorrowerLoanSection extends StatelessWidget {
  const BorrowerLoanSection({
    required this.loans,
    required this.onPay,
    required this.onPayOverdue,
    required this.onNewLoan,
    required this.onAddSpecialLoan,
    required this.onAddAmount,
    super.key,
  });

  final List<BorrowerLoanGroup> loans;
  final void Function(BorrowerLoanGroup group, LoanSchedule schedule) onPay;
  final void Function(
    BorrowerLoanGroup group,
    List<LoanSchedule> overdueSchedules,
  ) onPayOverdue;
  final VoidCallback onNewLoan;
  final void Function(BorrowerLoanGroup group) onAddSpecialLoan;
  final void Function(BorrowerLoanGroup group) onAddAmount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                "Borrower's Loans",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            AppWidgets.defaultFilledButton(
              onPressed: onNewLoan,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16),
                  Gap(4),
                  Text('New Loan', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const Gap(12),
        if (loans.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No loans found',
                style: TextStyle(color: Colors.black),
              ),
            ),
          )
        else
          ...loans.map(
            (group) => Column(
              children: [
                LoanCardWidget(
                  group: group,
                  onPay: (schedule) => onPay(group, schedule),
                  onPayOverdue: (schedules) =>
                      onPayOverdue(group, schedules),
                  onAddSpecialLoan: () => onAddSpecialLoan(group),
                  onAddAmount: () => onAddAmount(group),
                ),
                // Nested child loans
                ...group.childLoans.map(
                  (child) => LoanCardWidget(
                    group: child,
                    onPay: (schedule) => onPay(child, schedule),
                    onPayOverdue: (schedules) =>
                        onPayOverdue(child, schedules),
                    onAddSpecialLoan: () => onAddSpecialLoan(child),
                    onAddAmount: () => onAddAmount(child),
                    indented: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
