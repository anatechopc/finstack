import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanTypeSection extends StatelessWidget {
  const LoanTypeSection({
    required this.formKey,
    super.key,
    this.productView,
  });

  final GlobalKey<FormBuilderState> formKey;
  final ProductView? productView;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Loan type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Gap(8),
        FormBuilderRadioGroup<String>(
          name: 'loan_type',
          initialValue: !CommonProducts.isOthers(productView?.loanType ?? '')
              ? 'others'
              : productView?.loanType,
          orientation: OptionsOrientation.vertical,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(borderSide: BorderSide.none),
          ),
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
          activeColor: AppColors.black,
          options: [
            ...CommonProducts.values.map((value) {
              return FormBuilderFieldOption(
                value: value.label,
                child: Text(value.label),
              );
            }),
            const FormBuilderFieldOption(
              value: 'others',
              child: Text('Others'),
            ),
          ],
          onChanged: (value) {
            formKey.currentState?.fields['others_type_visibility']
                ?.didChange(value == 'others');
          },
        ),
        const Gap(8),
        FormBuilderField(
          initialValue: !CommonProducts.isOthers(productView?.loanType ?? ''),
          builder: (state) {
            if (state.value == null) {
              return Container();
            }

            var show = false;

            if (state.value is bool) {
              show = state.value!;
            }

            return Visibility(
              visible: show,
              child: AppWidgets.defaultFormBuilderTextField(
                initialValue: productView?.loanType,
                name: 'others_type',
                label: 'Loan type',
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                ]),
              ),
            );
          },
          name: 'others_type_visibility',
        ),
      ],
    );
  }
}
