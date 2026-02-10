import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/widget/add_product/counter_widget.dart';
import 'package:product_repository/product_repository.dart';

class CoMakerCountSection extends StatelessWidget {
  const CoMakerCountSection({
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
          'Required number of co-makers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        FormBuilderField(
          initialValue: product?.requiredCoMakerCount ?? 0,
          builder: (state) {
            final data = state.value;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Number of Co-makers'),
                const Gap(16),
                CounterWidget(
                  initialValue: data ?? 0,
                  minValue: 0,
                  onChanged: (value) {
                    state.didChange(value);
                  },
                ),
              ],
            );
          },
          name: 'required_co_maker_count',
        ),
      ],
    );
  }
}
