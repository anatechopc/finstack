import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class PayableTileWidget extends StatelessWidget {
  const PayableTileWidget({
    required this.schedule,
    required this.onPay,
    this.readOnly = false,
    super.key,
  });

  final LoanSchedule schedule;
  final VoidCallback onPay;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final isOverdue = schedule.status == LoanStatus.not_paid_overdue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isOverdue
            ? AppColors.red.withValues(alpha: 0.08)
            : AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverdue
              ? AppColors.red.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.dueAt.toDefaultDateFormat(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Gap(2),
                Text(
                  'Amortization: ${schedule.amortization.toCurrency()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? AppColors.red.withValues(alpha: 0.15)
                        : AppColors.green1.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isOverdue ? 'Overdue' : 'Upcoming',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isOverdue ? AppColors.red : AppColors.green1_6,
                    ),
                  ),
                ),
                const Gap(2),
                Text(
                  schedule.outstandingBalance.toCurrency(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (!readOnly) ...[
            const Gap(8),
            AppWidgets.defaultFilledButton(
              onPressed: onPay,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: const Text(
                'Pay',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
