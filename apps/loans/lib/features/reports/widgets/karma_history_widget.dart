import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/widgets/karma_history_choice_group.dart';
import 'package:loooans/features/reports/widgets/transactions_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';

class KarmaHistoryWidget extends StatelessWidget {
  const KarmaHistoryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(),
          const Gap(16),
          SizedBox(
            height: 142,
            child: _chart(),
          ),
          const Gap(32),
          Expanded(
            child: _transactions(),
          ),
        ],
      ),
    );
  }

  Widget _transactions() {
    return const TransactionsWidget();
  }

  static Widget titleAndChart() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _title(),
        const Gap(16),
        SizedBox(
          height: 142,
          child: _chart(),
        ),
      ],
    );
  }

  static Widget _title() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Karma history',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(16),
        KarmaHistoryChoiceGroup(
          onChoiceSelected: (choice) {
            debugPrint('choice: $choice');
          },
        ),
      ],
    );
  }

  static Widget _chart() {
    const showMinYPosition = -1.0;
    const showMaxYPosition = 1.0;

    final chart = LineChart(
      LineChartData(
        minY: -2,
        maxY: 2,
        maxX: 15,
        minX: -5,
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              getTitlesWidget: (value, meta) {
                return Text(
                  value == 1 ? 'One' : value.toString(),
                  style: const TextStyle(
                    color: AppColors.white,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if ([showMaxYPosition, showMinYPosition]
                        .singleWhereOrNull((pos) => pos == value) !=
                    null) {
                  return Text(
                    value.toString(),
                    style: const TextStyle(
                      color: AppColors.white,
                    ),
                  );
                }

                return Container();
              },
            ),
          ),
          topTitles: const AxisTitles(
            
          ),
          rightTitles: const AxisTitles(
            
          ),
        ),
        borderData: FlBorderData(
          border: const Border(
            left: BorderSide(
              color: AppColors.white,
            ),
            bottom: BorderSide(
              color: AppColors.white,
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              const FlSpot(-2, -1),
              const FlSpot(0, -1),
              const FlSpot(2, 0),
              const FlSpot(3, 1),
              const FlSpot(5, 1),
              const FlSpot(5, 1),
              const FlSpot(5, 1),
              const FlSpot(5, 1),
            ],
            color: AppColors.white,
          ),
        ],
      ),
    );
    return chart;
  }
}
