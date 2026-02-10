import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:product_repository/product_repository.dart';

class AddOnsSection extends StatelessWidget {
  const AddOnsSection({
    super.key,
    this.product,
  });

  final Product? product;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add-ons',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text(
          '''
Add-ons are additional products or services that can be added to the loan.
These add ons however increases the overall value of the loan.
Please use it with caution.''',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
        ),
        const Gap(8),
        FormBuilderSwitch(
          name: 'allow_addons',
          initialValue: product?.allowAddOns ?? true,
          // by default, allow all products to have addons
          title: const Text('Allow addons'),
          activeColor: AppColors.black,
          inactiveTrackColor: AppColors.green1,
          decoration: const InputDecoration(
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
      ],
    );
  }
}
