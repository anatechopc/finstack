import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';

class ClientDetailScheduleItem extends StatelessWidget {
  const ClientDetailScheduleItem({
    required this.index,
    required this.schedule,
    required this.onMakePayment,
    this.onReviewPayment,
    this.isHeader = false,
    this.loan,
    this.loanRows = const [],
    super.key,
  });

  /// Every row of the loan as listed. An open-term penalty is one per
  /// overdue stretch, shown on its earliest unpaid bill (owner rule R3).
  final List<LoanSchedule> loanRows;

  final int index;
  final LoanSchedule schedule;
  final bool isHeader;
  final void Function(LoanSchedule schedule) onMakePayment;

  /// Opens a review dialog (proof screenshot + confirm/reject) for a
  /// `payment_submitted` row.
  final void Function(LoanSchedule schedule)? onReviewPayment;

  /// The loan the row belongs to. Null hides the running-penalty line.
  final Loan? loan;

  String _getLoanStatusLabel() {
    // Open-term placeholders carry their own meaningful status.
    if (schedule.isPlaceholder) {
      return schedule.status.label;
    }

    // A pending application's projected bill: no money was released.
    final currentLoan = loan;
    if (schedule.isOpenTerm &&
        schedule.id == NO_ID &&
        currentLoan != null &&
        currentLoan.status == LoanStatus.pending) {
      return LoanScheduleWidget.projectedLabel;
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
    final dueAt = Jiffy.parseFromDateTime(schedule.lateFrom);

    // Concise single-word label so the Status cell never wraps to two lines
    // (which would make rows uneven). Full form is "Not paid (overdue)".
    if (now.isAfter(dueAt)) {
      return 'Overdue';
    }

    return LoanStatus.not_paid.label;
  }

  static bool _isUnpaid(LoanSchedule s) =>
      s.status == LoanStatus.not_paid ||
      s.status == LoanStatus.not_paid_overdue;

  /// Whether the loan bills open-term cycles at all: a pending, declined,
  /// settled or bad-debt loan has nothing to pay or penalize.
  bool get _loanBills {
    final currentLoan = loan;
    return currentLoan == null ||
        LoanCalculationService.billsOpenTerm(currentLoan);
  }

  /// Open-term bills are paid oldest first: the engine bills only after the
  /// last stored row, so paying a later computed bill first would drop the
  /// earlier one. Only the earliest unpaid bill, stored (a rejected
  /// submission) or computed, can be paid.
  bool get _isPayableOpenTermBill =>
      _loanBills &&
      _isUnpaid(schedule) &&
      // A top-up being approved is paying it (review of #149).
      !(loan != null && TopUpOverdueService.isClaimedBill(loan!, schedule)) &&
      !loanRows.any(
        (other) =>
            !identical(other, schedule) &&
            other.isOpenTerm &&
            !other.isPlaceholder &&
            _isUnpaid(other) &&
            other.dueAt.isBefore(schedule.dueAt),
      );

  /// Fixed-term installments are paid oldest first too (#150): paying a
  /// later one first leaves the earlier ones overdue with their penalties
  /// running. Only the earliest unpaid installment can be paid.
  bool get _isPayableInstallment =>
      _isUnpaid(schedule) &&
      !loanRows.any(
        (other) =>
            !identical(other, schedule) &&
            !other.isOpenTerm &&
            _isUnpaid(other) &&
            other.dueAt.isBefore(schedule.dueAt),
      );

  String _displayAmount(double amount) {
    if (amount == 0) {
      return '';
    }

    return amount.toCurrency();
  }

  /// Running penalty for an unpaid row, or what was charged/waived on a paid
  /// one. Lines are 11px so the row keeps its height on one-line rows.
  List<Widget> _penaltyLines() {
    const style = TextStyle(color: AppColors.red2, fontSize: 11);
    final currentLoan = loan;
    final preview = currentLoan == null || (schedule.isOpenTerm && !_loanBills)
        ? PenaltyResult.none
        : previewPenalty(
            schedule: schedule,
            loan: currentLoan,
            loanRows: loanRows,
          );
    final daysLateNow = calculateDaysLate(
      dueAt: schedule.lateFrom,
      collectedAt: DateTime.now(),
    );

    return [
      if (preview.total > 0)
        Text(
          '+ ${preview.total.toCurrency()} penalty · $daysLateNow days late',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (schedule.penalty > 0)
        Text(
          '+ ${schedule.penalty.toCurrency()} penalty charged',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (schedule.penaltyWaivedBy != null)
        const Text('penalty waived', style: TextStyle(fontSize: 11)),
    ];
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayAmount(
                    schedule.isOpenTerm
                        ? schedule.outstandingBalance
                        : schedule.amortization,
                  ),
                ),
                ..._penaltyLines(),
              ],
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
          // 'Paid on' must ALWAYS be rendered (empty when unpaid) so every row
          // has the same number of Expanded cells as the header — otherwise an
          // unpaid row has one fewer column and all its cells widen + shift,
          // breaking alignment with the header and the paid rows.
          Expanded(
            child: Text(
              schedule.paidAt != null
                  ? schedule.paidAt!.toDefaultDateFormat()
                  : '',
            ),
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
        (user.isAdmin() || user.isTeller()) &&
        (schedule.isOpenTerm && !schedule.isPlaceholder
            ? _isPayableOpenTermBill
            : _isPayableInstallment);
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

    // Placeholder rows (the principal release and top-ups) are not
    // installments: paying the principal release would record the whole
    // principal as repaid on the loan's creation day. That includes the
    // release row approval stores for app-managed companies (#138).
    if (schedule.paidAt == null &&
        !schedule.isPlaceholder &&
        !schedule.isPrincipalRelease) {
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
