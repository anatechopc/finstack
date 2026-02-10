import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class AdditionalChargesSection extends StatelessWidget {
  const AdditionalChargesSection({
    required this.isFullScreen,
    super.key,
  });

  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Additional charges',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(32),
              onTap: () {
                showChargesDialog(context);
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
            return Wrap(
              runSpacing: 8,
              spacing: 8,
              children: context.read<ProductBloc>().charges.map((charge) {
                var amountStr = '';

                if (charge.isPercentage) {
                  amountStr = '${charge.amount}%';
                } else {
                  amountStr = charge.amount.toCurrency();
                }

                return _CustomChargeChip(
                  content: '${charge.description} +$amountStr',
                  id: charge.id,
                  isDeduction: false,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  void showChargesDialog(
    BuildContext context, {
    bool isDeduction = false,
  }) {
    showChargesDeductionsDialog(
      context,
      isDeduction: isDeduction,
      isFullScreen: isFullScreen,
    );
  }
}

class DeductionsSection extends StatelessWidget {
  const DeductionsSection({
    required this.isFullScreen,
    super.key,
  });

  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Deductions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(32),
              onTap: () {
                showChargesDeductionsDialog(
                  context,
                  isDeduction: true,
                  isFullScreen: isFullScreen,
                );
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
            return Wrap(
              runSpacing: 8,
              spacing: 8,
              children: context.read<ProductBloc>().deductions.map((charge) {
                var amountStr = '';

                if (charge.isPercentage) {
                  amountStr = '${charge.amount}%';
                } else {
                  amountStr = charge.amount.toCurrency();
                }

                return _CustomChargeChip(
                  content: '${charge.description} -$amountStr',
                  id: charge.id,
                  isDeduction: true,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _CustomChargeChip extends StatelessWidget {
  const _CustomChargeChip({
    required this.content,
    required this.id,
    required this.isDeduction,
  });

  final String content;
  final String id;
  final bool isDeduction;

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
        border: Border.all(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(content),
          const Gap(4),
          IconButton(
            onPressed: () {
              if (!isDeduction) {
                context.read<ProductBloc>().removeCharge(id: id);
              } else {
                context.read<ProductBloc>().removeDeduction(id: id);
              }
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

void showChargesDeductionsDialog(
  BuildContext context, {
  bool isDeduction = false,
  bool isFullScreen = false,
}) {
  showDialog(
    context: context,
    builder: (context) {
      final key = GlobalKey<FormBuilderState>(debugLabel: 'charges_dialog');
      return AlertDialog(
        title: Text(!isDeduction ? 'Additional charge' : 'Deduction'),
        backgroundColor: AppColors.green1,
        content: FormBuilder(
          key: key,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              maxWidth: 500,
            ),
            child: !isFullScreen
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppWidgets.defaultFormBuilderTextField(
                              name: 'amount',
                              label: 'Amount',
                              helperText:
                                  'Allowed: amount or percentage (e.g 100, 3.5%)',
                              validator: FormBuilderValidators.compose([
                                FormBuilderValidators.required(),
                                (value) {
                                  if (value == null) {
                                    return null;
                                  }

                                  if (value.contains('%')) {
                                    final tempParsed = double.parse(
                                      value.substring(0, value.length - 1),
                                    );
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
                              ]),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp('^[0-9]*[.]?[0-9]*[%]?'),
                                ),
                              ],
                            ),
                          ),
                          const Gap(16),
                          Expanded(
                            child: AppWidgets.defaultFormBuilderTextField(
                              name: 'description',
                              label: 'Description',
                              validator: FormBuilderValidators.required(),
                            ),
                          ),
                        ],
                      ),
                      if (!isDeduction)
                        FormBuilderCheckbox(
                          name: 'is_upfront_collection',
                          title: const Text('Upfront Collection'),
                          initialValue: false,
                          activeColor: AppColors.black,
                          subtitle: const Text(
                            'Charges that are collected upon loan application',
                            style: TextStyle(
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppWidgets.defaultFormBuilderTextField(
                        name: 'amount',
                        label: 'Amount',
                        helperText:
                            'Allowed: amount or percentage (e.g 100, 3.5%)',
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          (value) {
                            if (value == null) {
                              return null;
                            }

                            if (value.contains('%')) {
                              final tempParsed = double.parse(
                                value.substring(0, value.length - 1),
                              );
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
                        ]),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('^[0-9]*[.]?[0-9]*[%]?'),
                          ),
                        ],
                      ),
                      const Gap(16),
                      AppWidgets.defaultFormBuilderTextField(
                        name: 'description',
                        label: 'Description',
                      ),
                      if (!isDeduction)
                        FormBuilderCheckbox(
                          name: 'is_upfront_collection',
                          title: const Text('Upfront Collection'),
                          initialValue: false,
                          activeColor: AppColors.black,
                          subtitle: const Text(
                            'Charges that are collected upon loan application',
                            style: TextStyle(
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
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
                  if (!isDeduction) {
                    context
                        .read<ProductBloc>()
                        .addAdditionalCharge(fields: key.currentState!.value);
                  } else {
                    context
                        .read<ProductBloc>()
                        .addDeduction(fields: key.currentState!.value);
                  }

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
