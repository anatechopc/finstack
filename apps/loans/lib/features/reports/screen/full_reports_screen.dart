import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/widgets/capital_usage_widget.dart';
import 'package:loooans/features/reports/widgets/mom_sales_chart_widget.dart';
import 'package:loooans/features/reports/widgets/report_cards_widget.dart';
import 'package:loooans/features/reports/widgets/sales_product_chart_widget.dart';
import 'package:loooans/features/users/screens/loan_clients_screen.dart';

class FullReportsScreen extends StatelessWidget {
  const FullReportsScreen({
    super.key,
    this.scrollController,
  });

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    if (screenSize.width < 840) {
      return _bodyPortrait(context);
    }

    if (screenSize.width <= 1092) {
      return _body2(context);
    }

    return _body(context);
  }

  Widget _body(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      itemBuilder: (BuildContext context, int index) {
        return switch (index) {
          0 => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CapitalUsageChartWidget(),
                ),
                Expanded(
                  child: MomSalesChartWidget(),
                ),
                Expanded(
                  child: SalesProductChartWidget(),
                ),
              ],
            ),
          1 => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: ReportCardsWidget(
                    fullCards: true,
                  ),
                ),
                Gap(16),
                Expanded(
                  child: LoanClientsScreen(
                    loadAll: false,
                  ),
                ),
              ],
            ),
          _ => Container(),
        };
      },
      separatorBuilder: (BuildContext context, int index) {
        return const Gap(24);
      },
      itemCount: 2,
    );
  }

  Widget _body2(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      itemBuilder: (BuildContext context, int index) {
        return switch (index) {
          0 => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CapitalUsageChartWidget(),
                ),
                Expanded(
                  child: MomSalesChartWidget(),
                ),
              ],
            ),
          1 => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SalesProductChartWidget(),
                      Gap(24),
                      SizedBox(
                        height: 500,
                        child: LoanClientsScreen(
                          loadAll: false,
                        ),
                      ),
                    ],
                  ),
                ),
                Gap(24),
                Expanded(
                  child: ReportCardsWidget(
                    fullCards: true,
                  ),
                ),
              ],
            ),
          _ => Container(),
        };
      },
      separatorBuilder: (BuildContext context, int index) {
        return const Gap(24);
      },
      itemCount: 2,
    );
  }

  Widget _bodyPortrait(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      itemBuilder: (context, index) {
        return switch (index) {
          0 => const CapitalUsageChartWidget(),
          1 => const MomSalesChartWidget(),
          2 => const SalesProductChartWidget(),
          3 => const ReportCardsWidget(
              fullCards: true,
            ),
          4 => const LoanClientsScreen(
              loadAll: false,
            ),
          _ => Container(),
        };
      },
      separatorBuilder: (context, index) {
        return const Gap(16);
      },
      itemCount: 5,
    );
  }
}
