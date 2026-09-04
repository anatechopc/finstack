import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// Collection date, live penalty breakdown, and waive controls for any
/// confirm-payment dialog. Registers `collected_at`, `waive_penalty`, and
/// `waive_reason` in the enclosing [FormBuilder]. Handles one installment or
/// many (bulk overdue, multi-schedule submissions) under a single date.
class PaymentPenaltySection extends StatefulWidget {
  const PaymentPenaltySection({
    required this.schedules,
    required this.loan,
    this.initialCollectedAt,
    super.key,
  });

  final List<LoanSchedule> schedules;
  final Loan loan;

  /// Defaults to now. Borrower submissions pass the submission time.
  final DateTime? initialCollectedAt;

  @override
  State<PaymentPenaltySection> createState() => _PaymentPenaltySectionState();
}

class _PaymentPenaltySectionState extends State<PaymentPenaltySection> {
  late DateTime _collectedAt = widget.initialCollectedAt ?? DateTime.now();
  bool _waive = false;

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final results = [
      for (final schedule in widget.schedules)
        (
          schedule: schedule,
          lateness: resolveLateness(
            schedule: schedule,
            loan: loan,
            collectedAt: _collectedAt,
          ),
        ),
    ];
    final amountDue = results.fold<double>(
      0,
      (sum, r) =>
          sum +
          (r.schedule.isOpenTerm
              ? r.schedule.outstandingBalance
              : r.schedule.amortization),
    );
    final penaltyTotal = results.fold<double>(
      0,
      (sum, r) => sum + r.lateness.penalties.total,
    );
    final maxDaysLate = results.fold<int>(
      0,
      (m, r) => r.lateness.daysLate > m ? r.lateness.daysLate : m,
    );
    final total = _waive ? amountDue : amountDue + penaltyTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppWidgets.defaultFormBuilderDatePicker(
          name: 'collected_at',
          label: 'Collection date',
          helperText: 'When the money was received. Lateness and penalties '
              'use this date, not today.',
          initialValue: _collectedAt,
          lastDate: DateTime.now(),
          validator: FormBuilderValidators.required(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _collectedAt = value);
            }
          },
        ),
        const Gap(12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _row(
                widget.schedules.length == 1
                    ? 'Installment'
                    : '${widget.schedules.length} installments',
                amountDue.toCurrency(),
              ),
              for (final r in results)
                for (final line in r.lateness.penalties.lines)
                  _row(
                    '${line.penalty.name} · ${line.penalty.amountLabel} '
                    '× ${line.periods}',
                    line.amount.toCurrency(),
                    sub: true,
                  ),
              if (maxDaysLate > 0 && penaltyTotal == 0)
                _row(
                  loan.allowLatePayments
                      ? '$maxDaysLate days late · late payments allowed'
                      : '$maxDaysLate days late · no penalties on this loan',
                  '',
                  sub: true,
                ),
              const Divider(),
              _row('Total to collect', total.toCurrency(), bold: true),
            ],
          ),
        ),
        if (penaltyTotal > 0) ...[
          FormBuilderCheckbox(
            name: 'waive_penalty',
            initialValue: false,
            title: const Text('Waive penalties'),
            subtitle: const Text(
              'Records who waived and why on the installment.',
              style: TextStyle(fontSize: 10),
            ),
            activeColor: AppColors.black,
            checkColor: AppColors.white,
            onChanged: (value) => setState(() => _waive = value ?? false),
          ),
          if (_waive)
            KeyedSubtree(
              key: const Key('waive_reason_field'),
              child: AppWidgets.defaultFormBuilderTextField(
                name: 'waive_reason',
                label: 'Waive reason',
                validator: FormBuilderValidators.required(),
              ),
            ),
        ],
      ],
    );
  }

  Widget _row(
    String label,
    String value, {
    bool sub = false,
    bool bold = false,
  }) {
    final style = TextStyle(
      fontSize: sub ? 12 : 14,
      color: sub ? AppColors.lightBlack : AppColors.black,
      fontWeight: bold ? FontWeight.w700 : null,
    );

    return Padding(
      padding: EdgeInsets.only(top: 3, bottom: 3, left: sub ? 12 : 0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
