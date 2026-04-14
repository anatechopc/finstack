import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/model/borrower_loan_group.dart';
import 'package:loooans/features/payment_center/widget/overdue_summary_tile.dart';
import 'package:loooans/features/payment_center/widget/payable_tile_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class LoanCardWidget extends StatelessWidget {
  const LoanCardWidget({
    required this.group,
    required this.onPay,
    this.onPayOverdue,
    this.readOnly = false,
    this.onAddSpecialLoan,
    this.onAddAmount,
    this.indented = false,
    super.key,
  });

  final BorrowerLoanGroup group;
  final void Function(LoanSchedule schedule) onPay;
  final void Function(List<LoanSchedule> overdueSchedules)? onPayOverdue;
  final VoidCallback? onAddSpecialLoan;
  final VoidCallback? onAddAmount;
  final bool readOnly;
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final loan = group.loan;
    final isExpanded = context.select<PaymentCenterBloc, bool>(
      (bloc) => bloc.state.expandedLoanSchedules.containsKey(loan.id),
    );

    final overdueSchedules = group.actionableSchedules
        .where((s) => s.status == LoanStatus.not_paid_overdue)
        .toList();
    final upcomingSchedules = group.actionableSchedules
        .where((s) => s.status != LoanStatus.not_paid_overdue)
        .toList();

    return Container(
      margin: EdgeInsets.only(
        left: indented ? 24 : 0,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () {
              if (isExpanded) {
                context
                    .read<PaymentCenterBloc>()
                    .add(CollapseLoanEvent(loanId: loan.id));
              } else {
                context
                    .read<PaymentCenterBloc>()
                    .add(ExpandLoanEvent(loanId: loan.id, loan: loan));
              }
            },
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              group.loanType,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Gap(6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: (loan.period == 0
                                        ? AppColors.ubOrange
                                        : AppColors.green1_6)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                loan.period == 0 ? 'Open' : 'Fixed',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: loan.period == 0
                                      ? AppColors.ubOrange
                                      : AppColors.green1_6,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (loan.parentId != null) ...[
                              const Gap(6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Add-on',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Gap(4),
                        Text(
                          '${loan.amount.toCurrency()} - ${loan.completeTerm}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(loan.status),
                  if (overdueSchedules.isNotEmpty) ...[
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${overdueSchedules.length}',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Gap(8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // Consolidated overdue tile
          if (overdueSchedules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OverdueSummaryTile(
                overdueSchedules: overdueSchedules,
                readOnly: readOnly,
                onPay: () {
                  if (onPayOverdue != null) {
                    onPayOverdue!(overdueSchedules);
                  }
                },
              ),
            ),

          // Upcoming schedules (individual tiles)
          if (upcomingSchedules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: upcomingSchedules
                    .map(
                      (schedule) => PayableTileWidget(
                        schedule: schedule,
                        readOnly: readOnly,
                        onPay: () => onPay(schedule),
                      ),
                    )
                    .toList(),
              ),
            )
          else if (overdueSchedules.isEmpty &&
              !readOnly &&
              _isActiveLoan(loan.status))
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              child: Text(
                'No pending schedules',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Action buttons — only for open-term, active loans
          if (!readOnly &&
              loan.period == 0 &&
              _isActiveLoan(loan.status))
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onAddSpecialLoan != null)
                    TextButton.icon(
                      onPressed: onAddSpecialLoan,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        'Special Loan',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (onAddAmount != null) ...[
                    if (onAddSpecialLoan != null) const Gap(8),
                    TextButton.icon(
                      onPressed: onAddAmount,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        'Amount',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Expanded schedule history
          if (isExpanded) _buildExpandedSchedules(context),

          const Gap(4),
        ],
      ),
    );
  }

  bool _isActiveLoan(LoanStatus status) {
    return status != LoanStatus.completed &&
        status != LoanStatus.declined &&
        status != LoanStatus.bad_debt;
  }

  Widget _buildStatusBadge(LoanStatus status) {
    final color = switch (status) {
      LoanStatus.approved => AppColors.green1_6,
      LoanStatus.completed => AppColors.blue,
      LoanStatus.paid_on_time || LoanStatus.paid_late => AppColors.green1,
      LoanStatus.not_paid_overdue ||
      LoanStatus.bad_debt =>
        AppColors.red,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildExpandedSchedules(BuildContext context) {
    final schedules =
        context.select<PaymentCenterBloc, List<LoanSchedule>?>(
      (bloc) => bloc.state.expandedLoanSchedules[group.loan.id],
    );

    if (schedules == null || schedules.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Full Schedule History',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          ...schedules.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      s.dueAt.toDefaultDateFormat(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.amortization.toCurrency(),
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const Gap(8),
                  SizedBox(
                    width: 100,
                    child: Text(
                      s.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: _scheduleStatusColor(s.status),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(8),
        ],
      ),
    );
  }

  Color _scheduleStatusColor(LoanStatus status) {
    return switch (status) {
      LoanStatus.paid_on_time => AppColors.green1_6,
      LoanStatus.paid_late => AppColors.ubOrange,
      LoanStatus.not_paid_overdue => AppColors.red,
      LoanStatus.not_paid => Colors.grey,
      _ => Colors.grey,
    };
  }
}
