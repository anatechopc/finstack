import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';

class UploadTermsConditionsField extends StatelessWidget {
  const UploadTermsConditionsField({
    super.key,
    this.product,
  });

  final Product? product;

  @override
  Widget build(BuildContext context) {
    return FormBuilderField(
      builder: (state) {
        final isError = state.hasError;
        final data = state.value as Map<String, dynamic>?;
        final name = data?['name'] as String?;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppWidgets.defaultOutlinedButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'pdf',
                    'jpg',
                    'png',
                    'gif',
                  ],
                );

                if (result != null) {
                  final file = result.files.single.xFile;
                  final fileBytes = await file.readAsBytes();
                  state.didChange({
                    'name': file.name,
                    'bytes': fileBytes,
                  });
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
                      'Upload your own Terms and conditions',
                      style: TextStyle(
                        color: !isError ? AppColors.black : AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              "Not required but it's great to have your own terms and conditions",
              style: TextStyle(
                color: AppColors.black.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
            if (name != null) ...[
              Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
          ],
        );
      },
      name: 'upload_terms_conditions',
      initialValue: {
        'name': product?.termsConditionUrl?.name,
        'bytes': Uint8List.fromList([]),
      },
    );
  }
}
