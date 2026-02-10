import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/true_false_cubit.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/widget/add_product/counter_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class RequirementsSection extends StatelessWidget {
  const RequirementsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Requirements',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text(
          '''
Things needed to submit upon applying for your loan in addition to the user data that the platform submits upon loan application submission.

These requirements will be in a form of PDF or image format.''',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
        ),
        const Gap(8),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) {
            return next.status == ProductStatus.refresh ||
                next.status == ProductStatus.selected;
          },
          builder: (context, state) {
            final requirements = context.read<ProductBloc>().requirements;
            return Column(
              children: requirements
                  .mapIndexed((index, req) {
                    final item = BlocProvider(
                      create: (_) => TrueFalseCubit(initialValue: true),
                      child: BlocBuilder<TrueFalseCubit, bool>(
                        builder: (context, state) {
                          return Row(
                            children: [
                              Checkbox(
                                activeColor: AppColors.black,
                                value: state,
                                onChanged: (val) {
                                  if (val == false) {
                                    context
                                        .read<ProductBloc>()
                                        .removeRequirement(id: req.id);
                                  }
                                },
                              ),
                              const Gap(4),
                              Expanded(
                                child: Text(req.name),
                              ),
                              const Gap(4),
                              CounterWidget(
                                initialValue: req.quantity,
                                onChanged: (quantity) {
                                  context.read<ProductBloc>().updateRequirement(
                                        id: req.id,
                                        quantity: quantity,
                                      );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    );

                    if (index == requirements.length - 1) {
                      return [item];
                    }

                    return [
                      item,
                      const Gap(8),
                    ];
                  })
                  .flattened
                  .toList(),
            );
          },
        ),
        const Gap(16),
        SizedBox(
          width: double.infinity,
          child: AppWidgets.defaultOutlinedButton(
            child: const Text('Add requirement'),
            onPressed: () {
              _showAddRequirementDialog(context);
            },
          ),
        ),
      ],
    );
  }

  void _showAddRequirementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final key = GlobalKey<FormBuilderState>(
          debugLabel: 'add_requirement_dialog',
        );
        return AlertDialog(
          title: const Text('Add requirement'),
          backgroundColor: AppColors.green1,
          content: FormBuilder(
            key: key,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                maxWidth: 500,
              ),
              child: AppWidgets.defaultFormBuilderTextField(
                name: 'name',
                label: 'Requirement name',
                validator: FormBuilderValidators.required(),
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Add'),
                onPressed: () {
                  if (key.currentState?.saveAndValidate() ?? false) {
                    context.read<ProductBloc>().addRequirement(
                          name: key.currentState!.value['name'] as String,
                        );
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
