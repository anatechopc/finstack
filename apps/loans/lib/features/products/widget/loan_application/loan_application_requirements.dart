import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/features/products/widget/loan_application/upload_requirement_dialog.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';

class LoanApplicationRequirements extends StatelessWidget {
  const LoanApplicationRequirements({super.key});

  @override
  Widget build(BuildContext context) {
    final product = context.read<ProductBloc>().selectedProduct;
    final selectedProductView = context.read<ProductBloc>().tempProductView;
    final productRequirements = product?.requirements ?? [];

    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.refresh;
      },
      builder: (context, state) {
        return FormBuilderField(
          builder: (state) {
            final hasError = state.hasError;

            return Container(
              padding: EdgeInsets.all(hasError ? 8 : 0),
              decoration: hasError
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.red),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
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
                      const Gap(4),
                      Text(
                        'Please submit the required documents needed by ${selectedProductView.companyName}\n\nPDF or image format accepted.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      if (productRequirements.isEmpty) const Gap(8),
                      for (final requirement in productRequirements) ...[
                        Builder(
                          builder: (context) {
                            final submittedRequirement = context
                                .read<LoansBloc>()
                                .submittedRequirements
                                .singleWhereOrNull(
                                  (submitted) =>
                                      submitted.requirementId == requirement.id,
                                );

                            return InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                if (submittedRequirement != null) {
                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      return AlertDialog(
                                        content: SizedBox(
                                          width: 1000,
                                          height: 800,
                                          child: FileViewerWidget(
                                            tempItems: [submittedRequirement],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: _requirementItem(
                                  context,
                                  name:
                                      '${requirement.quantity} ${requirement.name}',
                                  fulfilled: requirement.quantity ==
                                      submittedRequirement?.fileData.length,
                                  submittedRequirement: submittedRequirement,
                                ),
                              ),
                            );
                          },
                        ),
                        const Gap(4),
                      ],
                      const Gap(16),
                      SizedBox(
                        width: double.infinity,
                        child: AppWidgets.defaultOutlinedButton(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'svg/upload.svg'.assetSafe,
                                width: 24,
                              ),
                              const Gap(8),
                              const Text(
                                'Upload requirement',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          onPressed: () async {
                            await showUploadRequirementDialog(
                              context,
                              productRequirements,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (hasError) ...[
                    const Gap(4),
                    Text(
                      state.errorText ?? 'Please add requirements',
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
          name: 'requirements',
          validator: FormBuilderValidators.compose([
            (value) {
              if (product != null &&
                  !context
                      .read<LoansBloc>()
                      .isSubmittedRequestCompleted(product)) {
                return 'Please submit all requirements';
              }

              return null;
            },
          ]),
        );
      },
    );
  }

  Widget _requirementItem(
    BuildContext context, {
    required String name,
    bool fulfilled = false,
    RequirementTempContainer? submittedRequirement,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            right: 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Icon(
                fulfilled ? Icons.check_rounded : Icons.close_rounded,
                color: fulfilled ? AppColors.lightBlack : AppColors.red,
              ),
            ],
          ),
        ),
        if (submittedRequirement != null)
          ...submittedRequirement.fileData.mapIndexed((index, item) {
            return Padding(
              padding: const EdgeInsets.only(
                top: 4,
                left: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      context.read<LoansBloc>().removeRequirement(
                            requirementId: submittedRequirement.requirementId,
                            index: index,
                          );
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.lightBlack,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
