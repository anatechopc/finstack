import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// A consolidated tile that summarizes multiple overdue schedules.
///
/// For open-term loans: shows the summed interest charges.
/// For fixed-term loans: shows the summed amortization (total payable).
class OverdueSummaryTile extends StatelessWidget {
  const OverdueSummaryTile({
    required this.overdueSchedules,
    required this.onPay,
    this.readOnly = false,
    super.key,
  });

  final List<LoanSchedule> overdueSchedules;
  final VoidCallback onPay;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (overdueSchedules.isEmpty) return const SizedBox.shrink();

    final count = overdueSchedules.length;
    final isOpenTerm = overdueSchedules.first.isOpenTerm;

    // For open-term: sum interest charges (principal is 0)
    // For fixed-term: sum amortization (interest + principal)
    final totalPayable = isOpenTerm
        ? overdueSchedules.fold<double>(
            0,
            (sum, s) => sum + s.interestCharge,
          )
        : overdueSchedules.fold<double>(
            0,
            (sum, s) => sum + s.amortization,
          );

    final totalInterest = overdueSchedules.fold<double>(
      0,
      (sum, s) => sum + s.interestCharge,
    );

    final totalPrincipal = isOpenTerm
        ? 0.0
        : overdueSchedules.fold<double>(
            0,
            (sum, s) => sum + s.principalPayment,
          );

    final earliestDue = overdueSchedules
        .map((s) => s.dueAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latestDue = overdueSchedules
        .map((s) => s.dueAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Overdue - $count ${count == 1 ? 'payment' : 'payments'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(6),
                    Text(
                      '${earliestDue.toDefaultDateFormat()}'
                      '${count > 1 ? ' — ${latestDue.toDefaultDateFormat()}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              if (!readOnly)
                AppWidgets.defaultFilledButton(
                  onPressed: onPay,
                  backgroundColor: AppColors.red,
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
          ),
          const Gap(8),
          // Amount breakdown
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                if (isOpenTerm)
                  _buildRow('Total interest', totalInterest)
                else ...[
                  _buildRow('Total interest', totalInterest),
                  _buildRow('Total principal', totalPrincipal),
                  const Divider(height: 8),
                  _buildRow(
                    'Total payable',
                    totalPayable,
                    bold: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              color: Colors.grey[700],
            ),
          ),
          Text(
            amount.toCurrency(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
