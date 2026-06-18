import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class LoanScheduleWidget extends StatelessWidget {
  const LoanScheduleWidget({
    required this.amortization,
    required this.schedules,
    required this.completeTerm,
    super.key,
    this.forDialogHeight,
    this.buildTable = false,
    this.tableHeight,
  });

  final double? forDialogHeight;
  final bool buildTable;

  /// When set, the schedule table is given this exact (bounded) height instead
  /// of an Expanded. Lets the widget live inside a scroll view (the table can't
  /// be Expanded there). Keeps the title, unlike [forDialogHeight].
  final double? tableHeight;
  final double amortization;
  final String completeTerm;
  final List<LoanSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (forDialogHeight == null) ...[
          Text(
            'Loan payment schedule',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: buildTable ? 16 : 24,
            ),
          ),
          const Gap(16),
        ],
        Text(
          'You need to pay ${amortization.toCurrency()} every $completeTerm',
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
        const Gap(24),
        const Text(
          'Schedule details',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(8),
        if (forDialogHeight != null)
          SizedBox(
            height: forDialogHeight,
            width: 500,
            child: _table(context),
          )
        else if (tableHeight != null)
          SizedBox(
            height: tableHeight,
            child: !buildTable ? _list() : _table(context),
          )
        else
          Expanded(
            child: !buildTable ? _list() : _table(context),
          ),
      ],
    );
  }

  Widget _list() {
    return ListView.separated(
      itemBuilder: (context, index) {
        return scheduleItem(
          context,
          schedule: schedules[index],
          index: index,
        );
      },
      separatorBuilder: (context, index) {
        return const Gap(0);
      },
      itemCount: schedules.length,
    );
  }

  Widget _table(BuildContext context) {
    return TableView.builder(
      cellBuilder: _buildCell,
      columnCount: 5,
      columnBuilder: _buildColumnSpan,
      rowCount: schedules.length + 1,
      // + 1 for header
      rowBuilder: (index) => _buildRowSpan(context, index),
    );
  }

  static Widget scheduleItem(
    BuildContext context, {
    required LoanSchedule schedule,
    int index = 0,
  }) {
    final trailingText = !schedule.isOpenTerm
        ? context.read<LoansBloc>().monthlyAmortization
        : schedule.interestCharge;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: () {},
      leading: Text('${index + 1}'),
      title: Text(schedule.dueAt.toDefaultDateFormatWithDay()),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Interest: ${schedule.interestPayment.toCurrency()}',
            style: const TextStyle(
              fontSize: 12,
            ),
          ),
          Text(
            'Principal: ${schedule.principalPayment.toCurrency()}',
            style: const TextStyle(
              fontSize: 12,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Text(trailingText.toCurrency()),
    );
  }

  TableViewCell _buildCell(BuildContext context, TableVicinity vicinity) {
    Widget defaultCellDisplay =
        Text('Tile c: ${vicinity.column}, r: ${vicinity.row}');

    if (vicinity.row == 0) {
      defaultCellDisplay = Text(
        Constants.loanScheduleHeaders[vicinity.column],
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    } else {
      final schedule = schedules[vicinity.row - 1];

      if (vicinity.column == 0) {
        defaultCellDisplay = Text(schedule.dueAt.toDefaultDateFormat());
      } else if (vicinity.column == 1) {
        defaultCellDisplay = Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            schedule.amortization.toCurrency(),
          ),
        );
      } else if (vicinity.column == 2) {
        defaultCellDisplay = Text(schedule.interestPayment.toCurrency());
      } else if (vicinity.column == 3) {
        defaultCellDisplay = Text(schedule.principalPayment.toCurrency());
      } else if (vicinity.column == 4) {
        defaultCellDisplay = Text(
          _statusLabel(schedule),
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    return TableViewCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: defaultCellDisplay,
      ),
    );
  }

  /// Borrower-facing status for a schedule row. Shows the real payment state
  /// (Payment submitted / Paid on time / Paid late); anything else (not_paid,
  /// or a loan-level status that leaked onto a persisted schedule) is presented
  /// as Not paid / Not paid (overdue) based on the due date. A rejected payment
  /// reverts the schedule to not_paid here (the borrower can resubmit) and is
  /// surfaced separately via the rejection notification.
  String _statusLabel(LoanSchedule schedule) {
    const realPaymentStatuses = {
      LoanStatus.payment_submitted,
      LoanStatus.paid_on_time,
      LoanStatus.paid_late,
    };
    if (realPaymentStatuses.contains(schedule.status)) {
      return schedule.status.label;
    }
    return schedule.dueAt.isBefore(DateTime.now())
        ? LoanStatus.not_paid_overdue.label
        : LoanStatus.not_paid.label;
  }

  TableSpan _buildColumnSpan(int index) {
    const decoration = TableSpanDecoration(border: TableSpanBorder());

    // Rebalanced for 5 columns (Date, Amortization, Interest, Principal,
    // Status) — the fractions must sum to 1.0. Status gets the widest slice so
    // labels like "Payment submitted" / "Not paid (overdue)" fit.
    final fraction = switch (index) {
      0 => 0.24, // Date
      1 => 0.16, // Amortization
      2 => 0.14, // Interest
      3 => 0.16, // Principal
      _ => 0.30, // Status
    };

    return TableSpan(
      foregroundDecoration: decoration,
      extent: FractionalTableSpanExtent(fraction),
    );
  }

  TableSpan _buildRowSpan(BuildContext context, int index) {
    const decoration = TableSpanDecoration();

    if (index == 0) {
      return const TableSpan(
        backgroundDecoration: decoration,
        extent: FixedTableSpanExtent(48),
      );
    }

    return TableSpan(
      backgroundDecoration: decoration,
      extent: const FixedTableSpanExtent(48),
      cursor: SystemMouseCursors.click,
      recognizerFactories: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (TapGestureRecognizer t) => t.onTap = () {
            debugPrint('Tap row $index');
          },
        ),
      },
      // onEnter: (_) {
      //   decoration = TableSpanDecoration(
      //     color: AppColors.white,
      //   );
      // }
    );
  }
}
