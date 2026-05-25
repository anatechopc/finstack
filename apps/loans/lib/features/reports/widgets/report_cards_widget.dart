import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/features/reports/widgets/score_card_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ReportCardsWidget extends StatelessWidget {
  const ReportCardsWidget({
    super.key,
    this.constrainWidth = false,
    this.applyPaddingHorizontal = false,
    this.fullCards = false,
  });

  final bool constrainWidth;
  final bool applyPaddingHorizontal;
  final bool fullCards;

  @override
  Widget build(BuildContext context) {
    return !fullCards
        ? _topRightBody(
            context,
            constrainWidth: constrainWidth,
            applyPaddingHorizontal: applyPaddingHorizontal,
          )
        : _reportFullCards(context);
  }

  Widget _topRightBody(
    BuildContext context, {
    bool constrainWidth = false,
    bool applyPaddingHorizontal = false,
  }) {
    return Container(
      padding: applyPaddingHorizontal
          ? const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
            )
          : EdgeInsets.zero,
      constraints: BoxConstraints(
        maxWidth: !constrainWidth ? double.infinity : 600,
      ),
      child: StreamBuilder(
        stream: context.read<ReportsBloc>().reportSummaryStream(),
        builder: (context, snapshot) {
          return StaggeredGrid.count(
            crossAxisCount: !fullCards ? 2 : 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              namedReportCards(context)['collections']!,
              namedReportCards(context)['net_gains']!,
              namedReportCards(context)['bad_debt']!,
              namedReportCards(context)['active_clients']!,
              namedReportCards(context)['receivables']!,
              AppWidgets.defaultOutlinedButton(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text('Check full reports'),
                    ),
                    const Gap(8),
                    SvgPicture.asset(
                      'svg/icon_arrow_up.svg'.assetSafe,
                      width: 24,
                      colorFilter: const ColorFilter.mode(
                        AppColors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  GoRouter.of(context).goSafe('${Paths.index}?sec=reports');
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _reportFullCards(
    BuildContext context, {
    bool constrainWidth = false,
    bool applyPaddingHorizontal = false,
  }) {
    return Container(
      padding: applyPaddingHorizontal
          ? const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
            )
          : const EdgeInsets.only(right: 24),
      constraints: BoxConstraints(
        maxWidth: !constrainWidth ? double.infinity : 600,
      ),
      child: StreamBuilder(
        stream: context.read<ReportsBloc>().reportSummaryStream(),
        builder: (context, snapshot) {
          return StaggeredGrid.extent(
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            maxCrossAxisExtent: 300,
            children: namedReportCards(context).values.toList(),
          );
        },
      ),
    );
  }

  Map<String, Widget> namedReportCards(BuildContext context) {
    final reportsBloc = context.read<ReportsBloc>();
    final loanStatusCount = reportsBloc.loanStatusCount;
    final sales = reportsBloc.sales;
    final capitalUsage = reportsBloc.capitalUsage;
    final receivables = reportsBloc.receivables;
    final capitalDataItems = reportsBloc.capitalDataItems;
    return {
      'active_clients': StreamBuilder(
        stream: context.read<ReportsBloc>().loanStatusCountStream(),
        builder: (context, snapshot) {
          return ScoreCardWidget(
            footerTitle: 'Active clients',
            content: loanStatusCount['Active']?.toString() ?? '0',
            contentCentered: false,
            footerIcon: IconButton(
              onPressed: () {
                _showInfoDialog(
                  context,
                  title: 'Active clients',
                  description:
                      'As of the moment, you have ${loanStatusCount['Active']?.toString() ?? '0'} active clients',
                  question: 'How active clients are determined',
                  explanation:
                      '''
Active client refers to an individual who borrowed money from your business and is still actively paying the amortization

Active clients are determined based on active loans. Loans that are open and active collection is on going.

Closed (loan finished) accounts are not included in the counting.''',
                );
              },
              icon: const Icon(Icons.info_outline_rounded),
            ),
          );
        },
      ),
      'collections': ScoreCardWidget(
        footerTitle: 'Collections',
        content: (sales?.totalCollections ?? 0).toCurrency(),
        isContentMoney: true,
        largeMoneyContent: true,
        contentCentered: false,
        footerIcon: IconButton(
          onPressed: () {
            _showInfoDialog(
              context,
              title: 'Total collections',
              description:
                  'As of the moment, you have collected amount in total of ${(sales?.totalCollections ?? 0).toCurrency()}',
              question: 'How total collections are determined',
              explanation:
                  '''
Collections are referred to the amount of money you are able to collect from the clients

Total collections are determined based on the sum of all the loan amortization collected. The total includes the capital plus the profit gained from the borrower.''',
            );
          },
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ),
      'total_capital': ScoreCardWidget(
        footerTitle: 'Total capital',
        content: (capitalUsage?.totalCapital ?? 0).toCurrency(),
        isContentMoney: true,
        largeMoneyContent: true,
        contentCentered: false,
        footerIcon: IconButton(
          onPressed: () {
            _showInfoDialog(
              context,
              title: 'Total capital',
              description:
                  'As of the moment, you have a total capital of ${(capitalUsage?.totalCapital ?? 0).toCurrency()}',
              question: 'How total capital are determined',
              explanation:
                  '''
Capital is referred to the amount of money you are putting to run your loan business

Total capital is determined by how much capital you have  added to the business.

Please note that the total capital also serves as a limit on how much you, as a loan provider can lend and how many people can borrow from your loan business.''',
              // TODO(deibeeed): implement this, https://github.com/anatechopc/loooans/issues/60
              extraContent: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total capital breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const Gap(8),
                  const Row(
                    children: [
                      Expanded(
                        child: Text('Date added'),
                      ),
                      Expanded(
                        child: Text('Amount'),
                      ),
                    ],
                  ),
                  const Gap(8),
                  if (capitalDataItems.isNotEmpty)
                    ...capitalDataItems.mapIndexed((index, entry) {
                      return [
                        if (index != 0)
                          const Gap(8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(entry.createdAt.toDefaultDateFormat()),
                            ),
                            Expanded(
                              child: Text(entry.amount.toCurrency()),
                            ),
                          ],
                        ),
                      ];
                    }).flattened,
                ],
              ),
            );
          },
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ),
      'net_gains': ScoreCardWidget(
        footerTitle: 'Net gains',
        content: (sales?.totalInterestPayments ?? 0).toCurrency(),
        largeMoneyContent: true,
        isContentMoney: true,
        contentCentered: false,
        footerIcon: IconButton(
          onPressed: () {
            final summaryItemsWithLargest =
                reportsBloc.getLastTotalSummaryItemsWithLargestCollection();
            final summaryItems =
                summaryItemsWithLargest.items.entries.toList().reversed;
            final dates = summaryItemsWithLargest.dates;

            _showInfoDialog(
              context,
              title: 'Net gains',
              description:
                  'As of the moment, your total gains or profit is ${(sales?.totalInterestPayments ?? 0).toCurrency()}',
              question: 'How net gains is determined',
              explanation:
                  '''
Net gains refers to the income you gained after deducting the loan amount of the client.

Net gains is determined by computing total collections deducted by the total amount borrowed by your clients. 

Please note that for unpaid clients amortization, since the payment has not yet collected, it will not be counted in the total collections. Also, net gains or profit might not be your actual profit since the system has not accounted your operating expenses and so on.''',
              extraContent: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Net gains Month over month',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const Gap(8),
                  const Row(
                    children: [
                      Expanded(
                        child: Text('Month'),
                      ),
                      Expanded(
                        child: Text('Gains'),
                      ),
                    ],
                  ),
                  const Gap(8),
                  ...summaryItems.map((entry) {
                    final summary = entry.value;
                    return [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateTime.fromMillisecondsSinceEpoch(
                                dates[entry.key]!,
                              ).toDefaultDateYearMonthFormat(),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              summary.totalInterestPayments.toCurrency(),
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                    ];
                  }).flattened,
                ],
              ),
            );
          },
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ),
      // activate reviews https://github.com/anatechopc/loooans/issues/47
      // 'reviews': ScoreCardWidget(
      //   footerTitle: 'Reviews',
      //   contentWidget: Row(
      //     children: [
      //       const Icon(
      //         Icons.star_rounded,
      //         size: 24,
      //       ),
      //       RichText(
      //         text: TextSpan(children: [
      //           TextSpan(
      //             text: '5 ',
      //             style: GoogleFonts.urbanist(
      //               color: AppColors.black,
      //               fontSize: 32,
      //               fontWeight: FontWeight.w500,
      //             ),
      //           ),
      //           TextSpan(
      //             text: '(100)',
      //             style: GoogleFonts.urbanist(
      //               fontSize: 18,
      //               color: AppColors.black.withValues(alpha: 0.6),
      //             ),
      //           ),
      //         ]),
      //       ),
      //     ],
      //   ),
      //   contentCentered: false,
      //   footerIcon: IconButton(
      //     onPressed: () {},
      //     icon: const Icon(Icons.info_outline_rounded),
      //   ),
      // ),
      'receivables': ScoreCardWidget(
        footerTitle: 'Receivables',
        content: (receivables ?? 0).toCurrency(),
        isContentMoney: true,
        contentCentered: false,
        largeMoneyContent: true,
        footerIcon: IconButton(
          onPressed: () {
            _showInfoDialog(
              context,
              title: 'Receivables',
              description:
                  'As of the moment, you have total payment receivables of ${(receivables ?? 0).toCurrency()}',
              question: 'How receivables are determined',
              explanation:
                  '''
Receivables are amortization payments that you are expecting to receive. This is also called account receivables.

Receivables are determined by getting the total uncollected amortization from your clients.

${AuthenticationService.instance.hasCompany && AuthenticationService.instance.company.managementType == CompanyManagementType.selfManaged ? "For open term loans, receivable computation does not account for the duration of the loan." : ""}

Please note that for closed (bad debt) status, these accounts will not be included in the computation.
''',
            );
          },
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ),
      'bad_debt': ScoreCardWidget(
        footerTitle: 'Bad debt',
        content: (capitalUsage?.totalBadDebts ?? 0).toCurrency(),
        isContentMoney: true,
        contentCentered: false,
        largeMoneyContent: true,
        footerIcon: IconButton(
          onPressed: () {
            _showInfoDialog(
              context,
              title: 'Bad debt',
              description:
                  'As of the moment, you have bad debt in total of ${(capitalUsage?.totalBadDebts ?? 0).toCurrency()}',
              question: 'How bad debt are determined',
              explanation:
                  '''
Bad debts are accounts that was closed because client is unable to pay for the remaining amortization.

Bad debt are determined by getting the total sum of closed (bad debt) accounts.''',
            );
          },
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ),
      // ScoreCardWidget(
      //   footerTitle: 'Collection score',
      //   content: '100',
      //   contentCentered: false,
      //   footerIcon: IconButton(
      //     onPressed: () {},
      //     icon: const Icon(Icons.info_outline_rounded),
      //   ),
      // ),
    };
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String description,
    required String question,
    required String explanation,
    Widget? extraContent,
    List<Widget>? extraActions,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          contentPadding: const EdgeInsets.all(24),
          scrollable: extraContent != null,
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const Gap(16),
                Text(
                  description,
                  style: const TextStyle(),
                ),
                const Gap(16),
                Text(
                  question,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const Gap(16),
                Text(
                  explanation,
                ),
                if (extraContent != null) ...[
                  const Gap(16),
                  extraContent,
                ],
              ],
            ),
          ),
          actions: [
            if (extraActions != null && extraActions.isNotEmpty) ...[
              for (final action in extraActions) ...[
                SizedBox(
                  width: double.infinity,
                  child: action,
                ),
                const SizedBox(
                  width: 16,
                ),
              ],
            ],
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Close'),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
