import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({
    super.key,
    this.loanId,
  });

  final String? loanId;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  @override
  void initState() {
    context.read<LoansBloc>().loadNext();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var showDetailContainer = true;

    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      showDetailContainer = false;
    }

    return BlocListener<LoansBloc, LoansState>(
      listener: (context, state) {
        // if (state.status == LoansStatus.loading) {
        //   if (state.isLoading) {
        //     AppWidgets.showDefaultLoadingDialog(context);
        //   } else {
        //     Navigator.of(context, rootNavigator: true).pop();
        //   }
        // }
      },
      child: AppWidgets.rootConstraints(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Loans',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(32),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: StreamBuilder(
                        stream: context.read<LoansBloc>().userLoanViews,
                        builder: (context, snapshot) {
                          if (snapshot.data == null) {
                            return Container();
                          }

                          final data = snapshot.data!;

                          return TableView.builder(
                            cellBuilder: (context, vicinity) {
                              return _buildCell(context, vicinity, data);
                            },
                            columnCount: 4,
                            columnBuilder: _buildColumnSpan,
                            rowCount: data.length + 1,
                            rowBuilder: (index) => _buildRowSpan(
                              context,
                              index,
                              data,
                            ),
                          );
                        },
                      ),
                    ),
                    if (showDetailContainer) ...[
                      const Gap(32),
                      Expanded(
                        child: widget.loanId != null
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(),
                                ),
                                child: LoanDetails(
                                  id: widget.loanId!,
                                ),
                              )
                            : DottedBorder(
                                borderType: BorderType.RRect,
                                radius: const Radius.circular(16),
                                strokeCap: StrokeCap.round,
                                dashPattern: const [
                                  8,
                                ],
                                strokeWidth: 1.3,
                                child: const Center(
                                  child: Text(
                                    'Select loan to view',
                                    style: TextStyle(
                                      fontSize: 32,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TableViewCell _buildCell(
    BuildContext context,
    TableVicinity vicinity,
    List<UserLoanView> userLoanViews,
  ) {
    Widget defaultCellDisplay =
        Text('Tile c: ${vicinity.column}, r: ${vicinity.row}');

    if (vicinity.row == 0) {
      defaultCellDisplay = Text(
        Constants.myLoansHeaders[vicinity.column],
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );
    } else {
      final userLoanView = userLoanViews[vicinity.row - 1];
      if (vicinity.column == 0) {
        defaultCellDisplay = Text(userLoanView.loanCreatedAt.toDefaultDateFormat());
      } else if (vicinity.column == 2) {
        defaultCellDisplay = Text(userLoanView.amount.toCurrency());
      } else if (vicinity.column == 3) {
        defaultCellDisplay = Text(userLoanView.loanStatus.label);
      } else if (vicinity.column == 1) {
        defaultCellDisplay = Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            userLoanView.companyName,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }

      if (vicinity.row < 3) {
        context
            .read<LoansBloc>()
            .loadNext(limit: vicinity.row + defaultDataLimit);
      }
    }

    return TableViewCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: defaultCellDisplay,
      ),
    );
  }

  TableSpan _buildColumnSpan(int index) {
    const decoration = TableSpanDecoration(
      border: TableSpanBorder(
          // leading: index == 0 ? BorderSide() : BorderSide.none,
          // trailing: index == 3 ? BorderSide() : BorderSide.none,
          ),
    );

    switch (index) {
      case 0:
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FixedTableSpanExtent(120),
          // recognizerFactories: <Type, GestureRecognizerFactory>{
          //   TapGestureRecognizer:
          //       GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          //     TapGestureRecognizer.new,
          //     (TapGestureRecognizer t) =>
          //         t.onTap = () => debugPrint('Tap column $index'),
          //   ),
          // },
        );
      case 1:
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FractionalTableSpanExtent(0.35),
        );
      case 2:
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FixedTableSpanExtent(120),
        );
      case 3:
        return const TableSpan(
          foregroundDecoration: decoration,
          extent: FixedTableSpanExtent(120),
        );
    }
    throw AssertionError(
      'This should be unreachable, as every index is accounted for in the '
      'switch clauses.',
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
            if (getScreenSize(context: context).index <=
                ScreenSize.medium.index) {
              GoRouter.of(context).goSafe(Paths.loansAction
                  .replaceAll(':action', userLoanViews[index - 1].loanId),);
            } else {
              GoRouter.of(context).goSafe(
                '${Paths.index}?sec=loans&id=${userLoanViews[index - 1].loanId}',
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
