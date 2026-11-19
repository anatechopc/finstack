import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// The overdue warning shown when a lender adds a top-up to an open-term
/// loan (owner, 2026-11-19). With no bill past due it shows nothing and
/// returns `proceed: true, choice: null`. Otherwise the lender deducts the
/// overdue amount from the top-up, adds it to the next bill, or cancels
/// (`proceed: false`). "Deduct" is not offered when the overdue amount is
/// more than the cash the top-up hands over ([proceeds]).
///
/// [schedules] are the loan's rows and bills as client detail lists them.
Future<({bool proceed, OverdueChoice? choice})> askTopUpOverdueChoice(
  BuildContext context, {
  required Loan loan,
  required List<LoanSchedule> schedules,
  required double proceeds,
}) async {
  final overdue = TopUpOverdueService.overdue(loan: loan, schedules: schedules);
  if (overdue == null) {
    return (proceed: true, choice: null);
  }
  final canDeduct = overdue.amount <= proceeds;
  final count = overdue.bills.length;
  final choice = await showDialog<OverdueChoice>(
    context: context,
    builder: (dialogContext) {
      void choose(OverdueChoice? value) =>
          Navigator.of(dialogContext, rootNavigator: true).pop(value);

      return AlertDialog(
        title: const Text('This loan has overdue bills'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'bill' : 'bills'} with penalties as '
                  "of today (what the borrower's Pay now shows): "
                  '${overdue.amount.toCurrency()}',
                ),
                const Gap(8),
                Text('Cash this top-up hands over: ${proceeds.toCurrency()}'),
                const Gap(16),
                Text(
                  canDeduct
                      ? 'Deduct from the top-up: the overdue bills are recorded '
                          'paid when the top-up is approved, with their '
                          'penalties on that day; '
                          '${(proceeds - overdue.amount).toCurrency()} is '
                          'released if it is approved today.'
                      : 'Deduct from the top-up is not available: the overdue '
                          'amount is more than the cash this top-up hands over.',
                ),
                const Gap(8),
                Text(
                  'Add to the next bill: ${proceeds.toCurrency()} is released; '
                  'the overdue bills stay owed with the next bill and their '
                  'penalties keep running until they are paid.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            onPressed: canDeduct ? () => choose(OverdueChoice.deduct) : null,
            child: const Text('Deduct from the top-up'),
          ),
          AppWidgets.defaultOutlinedButton(
            onPressed: () => choose(OverdueChoice.nextBill),
            child: const Text('Add to the next bill'),
          ),
          AppWidgets.defaultOutlinedButton(
            onPressed: () => choose(null),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );

  return (proceed: choice != null, choice: choice);
}

/// The approval confirmation for [topUp]. For a top-up whose lender chose
/// "deduct", it shows the overdue amount on the approval day and the cash
/// released after it; approval is not offered when that amount is more
/// than the proceeds. A top-up whose approval stopped while recording its
/// deduction shows the amount it claimed; approving completes it. Returns
/// the deduction shown (0 when nothing is deducted), or null when the
/// approver cancels.
Future<double?> showTopUpApprovalDialog(
  BuildContext context, {
  required AdditionalLoanAmount topUp,
  required Loan loan,
  required List<LoanSchedule> schedules,
}) {
  final proceeds = TopUpOverdueService.proceeds(topUp);
  final claimed = topUp.deductionPlan.isNotEmpty;
  final deducts = topUp.overdueChoice == OverdueChoice.deduct && !claimed;
  final overdue = deducts
      ? TopUpOverdueService.overdue(loan: loan, schedules: schedules)
      : null;
  final deduction = claimed ? topUp.overdueDeduction : overdue?.amount ?? 0.0;
  final canApprove = deduction <= proceeds;

  return showDialog<double>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Are you sure?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Warning: You are about to approve the additional loan amount.'
                '\nPlease make sure this is your desired action.'
                '\nYou cannot undo this action.',
              ),
              if (topUp.overdueChoice != null) ...[
                const Gap(16),
                Text(
                  switch ((topUp.overdueChoice!, overdue)) {
                    _ when claimed => 'An earlier approval stopped while '
                        'recording ${deduction.toCurrency()} of overdue bills '
                        'paid from this top-up. Approving completes it.',
                    (OverdueChoice.nextBill, _) =>
                      'The lender chose to add the '
                          'overdue bills to the next bill.',
                    (OverdueChoice.deduct, null) => 'The lender chose to deduct '
                        'the overdue bills. No bill is overdue now: nothing is '
                        'deducted.',
                    (OverdueChoice.deduct, final overdue?) =>
                      'The lender chose to deduct the overdue bills. Overdue '
                          'as of today, with penalties: '
                          '${overdue.amount.toCurrency()} '
                          '(${overdue.bills.length} '
                          '${overdue.bills.length == 1 ? 'bill' : 'bills'}, '
                          'recorded paid today).',
                  },
                ),
                const Gap(8),
                Text(
                  canApprove
                      ? 'Cash to release: '
                          '${(proceeds - deduction).toCurrency()} '
                          '(of ${proceeds.toCurrency()})'
                      : 'The overdue amount is more than the cash this top-up '
                          'hands over (${proceeds.toCurrency()}). Decline it '
                          'and add it again with another option.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            backgroundColor: AppColors.green1,
            foregroundColor: AppColors.black,
            onPressed: canApprove
                ? () => Navigator.of(dialogContext, rootNavigator: true)
                    .pop(deduction)
                : null,
            child: const Text('Approve'),
          ),
          AppWidgets.defaultFilledButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
