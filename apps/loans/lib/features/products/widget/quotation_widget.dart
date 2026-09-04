import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';

class QuotationWidget extends StatelessWidget {
  const QuotationWidget({
    required this.loanAmount,
    required this.period,
    required this.interestRate,
    super.key,
    this.foregroundColor = AppColors.black,
    this.penalties,
    this.allowLatePayments,
  });

  final double loanAmount;
  final int period;
  final double interestRate;
  final Color foregroundColor;

  /// When null, the product bloc's working list is shown (offer preview and
  /// application). Pass a loan's snapshot to show the terms in force.
  final List<Penalty>? penalties;

  /// Only known for a loan (its snapshot). Null hides the line.
  final bool? allowLatePayments;

  @override
  Widget build(BuildContext context) {
    return quotation(
      context,
      loanAmount: loanAmount,
      period: period,
    );
  }

  Widget quotation(
    BuildContext context, {
    required double loanAmount,
    required int period,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quotation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
            IconButton(
              onPressed: () async {
                final loansBloc = context.read<LoansBloc>();
                final userBloc = context.read<UserBloc>();
                Company? company;

                if (AuthenticationService.instance.hasCompany) {
                  company = AuthenticationService.instance.company;
                }

                AppWidgets.showDefaultLoadingDialog(context);
                await PdfGenerator.generatePdf(
                  schedules: loansBloc.clientLoanSchedules,
                  loan: loansBloc.selectedLoan,
                  user: userBloc.user,
                  userAddress: userBloc.address,
                  company: company,
                  companyAddress: AuthenticationService.instance.address,
                  product: context.read<ProductBloc>().selectedProduct!,
                );
                // remove the dialog
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              },
              icon: const Icon(
                Icons.print_rounded,
                color: AppColors.black,
              ),
            ),
          ],
        ),
        const Gap(8),
        _quotationItem(
          title: 'Loan amount',
          detail: loanAmount.toCurrency(),
        ),
        _quotationItem(
          title: 'Period',
          detail: period.toString(),
        ),
        _quotationItem(
          title: 'Interest rate',
          detail: '$interestRate%',
        ),
        // _quotationItem(
        //   title: 'Add: Transaction fee',
        //   detail: 50.toCurrency(),
        // ),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final charges = context.read<ProductBloc>().charges;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: charges.map(
                (charge) {
                  var detail = charge.amount.toCurrency();

                  if (charge.isPercentage) {
                    detail = '${charge.amount}%';
                  }

                  return _quotationItem(
                    title: 'Add: ${charge.description}',
                    detail: detail,
                  );
                },
              ).toList(),
            );
          },
        ),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final deductions = context.read<ProductBloc>().deductions;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: deductions.map(
                (deduction) {
                  var detail = deduction.amount.toCurrency();

                  if (deduction.isPercentage) {
                    detail = '${deduction.amount}%';
                  }

                  return _quotationItem(
                    title: 'Less: ${deduction.description}',
                    detail: detail,
                  );
                },
              ).toList(),
            );
          },
        ),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final list = penalties ?? context.read<ProductBloc>().penalties;
            final allowsLate = allowLatePayments ??
                context.read<ProductBloc>().selectedProduct?.allowLatePayments ??
                false;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allowsLate)
                  _quotationItem(
                    title: 'Late payments',
                    detail: 'Allowed, no penalties',
                  )
                else
                  ...list.map(
                    (penalty) {
                      return _quotationItem(
                        title: 'Penalty if paid late: ${penalty.name}',
                        detail: penalty.amountLabel,
                      );
                    },
                  ),
              ],
            );
          },
        ),
        Divider(
          color: foregroundColor,
        ),
        BlocBuilder<LoansBloc, LoansState>(
          builder: (context, state) {
            return _quotationItem(
              title: 'Total payable',
              detail: context.read<LoansBloc>().totalLoanPayment.toCurrency(),
            );
          },
        ),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final charges = context.read<ProductBloc>().charges;
            final upfrontCollection = charges.fold<double>(0, (prev, next) {
              var amount = 0.0;

              if (next.isUpfrontCollection) {
                if (next.isPercentage) {
                  amount = (next.amount / 100) * loanAmount;
                } else {
                  amount = next.amount;
                }
              }

              return prev + amount;
            });

            return _quotationItem(
              title: 'Total upfront collection',
              detail: upfrontCollection.toCurrency(),
            );
          },
        ),
        BlocBuilder<LoansBloc, LoansState>(
          builder: (context, state) {
            var totalReceivables = context.read<LoansBloc>().totalLoanAmountReceivable;

            if (totalReceivables.isNaN) {
              totalReceivables = 0;
            }

            return _quotationItem(
              title: 'Total loan amount receivable',
              detail: totalReceivables.toCurrency(),
              enlargeDetail: true,
            );
          },
        ),
        BlocBuilder<LoansBloc, LoansState>(
          builder: (context, state) {
            var amortization = context.read<LoansBloc>().monthlyAmortization;

            if (amortization.isNaN) {
              amortization = 0;
            }

            return _quotationItem(
              title: 'Monthly Amortization',
              detail: amortization.toCurrency(),
              enlargeDetail: true,
            );
          },
        ),
      ],
    );
  }

  Widget _quotationItem({
    required String title,
    required String detail,
    bool enlargeDetail = false,
  }) {
    final textStyle = TextStyle(
      fontSize: !enlargeDetail ? 12 : 16,
      fontWeight: !enlargeDetail ? null : FontWeight.w600,
      color: foregroundColor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: textStyle,
            ),
          ),
          Text(
            detail,
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
