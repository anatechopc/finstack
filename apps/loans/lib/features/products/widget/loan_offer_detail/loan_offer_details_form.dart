import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/loan_offer_item.dart';
import 'package:loooans/features/products/widget/loan_offer_detail/loan_offer_dialogs.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanOfferDetailsForm extends StatelessWidget {
  const LoanOfferDetailsForm({
    required this.formKey,
    required this.productView,
    required this.background,
    super.key,
  });

  final GlobalKey<FormBuilderState> formKey;
  final ProductView productView;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return FormBuilder(
      key: formKey,
      onChanged: () {
        var amount = 0.0;
        var period = 0;

        if (formKey.currentState?.fields['amount']?.value != null) {
          final val = formKey.currentState?.fields['amount']?.value as String;

          if (val.isNotEmpty) {
            amount = double.parse(val);
          } else {
            amount = 0;
          }
        }

        if (formKey.currentState?.fields['period']?.value != null) {
          final val = formKey.currentState?.fields['period']?.value as String;

          if (val.isNotEmpty) {
            period = int.parse(val);
          } else {
            period = 0;
          }
        }

        context.read<LoansBloc>().calculateLoan(
          fields: {
            'amount': amount.toString(),
            'period': period.toString(),
          },
          term: productView.term,
          interestRate: productView.interestRate,
          additionalCharges: context.read<ProductBloc>().charges,
          deductions: context.read<ProductBloc>().deductions,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoanOfferItem(
            backgroundColor: background,
            isContent: true,
            productView: productView,
          ),
          const Gap(16),
          AppWidgets.defaultFormBuilderTextField(
            name: 'amount',
            label: 'Amount',
            helperText: 'Enter amount to borrow',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              AppWidgets.rangeInputFormatter(
                max: productView.maxLoanableAmount,
              ),
            ],
            validator: FormBuilderValidators.compose(
              [
                FormBuilderValidators.required(
                  errorText: 'Please enter amount',
                ),
                (value) {
                  try {
                    if (value == null || value.isEmpty) {
                      return null;
                    }

                    final amount = double.parse(value);

                    if (amount > productView.maxLoanableAmount) {
                      return 'Amount greater than max loanable amount';
                    }
                  } catch (e) {
                    debugPrint(e.toString());
                  }

                  return null;
                }
              ],
            ),
          ),
          const Gap(16),
          AppWidgets.defaultFormBuilderTextField(
            name: 'period',
            label: 'Period',
            helperText: 'Period multiplied by 15 days',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              AppWidgets.rangeInputFormatter(
                max: productView.maxPeriod.toDouble(),
              ),
            ],
            validator: FormBuilderValidators.compose(
              [
                FormBuilderValidators.required(
                    errorText: 'Please enter period',),
              ],
            ),
          ),
          const Gap(16),
          BlocBuilder<LoansBloc, LoansState>(
            buildWhen: (prev, next) {
              return next.status == LoansStatus.refresh;
            },
            builder: (context, state) {
              var amount = 0.0;
              var period = 0;

              if (state.status == LoansStatus.refresh) {
                if (formKey.currentState?.fields['amount']?.value != null) {
                  final val =
                      formKey.currentState?.fields['amount']?.value as String;

                  if (val.isNotEmpty) {
                    amount = double.parse(val);
                  } else {
                    amount = 0;
                  }
                }

                if (formKey.currentState?.fields['period']?.value != null) {
                  final val =
                      formKey.currentState?.fields['period']?.value as String;

                  if (val.isNotEmpty) {
                    period = int.parse(val);
                  } else {
                    period = 0;
                  }
                }
              }

              return QuotationWidget(
                loanAmount: amount,
                period: period,
                interestRate: productView.interestRate,
              );
            },
          ),
          const Gap(16),
          AppWidgets.defaultFilledButton(
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
          AppWidgets.defaultFilledButton(
            padding: const EdgeInsets.all(16),
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
              showOfferDialog(
                context,
                purpose: 'terms',
                pdfUri: context
                    .read<ProductBloc>()
                    .selectedProduct
                    ?.termsConditionUrl
                    ?.url,
              );
            },
          ),
        ],
      ),
    );
  }
}
