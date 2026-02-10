import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ClientDetailScheduleItem extends StatelessWidget {
  const ClientDetailScheduleItem({
    required this.index,
    required this.schedule,
    required this.onMakePayment,
    this.isHeader = false,
    super.key,
  });

  final int index;
  final LoanSchedule schedule;
  final bool isHeader;
  final void Function(LoanSchedule schedule) onMakePayment;

  String _getLoanStatusLabel() {
    if (schedule.isPlaceholder) {
      return schedule.status.label;
    }

    final now = Jiffy.now().startOf(Unit.day);
    final dueAt = Jiffy.parseFromDateTime(schedule.dueAt);

    if (schedule.status == LoanStatus.not_paid && now.isAfter(dueAt)) {
      return LoanStatus.not_paid_overdue.label;
    }

    return schedule.status.label;
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
      ],
    );
  }

  Widget _buildRow(BuildContext context) {
    final company = AuthenticationService.instance.company;
    final user = AuthenticationService.instance.user;
    final showMakePaymentButton =
        company.managementType == CompanyManagementType.selfManaged &&
            user.isTeller() &&
            schedule.status == LoanStatus.not_paid;
    final showAdditionalLoanAmountDetailsButton =
        company.managementType == CompanyManagementType.selfManaged &&
            (user.isLoanOfficer() || user.isAdmin()) &&
            schedule.status == LoanStatus.pending &&
            schedule.isOpenTerm;

    return Container(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
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
            child: Text(_getLoanStatusLabel()),
          ),
          if (schedule.paidAt != null)
            Expanded(
              child: Text(schedule.paidAt!.toDefaultDateFormat()),
            ),
          if (schedule.status == LoanStatus.payment_submitted) ...[
            const Gap(
              8,
            ),
            AppWidgets.defaultOutlinedButton(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: const Text('Confirm payment'),
              onPressed: () {
                // NOTE: this is confirmation of payment for
                // managementType = CompanyManagementType.app
              },
            ),
          ],
          if (schedule.paidAt == null &&
              !schedule.isAdditionalLoanAmount) ...[
            Opacity(
              opacity: showMakePaymentButton ? 1.0 : 0.0,
              child: SizedBox(
                width: 160,
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
              ),
            ),
          ],
          if (schedule.isAdditionalLoanAmount)
            Opacity(
              opacity: showAdditionalLoanAmountDetailsButton ? 1.0 : 0.0,
              child: SizedBox(
                width: 160,
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
              ),
            ),
        ],
      ),
    );
  }
}
