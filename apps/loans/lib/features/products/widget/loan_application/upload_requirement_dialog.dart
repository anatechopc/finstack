import 'package:collection/collection.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';

Future<void> showUploadRequirementDialog(
  BuildContext context,
  List<Requirement> productRequirements,
) {
  final submittedRequirement =
      context.read<LoansBloc>().submittedRequirements;
  final visibleProductRequirements = productRequirements.whereNot(
    (req) {
      return submittedRequirement
              .singleWhereOrNull(
                  (submitted) => submitted.requirementId == req.id,)
              ?.fileData
              .length ==
          req.quantity;
    },
  );

  if (visibleProductRequirements.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All requirements are already submitted'),
      ),
    );
    return Future.value();
  }

  return showDialog(
    context: context,
    builder: (context) {
      final formKey = GlobalKey<FormBuilderState>(
        debugLabel: 'add_loan_requirement_dialog',
      );
      formKey.currentState?.fields['requirement']
          ?.setValue(visibleProductRequirements.first);

      return AlertDialog(
        backgroundColor: AppColors.green1,
        content: FormBuilder(
          key: formKey,
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Requirement',
                  style: TextStyle(
                    color: AppColors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppWidgets.defaultFormBuilderDropdown(
                  name: 'requirement',
                  label: 'Type',
                  items: visibleProductRequirements
                      .map(
                        (requirement) => DropdownMenuItem(
                          value: requirement,
                          child: Text(requirement.name),
                        ),
                      )
                      .toList(),
                  initialValue: visibleProductRequirements.first,
                  validator: FormBuilderValidators.required(),
                  dropdownColor: AppColors.white,
                  onChanged: (requirement) {
                    formKey.currentState?.fields['data']?.reassemble();
                  },
                ),
                FormBuilderField(
                  builder: (state) {
                    final isError = state.hasError;
                    final data = state.value as List<SimpleFileData>?;
                    final names =
                        data?.map((e) => '● ${e.name}').join('\n') ?? '';
                    final selectedRequirement = formKey.currentState!
                        .simplifiedFields()['requirement'] as Requirement?;
                    var quantity = 1;

                    if (selectedRequirement != null) {
                      quantity = selectedRequirement.quantity;
                    }

                    return SizedBox(
                      width: 500,
                      height: 200,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final result =
                              await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: [
                              'pdf',
                              'jpg',
                              'png',
                              'gif',
                            ],
                            allowMultiple: quantity > 1,
                          );

                          if (result != null) {
                            final simpleFiles = <SimpleFileData>[];
                            for (final file in result.files) {
                              final fileBytes =
                                  await file.xFile.readAsBytes();
                              simpleFiles.add(
                                SimpleFileData(
                                  file.name,
                                  fileBytes,
                                ),
                              );
                            }
                            state.didChange(simpleFiles);
                          }
                        },
                        child: DottedBorder(
                          borderType: BorderType.RRect,
                          radius: const Radius.circular(16),
                          strokeCap: StrokeCap.round,
                          dashPattern: const [
                            8,
                          ],
                          strokeWidth: 1.3,
                          color: isError ? AppColors.red : AppColors.black,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Click to upload',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                if (names.isNotEmpty)
                                  Text(
                                    names,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  name: 'data',
                  validator: FormBuilderValidators.required(),
                ),
                SizedBox(
                  width: double.infinity,
                  child: AppWidgets.defaultFilledButton(
                    foregroundColor: AppColors.green1,
                    child: const Text('Add requirement'),
                    onPressed: () {
                      if (formKey.currentState?.saveAndValidate() ?? false) {
                        final requirement = formKey.currentState!
                            .value['requirement'] as Requirement;
                        final fileData = formKey.currentState!.value['data']
                            as List<SimpleFileData>;

                        context.read<LoansBloc>().addRequirement(
                              requirement: requirement,
                              data: fileData,
                            );

                        Navigator.of(
                          context,
                          rootNavigator: true,
                        ).pop();
                      }
                    },
                  ),
                ),
              ]
                  .mapIndexed(
                    (i, widget) => [
                      if (i > 0) const Gap(24),
                      widget,
                    ],
                  )
                  .flattened
                  .toList(),
            ),
          ),
        ),
      );
    },
  );
}
