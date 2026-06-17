import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ClientDetailScheduleItem extends StatelessWidget {
  const ClientDetailScheduleItem({
    required this.index,
    required this.schedule,
    required this.onMakePayment,
    this.onReviewPayment,
    this.isHeader = false,
    super.key,
  });

  final int index;
  final LoanSchedule schedule;
  final bool isHeader;
  final void Function(LoanSchedule schedule) onMakePayment;

  /// Opens a review dialog (proof screenshot + confirm/reject) for a
  /// `payment_submitted` row.
  final void Function(LoanSchedule schedule)? onReviewPayment;

  String _getLoanStatusLabel() {
    // Open-term placeholders carry their own meaningful status.
    if (schedule.isPlaceholder) {
      return schedule.status.label;
    }

    // Payment-meaningful statuses render as-is.
    if (schedule.status == LoanStatus.paid_on_time ||
        schedule.status == LoanStatus.paid_late ||
        schedule.status == LoanStatus.payment_submitted) {
      return schedule.status.label;
    }

    // Any other status (not_paid, approved, pending, ...) on a schedule row
    // is not payment-meaningful — derive the label from the due date so a
    // schedule persisted at approval doesn't render a misleading "Approved".
    final now = Jiffy.now().startOf(Unit.day);
    final dueAt = Jiffy.parseFromDateTime(schedule.dueAt);

    // Concise single-word label so the Status cell never wraps to two lines
    // (which would make rows uneven). Full form is "Not paid (overdue)".
    if (now.isAfter(dueAt)) {
      return 'Overdue';
    }

    return LoanStatus.not_paid.label;
  }

  String _displayAmount(double amount) {
    if (amount == 0) {
      return '';
    }

    return amount.toCurrency();
  }

  @override
  Widget build(BuildContext context) {
    if (isHeader) {
      return _buildHeader();
    }

    return _buildRow(context);
  }

  Widget _buildHeader() {
    const style = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    return Row(
      children: [
        const SizedBox(
          width: 48,
          child: Text(''),
        ),
        if (schedule.isOpenTerm)
          const Expanded(
            child: SizedBox(
              width: 160,
              child: Text(
                'Date',
                style: style,
              ),
            ),
          ),
        const Expanded(
          child: SizedBox(
            width: 160,
            child: Text(
              'Due date',
              style: style,
            ),
          ),
        ),
        const Expanded(
          child: Text(
            '# of days',
            style: style,
          ),
        ),
        Expanded(
          child: Text(
            schedule.isOpenTerm
                ? 'Principal\nbalance'
                : 'Monthly\namortization',
            style: style,
          ),
        ),
        if (schedule.isOpenTerm) ...[
          const Expanded(
            child: Text(
              'Principal\nloan',
              style: style,
            ),
          ),
          const Expanded(
            child: Text(
              'Interest\ncharge',
              style: style,
            ),
          ),
          const Expanded(
            child: Text(
              'Advance\ninterest',
              style: style,
            ),
          ),
        ],
        const Expanded(
          child: Text(
            'Interest\npayment',
            style: style,
          ),
        ),
        const Expanded(
          child: Text(
            'Principal\npayment',
            style: style,
          ),
        ),
        const Expanded(
          child: Text(
            'Status',
            style: style,
          ),
        ),
        const Expanded(
          child: SizedBox(
            width: 180,
            child: Text(
              'Paid on',
              style: style,
            ),
          ),
        ),
        // Reserve space matching the data rows' trailing action column so the
        // header columns stay aligned with the rows beneath them.
        const Gap(8),
        const SizedBox(width: 180),
      ],
    );
  }

  Widget _buildRow(BuildContext context) {
    return Container(
      // Reserve a consistent minimum height so rows with an inline action
      // button don't tower over plain rows, and add a subtle divider for
      // readability on the green background.
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.black.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: Text('$index'),
          ),
          if (schedule.isOpenTerm)
            Expanded(
              child: SizedBox(
                width: 160,
                child: Text(
                  schedule.isPlaceholder
                      ? schedule.dueAt.toDefaultDateFormat()
                      : '',
                ),
              ),
            ),
          Expanded(
            child: SizedBox(
              width: 160,
              child: Text(
                !schedule.isPlaceholder
                    ? schedule.dueAt.toDefaultDateFormat()
                    : '',
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 8,
              ),
              child: Text(
                schedule.outstandingBalance == 0
                    ? ''
                    : (schedule.interestDayMultiplier * 30).toString(),
              ),
            ),
          ),
          Expanded(
            child: Text(
              _displayAmount(
                schedule.isOpenTerm
                    ? schedule.outstandingBalance
                    : schedule.amortization,
              ),
            ),
          ),
          if (schedule.isOpenTerm) ...[
            Expanded(
              child: Text(_displayAmount(schedule.principalLoan)),
            ),
            Expanded(
              child: Text(_displayAmount(schedule.interestCharge)),
            ),
            Expanded(
              child: Text(
                _displayAmount(schedule.advanceInterestPayments),
              ),
            ),
          ],
          Expanded(
            child: Text(
              schedule.isOpenTerm && schedule.status == LoanStatus.not_paid
                  ? 0.toCurrency()
                  : schedule.interestPayment.toCurrency(),
            ),
          ),
          Expanded(
            child: Text(_displayAmount(schedule.principalPayment)),
          ),
          Expanded(
            child: Text(
              _getLoanStatusLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (schedule.paidAt != null)
            Expanded(
              child: Text(schedule.paidAt!.toDefaultDateFormat()),
            ),
          // Trailing action column — fixed width so it reserves space even
          // when empty, keeping every row's columns aligned.
          const Gap(8),
          SizedBox(
            width: 180,
            child: _buildTrailingAction(context),
          ),
        ],
      ),
    );
  }

  /// Renders the row's trailing action (confirm/reject, make payment, or
  /// details) inside a fixed-width column. Returns an empty placeholder when
  /// no action applies so rows stay aligned.
  Widget _buildTrailingAction(BuildContext context) {
    final company = AuthenticationService.instance.company;
    final user = AuthenticationService.instance.user;
    final isSelfManaged =
        company.managementType == CompanyManagementType.selfManaged;
    final showMakePaymentButton = isSelfManaged &&
        user.isTeller() &&
        schedule.status == LoanStatus.not_paid;
    final showAdditionalLoanAmountDetailsButton = isSelfManaged &&
        (user.isLoanOfficer() || user.isAdmin()) &&
        schedule.status == LoanStatus.pending &&
        schedule.isOpenTerm;
    final showReviewPaymentButton = isSelfManaged &&
        (user.isAdmin() || user.isTeller()) &&
        schedule.status == LoanStatus.payment_submitted;

    if (showReviewPaymentButton) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppWidgets.defaultOutlinedButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Text('Confirm payment'),
            onPressed: () => onReviewPayment?.call(schedule),
          ),
        ],
      );
    }

    if (schedule.paidAt == null && !schedule.isAdditionalLoanAmount) {
      return Opacity(
        opacity: showMakePaymentButton ? 1.0 : 0.0,
        child: AppWidgets.defaultOutlinedButton(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          child: const Text('Make payment'),
          onPressed: !showMakePaymentButton
              ? null
              : () {
                  onMakePayment(schedule);
                },
        ),
      );
    }

    if (schedule.isAdditionalLoanAmount) {
      return Opacity(
        opacity: showAdditionalLoanAmountDetailsButton ? 1.0 : 0.0,
        child: AppWidgets.defaultOutlinedButton(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          child: const Text('Details'),
          onPressed: !showAdditionalLoanAmountDetailsButton
              ? null
              : () {
                  AppWidgets.showAdditionalLoanDetailDialog(
                    context,
                    additionalLoanId: schedule.id,
                  );
                },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
