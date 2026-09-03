import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/services/cash_pool_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class CashPoolInformationWidget extends StatelessWidget {

  CashPoolInformationWidget({
    required this.userId, super.key,
  });
  final String userId;
  final cashPoolService = CashPoolService();

  ButtonOption? _selectedOption;

  @override
  Widget build(BuildContext context) {
    return _cashPoolInformation(context);
  }

  Widget _cashPoolInformation(BuildContext context) {
    // Compact/medium: no width for two columns, and the parent is a scrolling
    // column with no height to give, so the list sizes to its rows instead of
    // filling. Wide is the two-column Row it always was.
    final stacked =
        getScreenSize(context: context).index <= ScreenSize.medium.index;
    final wallet = _wallet(context, stacked: stacked);
    final transactions = _transactions(context, shrinkWrap: stacked);

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          wallet,
          const Gap(16),
          transactions,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: wallet),
        const Gap(16),
        Expanded(child: transactions),
      ],
    );
  }

  /// [stacked]: the options button goes under the title; a phone has no
  /// width for both on one line.
  Widget _wallet(BuildContext context, {required bool stacked}) {
    const title = Text(
      'Wallet',
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
    final actions = AppWidgets.defaultFilledButton(
      onPressed: () {
        if (_selectedOption?.value == 'bulk_add_cash_pool') {
          cashPoolService.handleBulkAddCashToPool(context);
          return;
        }

        cashPoolService.handleCashPoolOptions(
          context,
          userId: userId,
          selectedOption: _selectedOption,
        );
      },
      options: [
        ButtonOption(
          label: 'Add to cash pool',
          value: 'add_cash_pool',
        ),
        ButtonOption(
          label: 'Withdraw as change',
          value: 'change',
        ),
        ButtonOption(
          label: 'Add to savings',
          value: 'savings',
        ),
        ButtonOption(
          label: 'Bulk add to cash pool',
          value: 'bulk_add_cash_pool',
        ),
      ],
      onOptionSelected: (option) {
        _selectedOption = option;
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stacked) ...[
          title,
          const Gap(8),
          actions,
        ] else
          Row(
            children: [
              title,
              const Spacer(),
              actions,
            ],
          ),
        const Text(
            'This is where the record of how much was withdrawn from the client ATM and how much was acknowledged as payment for their loan.',),
        const Gap(24),
        // ... rest of the _cashPoolInformation widget
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.black,
            borderRadius: BorderRadius.circular(16),
          ),
          child: BlocBuilder<CashPoolBloc, CashPoolState>(
            builder: (context, state) {
              final display = context.read<CashPoolBloc>().cashPoolDisplay;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Takes the width so its labels can wrap; Balance
                  // stays pinned right, as the Spacer had it.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total cash pool',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.white,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          display.totalCashPool.toCurrency(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                        const Gap(16),
                        const Text(
                          'Total acknowledged',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.white,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          display.totalAcknowledged.toCurrency(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                        const Gap(16),
                        const Text(
                          'Withdrawn as change',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.white,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          display.change.toCurrency(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                        const Gap(16),
                        const Text(
                          'Savings',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.white,
                          ),
                        ),
                        const Gap(8),
                        Text(
                          display.savings.toCurrency(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Balance',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: AppColors.white,
                        ),
                      ),
                      const Gap(8),
                      Text(
                        display.balance.toCurrency(),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// [shrinkWrap]: the list takes its rows' height and leaves scrolling to
  /// the column around it; otherwise it fills the column and scrolls itself.
  Widget _transactions(BuildContext context, {required bool shrinkWrap}) {
    final list = StreamBuilder(
      stream:
          context.read<CashPoolBloc>().loadCashPoolList2(userId),
      // This lists transactions for the current user
      builder: (context, snapshot) {
        final data = snapshot.data ?? <CashPool>[];
        return ListView.separated(
          shrinkWrap: shrinkWrap,
          physics:
              shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          itemCount: data.length,
          itemBuilder: (context, index) {
            final item = data[index];

            return InkWell(
              onTap: item.status ==
                      CashPoolStatus.acknowledged_payment
                  ? () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(
                                'Cash pool transaction - ${item.createdAt.toDefaultDateFormatWithDayExtended()}',),
                            content: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 300,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      'Acknowledge payment of ${item.amount.toCurrency()} for ${item.loanId} loan.',),
                                  if (item.comment != null) ...[
                                    const Gap(16),
                                    Text.rich(
                                      TextSpan(
                                        text: 'Comment: ',
                                        style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w600,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: item.comment,
                                            style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              SizedBox(
                                width: double.infinity,
                                child:
                                    AppWidgets.defaultFilledButton(
                                  child: const Text('Close'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.status.label),
                        Text(
                          item.createdAt
                              .toDefaultDateFormatWithDayExtended(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(item.amount.toCurrency()),
                ],
              ),
            );
          },
          separatorBuilder: (context, state) {
            return Divider(
              height: 16,
              color: AppColors.black.withValues(alpha: 0.4),
            );
          },
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cash pool transactions',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const Gap(8),
        if (shrinkWrap) list else Expanded(child: list),
      ],
    );
  }
}
