import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/widgets/capital_usage_widget.dart';
import 'package:loooans/features/reports/widgets/report_cards_widget.dart';
import 'package:loooans/features/reports/widgets/sales_product_chart_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class DashboardTopBodyAdmin extends StatelessWidget {
  const DashboardTopBodyAdmin({
    super.key,
    this.isReportSection = false,
  });

  final bool isReportSection;

  @override
  Widget build(BuildContext context) {
    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      return _bodyPortrait(context);
    }

    return _body(context);
  }

  Widget _bodyPortrait(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, index) {
        return switch (index) {
          0 => const ReportCardsWidget(applyPaddingHorizontal: true),
          1 => const SalesProductChartWidget(isCompact: true),
          2 => const CapitalUsageChartWidget(isCompact: true),
          _ => Container(
              height: 64,
              width: double.infinity,
              color: AppColors.black,
            ),
        };
      },
      // separatorBuilder: (context, index) {
      //   return Container();
      // },
      itemCount: 4,
    );
  }

  Widget _body(BuildContext context) {
    return AppWidgets.rootConstraints(
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Gap(16),
          Expanded(
            child: CapitalUsageChartWidget(),
          ),
          Gap(16),
          Expanded(
            child: SalesProductChartWidget(),
          ),
          Gap(16),
          Expanded(
            child: ReportCardsWidget(
              applyPaddingHorizontal: true,
            ),
          ),
        ],
      ),
    );
  }
}
