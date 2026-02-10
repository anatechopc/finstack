import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/preview_detail.dart';

class PreviewSection extends StatelessWidget {
  const PreviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preview',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const Gap(8),
        const Text('How clients sees your loan offer'),
        const Gap(16),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh;
          },
          builder: (context, state) {
            return PreviewDetail(
              productView: context.read<ProductBloc>().tempProductView,
            );
          },
        ),
      ],
    );
  }
}
