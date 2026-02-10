import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/loan_offer_item.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class PreviewDetail extends StatelessWidget {
  const PreviewDetail({
    required this.productView, super.key,
    this.fullScreen = false,
  });

  final bool fullScreen;
  final ProductView productView;

  @override
  Widget build(BuildContext context) {
    context.read<LoansBloc>().calculateLoan(
      fields: {
        'amount': productView.maxLoanableAmount.toString(),
        'period': productView.maxPeriod.toString(),
        'payment_frequency': productView.term,
      },
      term: productView.term,
      interestRate: productView.interestRate,
      additionalCharges: context.read<ProductBloc>().charges,
      deductions: context.read<ProductBloc>().deductions,
    );

    return BlocListener<ProductBloc, ProductState>(
      listenWhen: (prev, next) {
        return next.status == ProductStatus.refresh;
      },
      listener: (context, state) {
        if (state.status == ProductStatus.refresh) {
          context.read<LoansBloc>().calculateLoan(
            fields: {
              'amount': productView.maxLoanableAmount.toString(),
              'period': productView.maxPeriod.toString(),
              'payment_frequency': productView.term,
            },
            term: productView.term,
            interestRate: productView.interestRate,
            additionalCharges: context.read<ProductBloc>().charges,
            deductions: context.read<ProductBloc>().deductions,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(defaultPaddingSize),
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: !fullScreen ? defaultBorderRadius : null,
        ),
        child: _detailsCompact(context),
      ),
    );
  }

  Widget _detailsCompact(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoanOfferItem(
          productView: productView,
          isContent: true,
          isProduct: true,
          backgroundColor: AppColors.black,
          foregroundColor: AppColors.green1,
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          enabled: false,
          name: 'amount',
          label: 'Amount',
          helperText: 'Enter amount to borrow',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          borderColor: AppColors.green1,
          initialValue: productView.maxLoanableAmount.toString(),
        ),
        const Gap(16),
        AppWidgets.defaultFormBuilderTextField(
          enabled: false,
          name: 'period',
          label: 'Period',
          initialValue: productView.maxPeriod.toString(),
          helperText: 'Period multiplied by ${productView.completeTerm}',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          borderColor: AppColors.green1,
          validator: FormBuilderValidators.compose([
            (value) {
              if (value != null) {
                try {
                  final period = int.parse(value);

                  if (period < 0 || period > productView.maxPeriod) {
                    return 'Period out of range';
                  }
                } catch (err) {
                  return null;
                }
              }

              return null;
            }
          ]),
        ),
        const Gap(16),
        QuotationWidget(
          loanAmount: productView.maxLoanableAmount,
          period: productView.maxPeriod,
          interestRate: productView.interestRate,
          foregroundColor: AppColors.white,
        ),
        const Gap(16),
        AppWidgets.defaultOutlinedButton(
          foregroundColor: AppColors.green1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Payment schedule',
                style: TextStyle(
                  color: AppColors.green1,
                  fontSize: 12,
                ),
              ),
              const Gap(4),
              SvgPicture.asset('svg/icon_arrow_up.svg'.assetSafe),
            ],
          ),
          onPressed: () {
            showOfferDialog(context, purpose: 'payment_schedule');
          },
        ),
        const Gap(8),
        AppWidgets.defaultOutlinedButton(
          padding: const EdgeInsets.all(16),
          foregroundColor: AppColors.green1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Terms',
                style: TextStyle(
                  color: AppColors.green1,
                  fontSize: 12,
                ),
              ),
              const Gap(4),
              SvgPicture.asset('svg/icon_arrow_up.svg'.assetSafe),
            ],
          ),
          onPressed: () {
            final productBloc = context.read<ProductBloc>();
            showOfferDialog(
              context,
              purpose: 'terms',
              pdfUri: productBloc.selectedProduct?.termsConditionUrl?.url,
              tempPdfBytes: productBloc.tempTermsAndConditions,
            );
          },
        ),
      ],
    );
  }

  void showOfferDialog(
    BuildContext context, {
    required String purpose,
    String? pdfUri,
    Map<String, Uint8List>? tempPdfBytes,
  }) {
    if (purpose == 'payment_schedule') {
      showDialog(
        context: context,
        builder: (context) {
          // height is used for schedule item widget height
          // 20 is the number of items
          // 24 is the height set per item
          var height = (20 * 24).toDouble();

          if (height > 600) {
            height = 600;
          }

          final screenHeight = MediaQuery.sizeOf(context).height;

          if (screenHeight < 800) {
            // this height computation is good until screenHeight=600
            height = screenHeight - (screenHeight * 0.50);
          }

          return AlertDialog(
            backgroundColor: AppColors.green1,
            scrollable: true,
            title: const Text(
              'Loan payment schedule',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 24,
              ),
            ),
            content: LoanScheduleWidget(
              forDialogHeight: height,
              amortization: context.read<LoansBloc>().monthlyAmortization,
              schedules: context.read<LoansBloc>().clientLoanSchedules,
              completeTerm: productView.completeTerm,
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultFilledButton(
                  child: const Text(
                    'Close',
                    style: TextStyle(color: AppColors.green1),
                  ),
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
              ),
            ],
          );
        },
      );
    } else if (purpose == 'terms') {
      AppWidgets.showPdfDialog(
        context,
        pdfUri: pdfUri,
        tempPdfBytes: tempPdfBytes,
      );
    }
  }
}
