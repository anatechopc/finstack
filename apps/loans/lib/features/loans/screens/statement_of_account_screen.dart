import 'package:company_repository/company_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loan_settlement_bloc.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/features/reports/models/soa_model.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class StatementOfAccountScreen extends StatefulWidget {
  const StatementOfAccountScreen({
    required this.loanId, super.key,
  });

  final String loanId;

  @override
  State<StatementOfAccountScreen> createState() =>
      _StatementOfAccountScreenState();
}

class _StatementOfAccountScreenState extends State<StatementOfAccountScreen> {
  int _deductionBuildCount = 0;
  int _additionalChargesBuildCount = 0;

  @override
  void initState() {
    super.initState();
    context.read<ReportsBloc>().generateSoa(
          widget.loanId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoanSettlementBloc, LoanSettlementState>(
      listener: (context, state) {
        if (state.status == LoanSettlementStatus.loading) {
          if (state.isLoading) {
            AppWidgets.showDefaultLoadingDialog(context);
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } else if (state.status == LoanSettlementStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message ?? 'Unable to settle loan account'),),);
        } else if (state.status == LoanSettlementStatus.success) {
          if (state.message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message!)));
          }

          Navigator.of(context, rootNavigator: true).pop();

          if (state.closeDialog) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } else if (state.status == LoanSettlementStatus.confirmSettlement) {
          if (state.remainingBalance == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state.message ??
                    'Unable to settle loan account. Remaining balance cannot be calculated. Please try again later.',),),);
            return;
          }

          _showRemainingBalanceConfirmationDialog(
            context,
            remainingBalance: state.remainingBalance!,
          );
        }
      },
      child: BlocBuilder<ReportsBloc, ReportsState>(
        builder: (context, state) {
          if (state.status.index <= ReportStateStatus.loading.index) {
            return const Center(
              child: SizedBox.square(
                dimension: 56,
                child: CircularProgressIndicator(
                  color: AppColors.black,
                ),
              ),
            );
          }

          return _body(context);
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Statement of Account',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 24,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Text(
            'As of ${DateTime.now().toWesternDateFormatWithDay()}',
            textAlign: TextAlign.center,
          ),
        ),
        BlocBuilder<ReportsBloc, ReportsState>(
          buildWhen: (prev, next) {
            return next.status == ReportStateStatus.soaGeneratedRefresh;
          },
          builder: (context, state) {
            final soaModel = context.read<ReportsBloc>().soaModel;

            if (state.status != ReportStateStatus.soaGeneratedRefresh ||
                soaModel == null) {
              return Container();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth * 0.5,
                      child: Row(
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * 0.14,
                            child: Text(
                              'Name'.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(soaModel.fullName),
                        ],
                      ),
                    );
                  },
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth * 0.5,
                      child: Row(
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * 0.14,
                            child: Text(
                              'Interest rate'.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text('${soaModel.interest}% / ${soaModel.term}'),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        const Gap(24),
        Expanded(
          child: _table(context),
        ),
        Row(
          children: [
            Expanded(
              child: AppWidgets.defaultFilledButton(
                child: const Text(
                  'Settle account',
                  style: TextStyle(
                    color: AppColors.green1,
                  ),
                ),
                onPressed: () {
                  final soaModel = context.read<ReportsBloc>().soaModel;

                  if (soaModel != null) {
                    context.read<LoanSettlementBloc>().settleLoanAccount(
                          userId: soaModel.userId,
                          loanId: widget.loanId,
                        );
                  }
                },
              ),
            ),
            const Gap(16),
            Expanded(
              child: AppWidgets.defaultOutlinedButton(
                child: const Text('Print'),
                onPressed: () {
                  final soaModel = context.read<ReportsBloc>().soaModel;

                  if (soaModel != null) {
                    Company? company;

                    if (AuthenticationService.instance.hasCompany) {
                      company = AuthenticationService.instance.company;
                    }

                    PdfGenerator.generatePdfSoa(
                      soaModel: soaModel,
                      company: company,
                      companyAddress: AuthenticationService.instance.address,
                    );

                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No statement of account selected'),),);
                },
              ),
            ),
            const Gap(16),
            Expanded(
              child: AppWidgets.defaultOutlinedButton(
                child: const Text('Close'),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showRemainingBalanceConfirmationDialog(
    BuildContext context, {
    required double remainingBalance,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm remaining balance'),
          content: SizedBox(
            width: 500,
            child: Text.rich(
              TextSpan(
                text: 'The remaining balance is\n',
                children: [
                  TextSpan(
                    text: remainingBalance.toCurrency(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(
                      text:
                          '\n\nBy continuing, you have confirmed that the remaining balance has been paid and that, you have received the remaining balance payment.',),
                ],
              ),
            ),
          ),
          actionsOverflowButtonSpacing: 16,
          actions: [
            AppWidgets.defaultFilledButton(
              child: const Text('Confirm'),
              onPressed: () {
                final soaModel = context.read<ReportsBloc>().soaModel;
                if (soaModel == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No statement of account selected'),
                    ),
                  );
                  return;
                }

                context.read<LoanSettlementBloc>().confirmLoanAccountSettlement(
                      userId: soaModel.userId,
                      loanId: widget.loanId,
                    );
              },
            ),
            AppWidgets.defaultOutlinedButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _table(BuildContext context) {
    return BlocBuilder<ReportsBloc, ReportsState>(
      buildWhen: (prev, next) {
        return next.status == ReportStateStatus.soaGeneratedRefresh;
      },
      builder: (context, state) {
        final soaModel = context.read<ReportsBloc>().soaModel;
        if (state.status != ReportStateStatus.soaGeneratedRefresh ||
            soaModel == null) {
          return Container();
        }

        // initialize buildCounts
        _deductionBuildCount = 0;
        _additionalChargesBuildCount = 0;

        return TableView.builder(
          cellBuilder: (context, vicinity) {
            return _buildCell(
              context,
              vicinity,
              soaModel,
            );
          },
          columnCount: Constants.statementOfAccountHeaders.length,
          columnBuilder: _buildColumnSpan,
          // + 1 for header
          rowCount: soaModel.size + 1,
          rowBuilder: (index) => _buildRowSpan(
            context,
            index,
            soaModel,
          ),
        );
      },
    );
  }

  TableViewCell _buildCell(
    BuildContext context,
    TableVicinity vicinity,
    SOAModel soaModel,
  ) {
    final column = vicinity.column;
    int? columnMergeStart;
    int? columnMergeSpan;

    Widget defaultCellDisplay = const Text('');

    Widget wrapPadding(Widget child) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: child,
      );
    }

    Widget wrapTopBottomBorder(
      Widget child, {
      bool topOnly = false,
    }) {
      return Container(
        padding: topOnly ? null : const EdgeInsets.only(bottom: 2),
        decoration: topOnly
            ? null
            : const BoxDecoration(
                border: Border(
                bottom: BorderSide(),
              ),),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: topOnly ? 8 : 4),
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(),
              bottom: topOnly ? BorderSide.none : const BorderSide(),
            ),
          ),
          child: child,
        ),
      );
    }

    if (vicinity.row == 0) {
      defaultCellDisplay = wrapPadding(
        Text(
          Constants.statementOfAccountHeaders[vicinity.column],
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      final currentIndex = vicinity.row - 1;
      final entryCount = soaModel.entries.length;

      if (currentIndex < entryCount) {
        final entry = soaModel.entries[currentIndex];

        if (vicinity.column == 0) {
          if (entry.isTotal) {
            defaultCellDisplay = wrapPadding(
              const Text('Total'),
            );
          } else {
            defaultCellDisplay = wrapPadding(
              Text(entry.date.toDefaultDateCompleteMonthFormat()),
            );
          }
        } else if (column == 1) {
          final amount = entry.numberOfDays;
          defaultCellDisplay = wrapPadding(
            Text(amount),
          );
        } else if (column == 2) {
          final amount = entry.principalLoan;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        } else if (column == 3) {
          final amount = entry.interestCharge;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        } else if (column == 4) {
          final amount = entry.advanceInterest;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        } else if (column == 5) {
          final amount = entry.interestPayment;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        } else if (column == 6) {
          final amount = entry.principalPayment;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        } else if (column == 7) {
          final amount = entry.principalBalance;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
        }
      } else {
        // other things
        if (currentIndex == entryCount) {
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text('Total interest charged'.toUpperCase()),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapPadding(
              Text(soaModel.totalInterestCharge.toCurrency()),
            );
          }
        } else if (currentIndex == entryCount + 1) {
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text('Less: Advance interest'.toUpperCase()),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapPadding(
              Text(soaModel.lessAdvanceInterest.toCurrency()),
            );
          }
        } else if (currentIndex == entryCount + 2) {
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text('Less: Total interest collected'.toUpperCase()),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapPadding(
              Text(soaModel.lessTotalInterestCollected.toCurrency()),
            );
          }
        } else if (currentIndex == entryCount + 3) {
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = Container(
              child: wrapPadding(
                Text(
                  'Rebates'.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapTopBottomBorder(
              Text(
                soaModel.deductions.first.amount.toCurrency(
                  removeNegative: false,
                ),
              ),
            );
          }
        } else if (currentIndex == entryCount + 4) {
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text('Outstanding principal balance'.toUpperCase()),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapPadding(
              Text(soaModel.outstandingPrincipalBalance.toCurrency()),
            );
          }
        } else if (currentIndex <=
            (entryCount + 4 + soaModel.deductions.length)) {
          // deductions
          final deduction = soaModel.deductions[_deductionBuildCount];

          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text('Less: ${deduction.description}'.toUpperCase()),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapPadding(
              Text(
                deduction.amount.toCurrency(
                  removeNegative: false,
                ),
              ),
            );
          } else if (column == 7) {
            // last column
            _deductionBuildCount += 1;
          }
        } else if (currentIndex ==
            (entryCount + 4 + soaModel.deductions.length + 1)) {
          // total amount
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text(
                'Total amount'.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapTopBottomBorder(
              Text(
                soaModel.totalAmount.toCurrency(
                  removeNegative: false,
                ),
              ),
              topOnly: true,
            );
          }
        } else if (currentIndex <=
            (entryCount +
                4 +
                soaModel.deductions.length +
                1 +
                soaModel.additionalCharges.length)) {
          // Additional charges
          if (soaModel.additionalCharges.isEmpty) {
            // defaultCellDisplay = wrapPadding(
            //   Text('Add: ${additionalCharge.description}'.toUpperCase()),
            // );
            debugPrint('empty additional charges!');
            // do nothing
          } else {
            final additionalCharge =
                soaModel.additionalCharges[_additionalChargesBuildCount];

            if (column == 2) {
              columnMergeStart = 2;
              columnMergeSpan = 3;
              defaultCellDisplay = wrapPadding(
                Text('Add: ${additionalCharge.description}'.toUpperCase()),
              );
            } else if (column == 5) {
              defaultCellDisplay = wrapPadding(
                Text(
                  additionalCharge.amount.toCurrency(
                    removeNegative: false,
                  ),
                ),
              );
            } else if (column == 7) {
              _additionalChargesBuildCount += 1;
            }
          }
        } else if (currentIndex ==
            (entryCount +
                4 +
                soaModel.deductions.length +
                1 +
                soaModel.additionalCharges.length +
                1)) {
          // Additional charges
          if (column == 2) {
            columnMergeStart = 2;
            columnMergeSpan = 3;
            defaultCellDisplay = wrapPadding(
              Text(
                'Total amount due'.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          } else if (column == 5) {
            defaultCellDisplay = wrapTopBottomBorder(
              Text(
                soaModel.totalAmountDue.toCurrency(
                  removeNegative: false,
                ),
              ),
            );
          }
        }
      }
    }

    return TableViewCell(
      columnMergeStart: columnMergeStart,
      columnMergeSpan: columnMergeSpan,
      child: defaultCellDisplay,
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
          extent: FractionalTableSpanExtent(0.25),
          // extent: const FixedTableSpanExtent(120),
          // recognizerFactories: <Type, GestureRecognizerFactory>{
          //   TapGestureRecognizer:
          //       GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          //     TapGestureRecognizer.new,
          //     (TapGestureRecognizer t) =>
          //         t.onTap = () => debugPrint('Tap column $index'),
          //   ),
          // },
        );
      default:
        return const TableSpan(
          foregroundDecoration: decoration,
          // extent: FractionalTableSpanExtent(0.22),
          extent: FixedTableSpanExtent(120),
        );
      // case 2:
      //   return TableSpan(
      //     foregroundDecoration: decoration,
      //     extent: FractionalTableSpanExtent(0.25),
      //     // extent: FixedTableSpanExtent(120),
      //   );
      // case 3:
      //   return TableSpan(
      //     foregroundDecoration: decoration,
      //     extent: FractionalTableSpanExtent(0.25),
      //     // extent: FixedTableSpanExtent(120),
      //   );
    }
  }

  TableSpan _buildRowSpan(BuildContext context, int index, SOAModel soaModel) {
    var decoration = const TableSpanDecoration();

    if (index == 0) {
      return TableSpan(
        backgroundDecoration: decoration,
        extent: const FixedTableSpanExtent(72),
      );
    }

    final currentIndex = index - 1;
    final entryCount = soaModel.entries.length;

    if (currentIndex == entryCount - 1) {
      decoration = TableSpanDecoration(
        color: AppColors.black.withOpacity(0.4),
        border: const SpanBorder(
          leading: BorderSide(),
          trailing: BorderSide(),
        ),
      );
    } else if (currentIndex >= entryCount) {}

    return TableSpan(
      backgroundDecoration: decoration,
      extent: const FixedTableSpanExtent(38),
      cursor: SystemMouseCursors.click,
      recognizerFactories: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (TapGestureRecognizer t) => t.onTap = () {
            debugPrint('Tap row $index');
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
