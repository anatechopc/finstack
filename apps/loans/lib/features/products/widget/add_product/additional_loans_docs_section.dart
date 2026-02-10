import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';
import 'package:product_repository/product_repository.dart';

class AdditionalLoansDocsSection extends StatelessWidget {
  const AdditionalLoansDocsSection({
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
          'Additional loans',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text(
          '''
By setting the Max period to zero, the loan product you are about to create is an Open Term Loan.
In an Open Term Loan, the borrower is allowed to borrow multiple times without having to reapply for a new loan.

Additional documents are required to be submitted upon each additional loan application.
Upload the additional documents that you want to require from the borrower upon each additional loan application.''',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
        ),
        const Gap(8),
        FormBuilderField(
          builder: (state) {
            final isError = state.hasError;
            final data = state.value as List<dynamic>?;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppWidgets.defaultOutlinedButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowMultiple: true,
                      allowedExtensions: [
                        'pdf',
                        'jpg',
                        'jpeg',
                        'png',
                        'gif',
                      ],
                    );

                    if (result != null) {
                      final files = result.files;
                      final fileDataList = <Map<String, dynamic>>[];

                      for (final file in files) {
                        final xFile = file.xFile;
                        final fileBytes = await xFile.readAsBytes();
                        fileDataList.add({
                          'name': xFile.name,
                          'bytes': fileBytes,
                        });
                      }

                      state.didChange(fileDataList);
                    }
                  },
                  foregroundColor: !isError ? AppColors.black : AppColors.red,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'svg/upload.svg'.assetSafe,
                        width: 16,
                        colorFilter: ColorFilter.mode(
                          !isError ? AppColors.black : AppColors.red,
                          BlendMode.srcIn,
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          'Upload additional loan documents',
                          style: TextStyle(
                            color: !isError ? AppColors.black : AppColors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isError) ...[
                  const Gap(8),
                  Text(
                    state.errorText ?? 'Please upload at least one file',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
                const Gap(8),
                Text(
                  'Select multiple files that will be required for additional loan applications',
                  style: TextStyle(
                    color: AppColors.black.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
                if (data != null &&
                    data is List<Map<String, dynamic>> &&
                    data.isNotEmpty) ...[
                  const Gap(16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Additional Loan Documents',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(8),
                      ...data.asMap().entries.map((entry) {
                        final fileData = entry.value;
                        final name = fileData['name'] as String;
                        final validData =
                            data.where((e) => e['bytes'] != null).toList();

                        return InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  content: SizedBox(
                                    width: 1000,
                                    height: 800,
                                    child: FileViewerWidget(
                                      items:
                                          product?.additionalLoanDocs.map((e) {
                                                return RequirementSubmission(
                                                  url: e,
                                                  name: e.name,
                                                  requirementId: e.name,
                                                );
                                              }).toList() ??
                                              [],
                                      tempItems: [
                                        RequirementTempContainer(
                                          'additional_loan_docs',
                                          'Additional Loan Documents',
                                          validData.map((fileData) {
                                            final name =
                                                fileData['name'] as String;
                                            final bytes = fileData['bytes']
                                                    as Uint8List? ??
                                                Uint8List(0);
                                            return SimpleFileData(
                                              name,
                                              bytes,
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.insert_drive_file,
                                  size: 20,
                                  color: AppColors.black,
                                ),
                                const Gap(8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ],
            );
          },
          name: 'additional_loan_docs',
          initialValue: product?.additionalLoanDocs.map((e) {
                return {
                  'name': e.name,
                  'url': e.url as dynamic,
                };
              }).toList() ??
              [],
          validator: FormBuilderValidators.compose([
            (value) {
              if (value == null || (value as List).isEmpty) {
                return 'Please upload at least one additional loan document';
              }
              return null;
            },
          ]),
        ),
      ],
    );
  }
}
