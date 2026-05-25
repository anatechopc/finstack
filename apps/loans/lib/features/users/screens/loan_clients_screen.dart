
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class LoanClientsScreen extends StatefulWidget {
  const LoanClientsScreen({
    super.key,
    this.loadAll = true,
    this.scrollController,
    this.loadAllColumns = false,
  });

  final bool loadAll;
  final ScrollController? scrollController;
  final bool loadAllColumns;

  @override
  State<StatefulWidget> createState() {
    return _LoanClientsScreenState();
  }
}

class _LoanClientsScreenState extends State<LoanClientsScreen> {
  @override
  void initState() {
    context.read<LoansBloc>().clientsLoadNext();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return SizedBox(
      height: !widget.loadAll ? 300 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(context, maxAxisSize: true),
          const Gap(16),
          Expanded(
            child: StreamBuilder(
              stream: context.read<LoansBloc>().userLoanViews,
              builder: (context, snapshot) {
                if (snapshot.data == null) {
                  return Container();
                }

                final data = snapshot.data!;
                var showData = data;
                // +1 for header
                var rowCount = data.length + 1;

                if (!widget.loadAll) {
                  // max of 5 items, +1 for header and + 1 for more button
                  rowCount = 5;

                  if (data.length <= 5) {
                    // do not show more button when <= 5
                    rowCount = data.length + 1;
                  } else {
                    rowCount += 2;
                    showData = data.sublist(0, 5);
                  }
                }

                if (!isCompactOrMedium) {
                  return TableView.builder(
                    cellBuilder: (context, vicinity) {
                      return _buildCell(context, vicinity, showData);
                    },
                    columnCount: !widget.loadAllColumns
                        ? Constants.loanClientsHeaders.length
                        : Constants.loanClientsCompleteHeaders.length,
                    columnBuilder: _buildColumnSpan,
                    rowCount: rowCount,
                    rowBuilder: (index) {
                      if  (index == data.length - 1) {
                        context.read<LoansBloc>().clientsLoadNext(
                          limit: data.length + defaultDataLimit,
                        );
                      }

                      return _buildRowSpan(
                        context,
                        index,
                        showData,
                      );
                    },
                  );
                }

                return ListView.separated(
                  itemBuilder: (context, index) {
                    if (!widget.loadAll && index == 5) {
                      return AppWidgets.defaultOutlinedButton(
                        foregroundColor: AppColors.white,
                        child: const Text(
                          'more',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.white,
                          ),
                        ),
                        onPressed: () {},
                      );
                    }

                    final userLoanView = data[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        GoRouter.of(context).goSafe(
                            Paths.clientsAction.replaceAll(
                              ':action',
                              userLoanView.userId,
                            ),
                            extra: {
                              'useLoanView': userLoanView,
                              'loanId': userLoanView.loanId,
                              'productId': userLoanView.productId,
                              'userId': userLoanView.userId,
                            },);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userLoanView.userFullName,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  // fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                userLoanView.loanCreatedAt
                                    .toDefaultDateFormat(),
                                style: TextStyle(
                                  color: AppColors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                userLoanView.loanDueAt != null
                                    ? 'Due on ${userLoanView.loanDueAt!.toDefaultDateFormat()}'
                                    : 'Open term',
                                style: TextStyle(
                                  color: AppColors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                userLoanView.loanStatus.label,
                                style: TextStyle(
                                  color: _getLoanStatusColor(
                                      userLoanView.loanStatus,),
                                ),
                              ),
                              Text(
                                userLoanView.amount.toCurrency(),
                                style: TextStyle(
                                  color: AppColors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                userLoanView.amortization.toCurrency(),
                                style: TextStyle(
                                  color: AppColors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const Gap(16);
                  },
                  // if not load add, 5 data and 1 button
                  itemCount: !widget.loadAll ? 6 : data.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget header(
    BuildContext context, {
    bool maxAxisSize = false,
  }) {
    return Row(
      mainAxisSize: !maxAxisSize ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: !maxAxisSize
          ? MainAxisAlignment.start
          : MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Loan clients',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const Gap(8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (![
              UserRole.customer,
              UserRole.teller,
              UserRole.reviewModerator,
            ].contains(AuthenticationService.instance.user.userRole)) ...[
              AppWidgets.defaultOutlinedButton(
                foregroundColor: AppColors.white,
                child: const Text('Add loan'),
                onPressed: () {
                  AppWidgets.showAddUserWidget(
                    context,
                    withLoanApplication: true,
                  );
                },
              ),
              const Gap(16),
            ],
            if (!SettingsService.instance.appUseClassicUI)
              if (!widget.loadAllColumns)
                InkWell(
                  onTap: () {
                    GoRouter.of(context).goSafe('${Paths.index}?sec=clients');
                  },
                  child: SvgPicture.asset(
                    'svg/icon_arrow_up.svg'.assetSafe,
                    colorFilter: const ColorFilter.mode(
                      AppColors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () {
                    GoRouter.of(context).goSafe(Paths.index);
                  },
                  child: SvgPicture.asset(
                    'svg/icon_arrow_down.svg'.assetSafe,
                    colorFilter: const ColorFilter.mode(
                      AppColors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  TableViewCell _buildCell(
    BuildContext context,
    TableVicinity vicinity,
    List<UserLoanView> userLoanViews,
  ) {
    Widget defaultCellDisplay = Container();

    if (!widget.loadAll && vicinity.row == userLoanViews.length + 1) {
      if (vicinity.column == 0) {
        defaultCellDisplay = AppWidgets.defaultOutlinedButton(
          foregroundColor: AppColors.white,
          child: const Text(
            'more',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.white,
            ),
          ),
          onPressed: () {},
        );
      }
    } else {
      if (vicinity.row == 0) {
        final cellHeaders = !widget.loadAllColumns
            ? Constants.loanClientsHeaders
            : Constants.loanClientsCompleteHeaders;
        defaultCellDisplay = Text(
          cellHeaders[vicinity.column],
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.white,
          ),
        );
      } else {
        final userLoanView = userLoanViews[vicinity.row - 1];
        if (!widget.loadAllColumns) {
          if (vicinity.column == 0) {
            defaultCellDisplay = Text(
              userLoanView.loanCreatedAt.toDefaultDateFormat(),
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 1) {
            defaultCellDisplay = Padding(
              padding: const EdgeInsets.only(right: 16),
              // child: Text(
              //   '${userLoanView.userFullName} (${userLoanView.loanType})',
              //   overflow: TextOverflow.ellipsis,
              //   style: const TextStyle(
              //     color: AppColors.white,
              //   ),
              // ),
              child: Text.rich(
                TextSpan(
                  text: userLoanView.userFullName,
                  style: GoogleFonts.urbanist(
                    color: AppColors.white,
                  ),
                  children: [
                    TextSpan(
                      text: ' (${userLoanView.loanType})',
                      style: GoogleFonts.urbanist(
                        color: AppColors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          } else if (vicinity.column == 2) {
            defaultCellDisplay = Text(
              userLoanView.amount.toCurrency(),
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 3) {
            defaultCellDisplay = Text(
              userLoanView.loanStatus.label,
              style: TextStyle(
                color: _getLoanStatusColor(userLoanView.loanStatus),
              ),
            );
          }
        } else {
          if (vicinity.column == 0) {
            defaultCellDisplay = Text(
              userLoanView.loanCreatedAt.toDefaultDateFormat(),
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 1) {
            defaultCellDisplay = Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                userLoanView.loanDueAt?.toDefaultDateFormat() ?? 'Open term',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                ),
              ),
            );
          } else if (vicinity.column == 2) {
            defaultCellDisplay = Text(
              userLoanView.loanType,
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 3) {
            defaultCellDisplay = Text(
              userLoanView.userFullName,
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 4) {
            defaultCellDisplay = Text(
              userLoanView.amount.toCurrency(),
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 5) {
            defaultCellDisplay = Text(
              userLoanView.amortization.toCurrency(),
              style: const TextStyle(
                color: AppColors.white,
              ),
            );
          } else if (vicinity.column == 6) {
            defaultCellDisplay = Text(
              userLoanView.loanStatus.label,
              style: TextStyle(
                color: _getLoanStatusColor(userLoanView.loanStatus),
              ),
            );
          }
        }
      }
    }

    return TableViewCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: defaultCellDisplay,
      ),
    );
  }

  Color _getLoanStatusColor(LoanStatus status) {
    return switch (status) {
      LoanStatus.paid_on_time ||
      LoanStatus.completed ||
      LoanStatus.approved =>
        AppColors.green2,
      LoanStatus.declined ||
      LoanStatus.not_paid ||
      LoanStatus.not_paid_overdue ||
      LoanStatus.bad_debt =>
        AppColors.red,
      LoanStatus.pending || LoanStatus.payment_submitted => AppColors.chart2_1,
      LoanStatus.paid_late => AppColors.ubOrange,
    };
  }

  TableSpan _buildColumnSpan(int index) {
    const decoration = TableSpanDecoration(
      border: TableSpanBorder(
          // leading: index == 0 ? BorderSide() : BorderSide.none,
          // trailing: index == 3 ? BorderSide() : BorderSide.none,
          ),
    );

    if (!widget.loadAllColumns) {
      if (index == 1) {
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FractionalSpanExtent(0.35),
        );
      }
    } else {
      if (index == 3) {
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FractionalSpanExtent(0.26),
        );
      }
    }

    if (!widget.loadAllColumns) {
      return const TableSpan(
        foregroundDecoration: decoration,
        extent: FractionalSpanExtent(0.25),
      );
    }

    return const TableSpan(
      foregroundDecoration: decoration,
      extent: FractionalSpanExtent(0.13),
    );
  }

  TableSpan _buildRowSpan(
    BuildContext context,
    int index,
    List<UserLoanView> userLoanViews,
  ) {
    const decoration = TableSpanDecoration();

    if (index == 0) {
      return const TableSpan(
        backgroundDecoration: decoration,
        extent: FixedTableSpanExtent(48),
      );
    } else if (!widget.loadAll && index == 2) {
      // NOTE: index 2 is the last item of the list.
      return const TableSpan(
        backgroundDecoration: decoration,
        extent: FixedTableSpanExtent(62),
      );
    }

    return TableSpan(
      backgroundDecoration: decoration,
      extent: const FixedTableSpanExtent(48),
      cursor: SystemMouseCursors.click,
      recognizerFactories: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (TapGestureRecognizer t) => t.onTap = () {
            // GoRouter.of(context).goSafe('${Paths.index}?sec=loans&id=123abc');
            if (getScreenSize(context: context).index <=
                ScreenSize.medium.index) {
              final userLoanView = userLoanViews[index - 1];
              GoRouter.of(context).goSafe(
                  Paths.clientsAction.replaceAll(
                    ':action',
                    userLoanView.userId,
                  ),
                  extra: {
                    'useLoanView': userLoanView,
                    'loanId': userLoanView.loanId,
                    'productId': userLoanView.productId,
                    'userId': userLoanView.userId,
                  },);
            } else {
              final userLoanView = userLoanViews[index - 1];
              AppWidgets.showLoanClientDetailsDialog(
                context,
                userId: userLoanView.userId,
                userLoanView: userLoanView,
                loanId: userLoanView.loanId,
                productId: userLoanView.productId,
              );
            }
          },
        ),
      },
      // onEnter: (_) {
      //   decoration = TableSpanDecoration(
      //     color: AppColors.white,
      //   );
      // }
    );
  }
}
