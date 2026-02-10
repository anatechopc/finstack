import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/features/reports/widgets/score_card_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class DashboardClassicScreen extends StatelessWidget {
  const DashboardClassicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppWidgets.rootConstraints(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _loans(context),
            const Gap(24),
            _scoreCards(context, headerTitle: 'Collections'),
            const Gap(24),
            _scoreCards(context, headerTitle: 'Releases'),
          ],
        ),
      ),
    );
  }

  Widget _headerTitle({required String title}) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _loans(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerTitle(title: 'Loans'),
        const Gap(16),
        BlocBuilder<ReportsBloc, ReportsState>(builder: (context, state) {
          final loanStatusCounts = context.read<ReportsBloc>().loanStatusCount;

          return Row(
            children: loanStatusCounts.entries.mapIndexed((index, entry) {
              var assetPath = 'svg/add.svg';

              if (entry.key == 'Approved') {
                assetPath = 'svg/approve_loan.svg';
              } else if (entry.key == 'Overdue') {
                assetPath = 'svg/cash.svg';
              } else if (entry.key == 'Declined') {
                assetPath = 'svg/close.svg';
              } else if (entry.key == 'Active') {
                assetPath = 'svg/settled_loan.svg';
              } else if (entry.key == 'Settled') {
                assetPath = 'svg/settled_loan.svg';
              }

              final widget = Expanded(
                child: ScoreCardWidget(
                  footerTitle: entry.key.capitalize(),
                  content: entry.value.toDefaultFormat(),
                  headerIcon: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      AppColors.black,
                      BlendMode.srcIn,
                    ),
                    child: SvgPicture.asset(
                      assetPath,
                      width: 24,
                    ),
                  ),
                ),
              );

              return [
                if (index > 0)
                  const Gap(16),
                widget,
              ];
            }).flattened.toList(),
            // children: [
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'New',
            //       content: '1',
            //       headerIcon: ColorFiltered(
            //         colorFilter: ColorFilter.mode(
            //           AppColors.black,
            //           BlendMode.srcIn,
            //         ),
            //         child: SvgPicture.asset(
            //           'svg/add.svg'.assetSafe,
            //           width: 24,
            //         ),
            //       ),
            //     ),
            //   ),
            //   const Gap(16),
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'Approved',
            //       content: '100',
            //       headerIcon: SvgPicture.asset(
            //         'svg/approve_loan.svg'.assetSafe,
            //         width: 24,
            //       ),
            //     ),
            //   ),
            //   const Gap(16),
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'Active',
            //       content: '3972',
            //       headerIcon: SvgPicture.asset(
            //         'svg/finance.svg'.assetSafe,
            //         width: 24,
            //       ),
            //     ),
            //   ),
            //   const Gap(16),
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'Overdue',
            //       content: '567',
            //       headerIcon: SvgPicture.asset(
            //         'svg/cash.svg'.assetSafe,
            //         width: 24,
            //       ),
            //     ),
            //   ),
            //   const Gap(16),
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'Settled',
            //       content: '11,5792',
            //       headerIcon: SvgPicture.asset(
            //         'svg/settled_loan.svg'.assetSafe,
            //         width: 24,
            //       ),
            //     ),
            //   ),
            //   const Gap(16),
            //   Expanded(
            //     child: ScoreCardWidget(
            //       footerTitle: 'Declined',
            //       content: '69',
            //       headerIcon: ColorFiltered(
            //         colorFilter: ColorFilter.mode(
            //           AppColors.black,
            //           BlendMode.srcIn,
            //         ),
            //         child: SvgPicture.asset(
            //           'svg/close.svg'.assetSafe,
            //           width: 24,
            //         ),
            //       ),
            //     ),
            //   ),
            // ],
          );
        },),
      ],
    );
  }

  Widget _scoreCards(
    BuildContext context, {
    required String headerTitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerTitle(title: headerTitle.capitalize()),
        const Gap(16),
        BlocBuilder<ReportsBloc, ReportsState>(
          builder: (context, state) {
            final reportsBloc = context.read<ReportsBloc>();
            final now = DateTime.now();
            final lastMonth = Jiffy.parseFromDateTime(now).subtract(months: 1);
            final yesterday = Jiffy.parseFromDateTime(now).subtract(days: 1);

            return Row(
              children: [
                Expanded(
                  child: ScoreCardWidget(
                    footerTitle: DateTime.now().toWesternDateFormat(),
                    headerTitle: 'Today',
                    content: reportsBloc.getContentFromTotalSummary(
                      dateTime: now,
                      keyFor: 'day',
                      getFor: headerTitle.toLowerCase(),
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: ScoreCardWidget(
                    footerTitle: yesterday.dateTime.toWesternDateFormat(),
                    headerTitle: 'Yesterday',
                    content: reportsBloc.getContentFromTotalSummary(
                      dateTime: yesterday.dateTime,
                      keyFor: 'day',
                      getFor: headerTitle.toLowerCase(),
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: ScoreCardWidget(
                    footerTitle: now.toWesternDateYearMonthFormat(),
                    headerTitle: 'This month',
                    content: reportsBloc.getContentFromTotalSummary(
                      dateTime: now,
                      getFor: headerTitle.toLowerCase(),
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: ScoreCardWidget(
                    footerTitle:
                        lastMonth.dateTime.toWesternDateYearMonthFormat(),
                    headerTitle: 'Last month',
                    content: reportsBloc.getContentFromTotalSummary(
                      dateTime: lastMonth.dateTime,
                      getFor: headerTitle.toLowerCase(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
