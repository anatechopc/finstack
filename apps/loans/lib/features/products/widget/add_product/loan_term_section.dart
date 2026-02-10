import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanTermSection extends StatelessWidget {
  const LoanTermSection({
    super.key,
    this.productView,
  });

  final ProductView? productView;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Loan term',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Gap(8),
        FormBuilderRadioGroup<String>(
          name: 'term',
          initialValue: productView?.term,
          orientation: OptionsOrientation.vertical,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(borderSide: BorderSide.none),
          ),
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
          activeColor: AppColors.black,
          options: [
            const FormBuilderFieldOption(
              value: '1m',
              child: Text('Monthly'),
            ),
            if (context.read<ProductBloc>().tempProductView.maxPeriod > 0)
              const FormBuilderFieldOption(
                value: '15d',
                child: Text('Twice a month'),
              ),
          ],
        ),
      ],
    );
  }
}
