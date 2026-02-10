import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/widgets/karma_gauge_widget.dart';
import 'package:loooans/features/reports/widgets/karma_history_widget.dart';
import 'package:loooans/features/reports/widgets/score_card_widget.dart';
import 'package:loooans/features/reports/widgets/transactions_widget.dart';
import 'package:loooans/features/users/widget/profile_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class DashboardTopBody extends StatelessWidget {
  const DashboardTopBody({
    super.key,
    this.isKarmaSection = false,
  });

  final bool isKarmaSection;

  @override
  Widget build(BuildContext context) {
    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      final width = MediaQuery.sizeOf(context).width;

      return _topBodyPortrait(
        forceExpand: width < 668,
        isKarmaSection: isKarmaSection,
      );
    }

    return _topBody();
  }

  Widget _topBody() {
    return AppWidgets.rootConstraints(
      child: Row(
        children: [
          const Expanded(
            child: KarmaGaugeWidget(expand: true),
          ),
          const Gap(48),
          Expanded(
            child: _topRightBody(),
          ),
        ],
      ),
    );
  }

  Widget _topBodyPortrait({
    bool forceExpand = false,
    bool isKarmaSection = false,
  }) {
    return AppWidgets.rootConstraints(
      child: ListView.separated(
        itemBuilder: (context, index) {
          return switch (index) {
            0 => KarmaGaugeWidget(
                expand: forceExpand,
                showCredit: isKarmaSection,
              ),
            1 => !isKarmaSection
                ? _topRightBody(
                    constrainWidth: true,
                    applyPaddingHorizontal: true,
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                    ),
                    child: ProfileWidget(),
                  ),
            2 => Container(
                color: AppColors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: KarmaHistoryWidget.titleAndChart(),
              ),
            3 => Container(
                padding: const EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: 8,
                ),
                color: AppColors.black,
                child: TransactionsWidget.header(
                  maxAxisSize: true,
                ),
              ),
            _ => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                color: AppColors.black,
                child: TransactionsWidget.transactionItem(isLast: index == 99),
              ),
          };
        },
        separatorBuilder: (context, index) {
          if (index <= 1) {
            return const Gap(24);
          }

          if (index == 2) {
            return Container();
          }

          return const ColoredBox(
            color: AppColors.black,
            child: Divider(
              color: AppColors.white,
            ),
          );
        },
        itemCount: 100,
      ),
    );
  }

  Widget _topRightBody({
    bool constrainWidth = false,
    bool applyPaddingHorizontal = false,
  }) {
    return Container(
      padding: applyPaddingHorizontal
          ? const EdgeInsets.symmetric(horizontal: 24)
          : const EdgeInsets.only(right: 24),
      constraints: BoxConstraints(
        maxWidth: !constrainWidth ? double.infinity : 600,
      ),
      child: StaggeredGrid.count(
        crossAxisCount: 2,
        crossAxisSpacing: 32,
        mainAxisSpacing: 16,
        children: [
          ScoreCardWidget(
            footerTitle: 'Active loan',
            content: 'IzzyLoans',
            subContent: '${25000.toCurrency()} @ 5% p.m for 12 months',
            headerIcon: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: AppColors.green1, shape: BoxShape.circle,),
              child: SvgPicture.asset(
                'svg/finance.svg'.assetSafe,
              ),
            ),
          ),
          ScoreCardWidget(
            footerTitle: 'Active loan',
            content: 'IzzyLoans',
            subContent: '${25000.toCurrency()} @ 5% p.m for 12 months',
            headerIcon: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.green1,
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'svg/finance.svg'.assetSafe,
              ),
            ),
          ),
          ScoreCardWidget(
            headerTitle: 'Total loans',
            onTap: () {
              debugPrint('hello');
            },
            content: 60000.toCurrency(),
            isContentMoney: true,
          ),
          ScoreCardWidget(
            headerTitle: 'Total payments',
            onTap: () {
              debugPrint('hello');
            },
            content: 56384.87.toCurrency(),
            isContentMoney: true,
          ),
        ],
      ),
    );
  }
}
