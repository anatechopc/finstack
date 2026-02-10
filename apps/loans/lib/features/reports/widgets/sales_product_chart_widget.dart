import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';

class SalesProductChartWidget extends StatelessWidget {
  const SalesProductChartWidget({
    super.key,
    this.isCompact = false,
  });

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _salesByProductChart(context, isCompact: isCompact);
  }

  Widget _salesByProductChart(
    BuildContext context, {
    bool isCompact = false,
  }) {
    final reportsBloc = context.read<ReportsBloc>();
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 380,
        maxHeight: 320,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: !isCompact ? BorderRadius.circular(16) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.zero,
            child: Text(
              'Sales by product',
              style: TextStyle(fontSize: 18, color: AppColors.white),
            ),
          ),
          const Gap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox.square(
                  dimension: 200,
                  child: StreamBuilder(
                    stream: context.read<ReportsBloc>().reportSummaryStream(),
                    builder: (context, state) {
                      return PieChart(
                        PieChartData(
                          centerSpaceRadius: 0,
                          sections: [
                            if (reportsBloc.products != null)
                              ...reportsBloc.products!.entries.indexed
                                  .map((entry) {
                                final index = entry.$1;
                                const colorList = AppColors.salesItemColorsList;
                                var colorIndex = index;

                                if (colorIndex > colorList.length - 1) {
                                  final divisible = index % colorList.length;
                                  colorIndex = divisible;
                                }

                                return PieChartSectionData(
                                  color:
                                      AppColors.salesItemColorsList[colorIndex],
                                  value: entry.$2.value.totalAmountReleased,
                                  radius: 80,
                                  titlePositionPercentageOffset: 2,
                                  title: '',
                                );
                              })
                            else
                              PieChartSectionData(
                                color: AppColors.chartEmpty,
                                value: 1,
                                radius: 80,
                                titlePositionPercentageOffset: 2,
                                title: '',
                              ),

                            // PieChartSectionData(
                            //   color: AppColors.chartEmpty,
                            //   value: 5,
                            //   titlePositionPercentageOffset: 1.5,
                            //   title: '',
                            //   radius: 80,
                            //   // titleStyle: const TextStyle(
                            //   //   color: Colors.black,
                            //   // ),
                            // ),
                            // PieChartSectionData(
                            //   color: AppColors.chart1_1,
                            //   value: 25,
                            //   titlePositionPercentageOffset: 2,
                            //   title: '',
                            //   radius: 80,
                            // ),
                            // PieChartSectionData(
                            //   color: AppColors.chart2_1,
                            //   value: 25,
                            //   titlePositionPercentageOffset: 1.5,
                            //   title: '',
                            //   radius: 80,
                            //   // titleStyle: const TextStyle(
                            //   //   color: Colors.black,
                            //   // ),
                            // ),
                            // PieChartSectionData(
                            //   color: AppColors.chart5,
                            //   value: 25,
                            //   titlePositionPercentageOffset: 1.5,
                            //   title: '',
                            //   radius: 80,
                            //   // titleStyle: const TextStyle(
                            //   //   color: Colors.black,
                            //   // ),
                            // ),
                            // PieChartSectionData(
                            //   color: AppColors.chart6,
                            //   value: 15,
                            //   titlePositionPercentageOffset: 1.5,
                            //   title: '',
                            //   radius: 80,
                            //   // titleStyle: const TextStyle(
                            //   //   color: Colors.black,
                            //   // ),
                            // ),
                          ],
                          pieTouchData: PieTouchData(
                            touchCallback: (event, touchResponse) {},
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Gap(16),
              Expanded(
                child: _salesProductLegend(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _salesProductLegend() {
    return BlocBuilder<ReportsBloc, ReportsState>(
      builder: (context, state) {
        final reportsBloc = context.read<ReportsBloc>();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reportsBloc.products != null)
              ...reportsBloc.products!.entries.indexed.map((entry) {
                final index = entry.$1;
                const colorList = AppColors.salesItemColorsList;
                var colorIndex = index;

                if (colorIndex > colorList.length - 1) {
                  final divisible = index % colorList.length;
                  colorIndex = divisible;
                }

                return [
                  _salesProductLegendItem(
                    color: AppColors.salesItemColorsList[colorIndex],
                    title: entry.$2.key,
                  ),
                  if (index < reportsBloc.products!.length - 1) const Gap(8),
                ];
              }).flattened
            else
              _salesProductLegendItem(
                color: AppColors.chartEmpty,
                title: 'No data',
              ),
          ],
        );
      },
    );
  }

  Widget _salesProductLegendItem({
    required Color color,
    required String title,
  }) {
    return Row(
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
