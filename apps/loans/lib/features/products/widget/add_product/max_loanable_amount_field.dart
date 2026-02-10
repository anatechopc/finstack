import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class MaxLoanableAmountField extends StatelessWidget {
  const MaxLoanableAmountField({
    required this.formKey,
    super.key,
    this.productView,
  });

  final GlobalKey<FormBuilderState> formKey;
  final ProductView? productView;

  @override
  Widget build(BuildContext context) {
    return AppWidgets.defaultFormBuilderTextField(
      name: 'loanable_amount',
      label: 'Max loanable amount',
      initialValue: productView?.maxLoanableAmount.toString(),
      helperText:
          'You can still cater loans more than the max amount if the borrower requests for it',
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp('^[0-9]*[.]?[0-9]*'),
        ),
      ],
      validator: FormBuilderValidators.compose(
        [
          FormBuilderValidators.required(),
        ],
      ),
      onChanged: (val) {
        formKey.currentState?.fields['amount']?.didChange(
          val,
        );
      },
    );
  }
}
