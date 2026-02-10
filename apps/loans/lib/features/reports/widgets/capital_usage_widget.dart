import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class CapitalUsageChartWidget extends StatelessWidget {
  const CapitalUsageChartWidget({
    super.key,
    this.isCompact = false,
  });

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _capitalUsageChart(
      context,
      isCompact: isCompact,
    );
  }

  Widget _capitalUsageChart(
    BuildContext context, {
    bool isCompact = false,
  }) {
    final reportsBloc = context.read<ReportsBloc>();
    const maxWidth = 460.0;

    return Container(
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: 500,
      ),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: !isCompact ? BorderRadius.circular(16) : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth - 48;

          return StreamBuilder(stream: context.read<ReportsBloc>().reportSummaryStream(),
            builder: (context, snapshot) {
              var totalCapital = 0.0;
              var totalAmountUsed = 0.0;

              if (reportsBloc.capitalUsage != null) {
                totalCapital = reportsBloc.capitalUsage!.totalCapital;
              }

              if (reportsBloc.sales != null) {
                totalAmountUsed = reportsBloc.sales!.totalAmountReleased;
              }

              var percentageUsed = (totalAmountUsed / totalCapital) * 100;

              if (percentageUsed.isNaN) {
                percentageUsed = 0;
              }

              var remainingCapital = totalCapital - totalAmountUsed;

              if (remainingCapital < 0) {
                remainingCapital = 0;
              } else {
                remainingCapital = 1;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Capital usage',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.white,
                              ),
                            ),
                            const Gap(16),
                            AppWidgets.defaultAmountWidget(
                              totalAmountUsed.toCurrency(),
                              fontSize: 28,
                              subFontSize: 18,
                              fontColor: AppColors.white,
                              fontThick: false,
                            ),
                            Text(
                              'of ${totalCapital.toCurrency()}',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox.square(
                        dimension: 144,
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${percentageUsed.toDefaultFormat()}%',
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 22,
                                    ),
                                  ),
                                  Text(
                                    'used',
                                    style: TextStyle(
                                      color: AppColors.white.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox.square(
                              dimension: 144,
                              child: PieChart(
                                PieChartData(
                                  sections: [
                                    PieChartSectionData(
                                      color: AppColors.chartEmpty,
                                      value: remainingCapital,
                                      radius: 12,
                                      titlePositionPercentageOffset: 1.5,
                                      title: '',
                                      // titleStyle: const TextStyle(
                                      //   color: Colors.black,
                                      // ),
                                    ),
                                    if (reportsBloc.products != null)
                                      ...reportsBloc.products!.entries.indexed
                                          .map((entry) {
                                        final index = entry.$1;
                                        const colorList = AppColors
                                            .capitalUsageItemColorsList;
                                        var colorIndex = index;

                                        if (colorIndex > colorList.length - 1) {
                                          final divisible =
                                              index % colorList.length;
                                          colorIndex = divisible;
                                        }

                                        return PieChartSectionData(
                                          color: AppColors
                                                  .capitalUsageItemColorsList[
                                              colorIndex],
                                          value: entry
                                              .$2.value.totalAmountReleased,
                                          radius: 12,
                                          titlePositionPercentageOffset: 2,
                                          title: '',
                                        );
                                      }),
                                  ],
                                  pieTouchData: PieTouchData(
                                    touchCallback: (event, touchResponse) {},
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  if (reportsBloc.products != null)
                    ...reportsBloc.products!.entries.indexed.map((entry) {
                      final index = entry.$1;
                      final productTotals = entry.$2.value;
                      const colorList = AppColors.capitalUsageItemColorsList;
                      var colorIndex = index;

                      if (colorIndex > colorList.length - 1) {
                        final divisible = index % colorList.length;
                        colorIndex = divisible;
                      }

                      final percent =
                          productTotals.totalAmountReleased / totalCapital;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _pseudoBar(
                            title: entry.$2.key,
                            detail: '${(percent * 100).toDefaultFormat()}%',
                            width: barWidth * percent,
                            color: AppColors
                                .capitalUsageItemColorsList[colorIndex],
                          ),
                          if (index < reportsBloc.products!.length - 1)
                            const Gap(16),
                        ],
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _pseudoBar({
    required String title,
    required String detail,
    required double width,
    Color color = AppColors.chart1,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
              ),
            ),
            Text(
              detail,
              style: TextStyle(
                color: AppColors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
        const Gap(16),
        SizedBox(
          height: 8,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  width: 32,
                  decoration: BoxDecoration(
                    color: AppColors.chartEmpty,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
