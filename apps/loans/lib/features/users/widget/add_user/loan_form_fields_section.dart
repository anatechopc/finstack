import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class LoanFormFieldsSection extends StatelessWidget {
  const LoanFormFieldsSection({
    required this.formKey,
    super.key,
  });

  final GlobalKey<FormBuilderState> formKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductBloc, ProductState>(
      buildWhen: (prev, next) {
        return [
          ProductStatus.refresh,
          ProductStatus.selected,
          ProductStatus.unselected,
          ProductStatus.initial,
          ProductStatus.loanSelected,
        ].contains(next.status);
      },
      builder: (context, state) {
        final productView = context.read<ProductBloc>().tempProductView;

        // open term loan product doesn't have max period
        if (state.status == ProductStatus.loanSelected) {
          if (productView.maxPeriod <= 0) {
            // added run the code after 100 ms to prevent
            // setState while building
            Timer(const Duration(milliseconds: 100), () {
              formKey.currentState?.fields['period']
                  ?.didChange(0.toString());
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              if (value == null || value.isEmpty) {
                                return null;
                              }

                              final amount = double.parse(value);

                              if (amount >
                                  productView.maxLoanableAmount) {
                                return 'Amount greater than max loanable amount';
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
                        enabled: productView.maxPeriod > 0,
                        helperText:
                            'per ${productView.completeTerm} @ ${productView.completeMaxPeriod}',
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
                    ],
                  ),
                ),
                if (productView.maxPeriod <= 0) ...[
                  const Gap(16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Payment frequency',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,),
                        ),
                        const Gap(8),
                        FormBuilderRadioGroup<String>(
                          name: 'payment_frequency',
                          initialValue: '1m',
                          orientation: OptionsOrientation.vertical,
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(
                                borderSide: BorderSide.none,),
                          ),
                          validator:
                              FormBuilderValidators.compose([
                            FormBuilderValidators.required(),
                          ]),
                          activeColor: AppColors.black,
                          options: const [
                            FormBuilderFieldOption(
                              value: '1m',
                              child: Text('Monthly'),
                            ),
                            FormBuilderFieldOption(
                              value: '15d',
                              child: Text('Twice a month'),
                            ),
                            FormBuilderFieldOption(
                              value: 'salary_days',
                              child: Text('Salary days'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
