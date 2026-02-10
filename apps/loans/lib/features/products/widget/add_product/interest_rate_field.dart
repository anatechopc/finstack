import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class InterestRateField extends StatelessWidget {
  const InterestRateField({
    super.key,
    this.productView,
  });

  final ProductView? productView;

  @override
  Widget build(BuildContext context) {
    return AppWidgets.defaultFormBuilderTextField(
      name: 'interest_rate',
      label: 'Interest rate',
      initialValue: productView?.interestRate.toString(),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp('^[0-9]*[.]?[0-9]*[%]?'),
        ),
      ],
      validator: FormBuilderValidators.compose(
        [
          FormBuilderValidators.required(),
          (value) {
            if (value == null) {
              return null;
            }

            if (value.contains('%')) {
              final tempParsed =
                  double.parse(value.substring(0, value.length - 1));
              if (tempParsed > 100 || tempParsed < 0) {
                return 'Percentage value should only be between 0 and 100';
              }
            } else {
              final tempParsed = double.parse(value);

              if (tempParsed <= 0) {
                return 'Amount should be greater than 0';
              }
            }

            return null;
          },
        ],
      ),
    );
  }
}
