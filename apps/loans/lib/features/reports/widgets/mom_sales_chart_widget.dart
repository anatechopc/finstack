import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MomSalesChartWidget extends StatelessWidget {
  const MomSalesChartWidget({
    super.key,
    this.isCompact = false,
  });

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _momSales(context);
  }

  Widget _momSales(BuildContext context) {
    final reportsBloc = context.read<ReportsBloc>();

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 400,
        maxHeight: 400,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 40),
            child: Text(
              'Month over month Sales',
              style: TextStyle(fontSize: 18, color: AppColors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 40,
            ),
            child: BlocBuilder<ReportsBloc, ReportsState>(
              builder: (context, state) {
                return Text(
                  reportsBloc.getMomYearRangeTitle(),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.white.withValues(alpha: 0.6),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: context.read<ReportsBloc>().reportSummaryStream(),
              builder: (context, snapshot) {
                final summaryItemsWithLargest =
                    reportsBloc.getLastTotalSummaryItemsWithLargestCollection();
                final summaryItems =
                    summaryItemsWithLargest.items.entries.toList().reversed;
                final dates = summaryItemsWithLargest.dates;
                final largest = summaryItemsWithLargest.largest;
                return BarChart(
                  BarChartData(
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (
                          group,
                          groupIndex,
                          rod,
                          rodIndex,
                        ) {
                          return BarTooltipItem(
                            rod.toY.toCurrency(),
                            const TextStyle(),
                          );
                        },
                      ),
                    ),
                    barGroups: [
                      ...summaryItems.map((entry) {
                        final summary = entry.value;

                        return BarChartGroupData(
                          x: dates[entry.key]!,
                          // showingTooltipIndicators: [0, 1],
                          barRods: [
                            BarChartRodData(
                              toY: summary.totalCollections,
                              width: 50,
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              rodStackItems: [
                                BarChartRodStackItem(
                                  0,
                                  summary.totalInterestPayments,
                                  AppColors.chart6,
                                ),
                                BarChartRodStackItem(
                                  summary.totalInterestPayments +
                                      (summary.totalInterestPayments * 0.02),
                                  summary.totalCollections,
                                  AppColors.chart5,
                                ),
                              ],
                            ),
                          ],
                        );
                      }),
                    ],
                    maxY: largest,
                    gridData: const FlGridData(
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 100,
                          getTitlesWidget: (value, meta) {
                            var text = value.toStringAsFixed(0);

                            if (value >= 1000) {
                              text =
                                  '${(value / 1000).round().toStringAsFixed(0)}k';
                            }

                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                text,
                                style: const TextStyle(
                                  color: AppColors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              DateTime.fromMillisecondsSinceEpoch(value.toInt())
                                  .toDefaultDateMonthFormat(),
                              style: const TextStyle(
                                color: AppColors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Gap(16),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              children: [
                _legendItem(
                  color: AppColors.chart5,
                  title: 'Sales',
                ),
                const Gap(16),
                _legendItem(
                  color: AppColors.chart6,
                  title: 'Profit',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem({
    required Color color,
    required String title,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const Gap(8),
        Text(
          title,
          style: const TextStyle(color: AppColors.white),
        ),
      ],
    );
  }
}
