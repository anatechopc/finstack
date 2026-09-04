import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/penalty_dialog.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';

class PenaltiesSection extends StatelessWidget {
  const PenaltiesSection({
    required this.product,
    super.key,
  });

  final Product? product;

  @override
  Widget build(BuildContext context) {
    final defaults = AuthenticationService.instance.company.defaultPenalties;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Penalties',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(32),
              onTap: () async {
                final bloc = context.read<ProductBloc>();
                final penalty = await showPenaltyDialog(context);
                if (penalty != null) {
                  bloc.addPenalty(penalty);
                }
              },
              child: SvgPicture.asset(
                'svg/add.svg'.assetSafe,
                colorFilter: const ColorFilter.mode(
                  AppColors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
        const Gap(8),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final bloc = context.read<ProductBloc>();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: bloc.penalties.map((penalty) {
                    final inherited = defaults.any((d) => d.id == penalty.id);
                    return _PenaltyChip(
                      penalty: penalty,
                      inherited: inherited,
                    );
                  }).toList(),
                ),
                const Gap(4),
                const Text(
                  'Charged when an installment is paid after its due date. '
                  'Chips marked "Default" came from the company defaults.',
                  style: TextStyle(fontSize: 10),
                ),
                if (defaults.isNotEmpty)
                  TextButton(
                    onPressed: bloc.resetPenalties,
                    child: const Text('Reset to company defaults'),
                  ),
              ],
            );
          },
        ),
        const Gap(8),
        FormBuilderCheckbox(
          name: 'allow_late_payments',
          initialValue: product?.allowLatePayments ?? false,
          title: const Text('Allow late payments'),
          activeColor: AppColors.black,
          subtitle: const Text(
            'When on, late payments are not tagged and no penalties are '
            'charged on this product.',
            style: TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }
}

class _PenaltyChip extends StatelessWidget {
  const _PenaltyChip({
    required this.penalty,
    required this.inherited,
  });

  final Penalty penalty;
  final bool inherited;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: 10,
        top: 4,
        bottom: 4,
        right: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: inherited ? AppColors.green1_5 : AppColors.black,
          width: inherited ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${inherited ? 'Default · ' : ''}${penalty.chipLabel}'),
          const Gap(4),
          IconButton(
            onPressed: () {
              context.read<ProductBloc>().removePenalty(id: penalty.id);
            },
            icon: const Icon(
              Icons.remove_circle,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
