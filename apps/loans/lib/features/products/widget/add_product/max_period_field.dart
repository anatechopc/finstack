import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class MaxPeriodField extends StatelessWidget {
  const MaxPeriodField({
    required this.formKey,
    required this.onTriggerTermReload,
    super.key,
    this.productView,
  });

  final GlobalKey<FormBuilderState> formKey;
  final VoidCallback onTriggerTermReload;
  final ProductView? productView;

  @override
  Widget build(BuildContext context) {
    return AppWidgets.defaultFormBuilderTextField(
      name: 'max_period',
      label: 'Max loan period',
      initialValue: productView?.maxPeriod.toString(),
      helperText: 'Period is computed in months',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        AppWidgets.rangeInputFormatter(max: 120),
      ],
      validator: FormBuilderValidators.compose(
        [
          FormBuilderValidators.required(),
        ],
      ),
      onChanged: (val) {
        onTriggerTermReload();
        formKey.currentState?.fields['period']?.didChange(
          val,
        );
      },
    );
  }
}
