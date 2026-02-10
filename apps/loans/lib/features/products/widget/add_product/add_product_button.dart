import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class AddProductButton extends StatelessWidget {
  const AddProductButton({
    required this.formKey,
    super.key,
    this.productId,
  });

  final GlobalKey<FormBuilderState> formKey;
  final String? productId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppWidgets.defaultFilledButton(
        child: Text(
          productId == null ? 'Add product' : 'Update product',
          style: const TextStyle(
            color: AppColors.green1,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: () {
          if (formKey.currentState?.saveAndValidate() ?? false) {
            if (productId == null) {
              context
                  .read<ProductBloc>()
                  .addProduct(formKey.currentState!.value);
            } else {
              context
                  .read<ProductBloc>()
                  .updateProduct(formKey.currentState!.value);
            }
          }
        },
      ),
    );
  }
}
