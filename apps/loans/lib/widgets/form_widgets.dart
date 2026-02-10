import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/loooans_camera.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/button_widgets.dart';

class FormWidgets {
  static FormBuilderTextField defaultFormBuilderTextField({
    required String name,
    required String label,
    String? helperText,
    Color borderColor = AppColors.black,
    FormFieldValidator<String>? validator,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
    Widget? suffix,
    TextInputType? keyboardType,
    String? initialValue,
    bool enabled = true,
    ValueTransformer<String?>? valueTransformer,
    void Function(String?)? onChanged,
    int? maxLines = 1,
    String? hintText,
  }) {
    return FormBuilderTextField(
      name: name,
      enabled: enabled,
      initialValue: initialValue,
      obscureText: obscureText,
      maxLines: maxLines,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        focusedBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor.withOpacity(0.6),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        errorStyle: const TextStyle(
          color: AppColors.red,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        label: Text(
          label,
          style: TextStyle(color: borderColor),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helperText,
        helperMaxLines: 4,
        helperStyle: TextStyle(
          color: borderColor.withOpacity(0.6),
        ),
        hintText: hintText,
        errorMaxLines: 4,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
      keyboardType: keyboardType,
      style: TextStyle(
        color: enabled ? borderColor : borderColor.withOpacity(0.6),
      ),
      inputFormatters: inputFormatters,
      cursorColor: borderColor,
      validator: validator,
      valueTransformer: valueTransformer,
      onChanged: onChanged,
    );
  }

  static FormBuilderTypeAhead<T> defaultFormBuilderTextFieldDropdown<T>({
    required String name,
    required String label,
    required FutureOr<List<T>?> Function(String) suggestionsCallback, required Widget Function(BuildContext, T) itemBuilder, String? helperText,
    Color borderColor = AppColors.black,
    FormFieldValidator<dynamic>? validator,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
    Widget? suffix,
    TextInputType? keyboardType,
    T? initialValue,
    bool enabled = true,
    ValueTransformer<String?>? valueTransformer,
    void Function(String?)? onChanged,
    int? maxLines = 1,
    String? hintText,
    void Function(T)? onSelected,
    SelectionToTextTransformer<T>? selectionToTextTransformer,
  }) {
    return FormBuilderTypeAhead<T>(
      name: name,
      initialValue: initialValue,
      suggestionsCallback: suggestionsCallback,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      selectionToTextTransformer: selectionToTextTransformer,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        focusedBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        errorStyle: const TextStyle(
          color: AppColors.red,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        label: Text(
          label,
          style: TextStyle(color: borderColor),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helperText,
        helperMaxLines: 4,
        helperStyle: TextStyle(
          color: borderColor.withOpacity(0.6),
        ),
        hintText: hintText,
        errorMaxLines: 4,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
      validator: validator,
    );
  }

  static FormBuilderDropdown<T> defaultFormBuilderDropdown<T>(
      {required String name,
      required String label,
      required List<DropdownMenuItem<T>> items,
      dynamic initialValue,
      FormFieldValidator<dynamic>? validator,
      Color borderColor = AppColors.black,
      ValueChanged<T?>? onChanged,
      Color? dropdownColor,
      bool enabled = true,
      }) {
    return FormBuilderDropdown(
      enabled: enabled,
      name: name,
      initialValue: initialValue as T?,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        focusedBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor.withOpacity(0.6),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        errorStyle: const TextStyle(
          color: AppColors.red,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        label: Text(
          label,
          style: TextStyle(
            color: borderColor,
          ),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      items: items,
      validator: validator,
      onChanged: onChanged,
      dropdownColor: dropdownColor ?? AppColors.lightBlack,
      style: TextStyle(
        color: enabled ? borderColor : borderColor.withOpacity(0.6),
      ),
    );
  }

  static FormBuilderDateTimePicker defaultFormBuilderDatePicker({
    required String name,
    required String label,
    String? helperText,
    Color borderColor = AppColors.black,
    FormFieldValidator<dynamic>? validator,
    DateFormat? format,
    DateTime? lastDate,
    DateTime? initialDate,
    bool enabled = true,
  }) {
    return FormBuilderDateTimePicker(
      enabled: enabled,
      name: name,
      format: format ?? Constants.defaultDateFormatWithDay,
      inputType: InputType.date,
      lastDate: lastDate,
      initialDate: initialDate ?? lastDate,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        focusedBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        errorStyle: const TextStyle(
          color: AppColors.red,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: defaultBorderRadius,
          borderSide: const BorderSide(
            color: AppColors.red,
          ),
        ),
        label: Text(
          label,
          style: TextStyle(color: borderColor),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helperText,
        helperMaxLines: 3,
        helperStyle: TextStyle(
          color: borderColor.withOpacity(0.6),
        ),
      ),
      style: TextStyle(
        color: borderColor,
      ),
      cursorColor: borderColor,
      validator: validator,
    );
  }

  static Future<Map<String, dynamic>?> defaultMediaChooserDialog(
    BuildContext context, {
    bool allowCamera = true,
    bool allowGallery = true,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose image source'),
          actionsPadding: const EdgeInsets.only(
            right: 16,
            bottom: 16,
          ),
          actions: [
            if (allowCamera)
              ButtonWidgets.defaultFilledButton(
                child: const Text('Camera'),
                onPressed: () async {
                  if (!context.mounted) {
                    return;
                  }
                  final cameras = await availableCameras();

                  final file = await showDialog<XFile?>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Take picture'),
                        content: LoooansCamera(
                          cameras: cameras,
                        ),
                      );
                    },
                  );

                  if (file == null) {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop();
                    return;
                  }

                  final fileBytes = await file.readAsBytes();

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop({
                    'name': file.name,
                    'bytes': fileBytes,
                  });
                },
              ),
            if (allowGallery)
              ButtonWidgets.defaultFilledButton(
                child: const Text('Gallery'),
                onPressed: () async {
                  if (!context.mounted) {
                    return;
                  }

                  final file = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );

                  if (file == null) {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop();
                    return;
                  }

                  final fileBytes = await file.readAsBytes();

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop({
                    'name': file.name,
                    'bytes': fileBytes,
                  });
                },
              ),
          ],
        );
      },
    );
  }

  static FormBuilderField defaultIconButtonMediaChooser(
    BuildContext context, {
    required String name,
    required String label,
    required String svgLogoPath,
    FormFieldValidator<dynamic>? validator,
    Color color = AppColors.black,
    bool allowCamera = true,
    bool allowGallery = true,
  }) {
    return FormBuilderField(
      builder: (state) {
        final isError = state.hasError;
        final data = state.value as Map<String, dynamic>?;
        final bytes = data?['bytes'] as Uint8List?;
        final name = data?['name'] as String?;

        return InkWell(
          onTap: () async {
            final fileData = await defaultMediaChooserDialog(
              context,
              allowCamera: allowCamera,
              allowGallery: allowGallery,
            );
            if (fileData != null) {
              state.didChange({
                'name': fileData['name'] as String,
                'bytes': fileData['bytes'] as Uint8List,
              });
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bytes?.isEmpty ?? true)
                SvgPicture.asset(
                  svgLogoPath.assetSafe,
                  width: 100,
                  colorFilter: ColorFilter.mode(
                    !isError ? color : AppColors.red,
                    BlendMode.srcIn,
                  ),
                )
              else
                SizedBox.square(
                  dimension: 100,
                  child: CircleAvatar(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(64),
                      child: Image.memory(
                        bytes!,
                        fit: BoxFit.cover,
                        height: 180,
                      ),
                    ),
                  ),
                ),
              const Gap(8),
              Text(
                label,
                style: TextStyle(color: color),
              ),
            ],
          ),
        );
      },
      name: name,
      validator: validator,
    );
  }

  static FormBuilderField defaultButtonMediaChooser(
    BuildContext context, {
    required String name,
    required String label,
    FormFieldValidator<dynamic>? validator,
    Color color = AppColors.black,
    bool allowCamera = true,
    bool allowGallery = true,
  }) {
    return FormBuilderField(
      builder: (state) {
        final isError = state.hasError;
        final data = state.value as Map<String, dynamic>?;
        final bytes = data?['bytes'] as Uint8List?;
        final name = data?['name'] as String?;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bytes != null) ...[
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                height: 180,
              ),
              const Gap(16),
            ],
            ButtonWidgets.defaultOutlinedButton(
              onPressed: () async {
                final fileData = await defaultMediaChooserDialog(
                  context,
                  allowCamera: allowCamera,
                  allowGallery: allowGallery,
                );
                if (fileData != null) {
                  state.didChange({
                    'name': fileData['name'] as String,
                    'bytes': fileData['bytes'] as Uint8List,
                  });
                }
              },
              foregroundColor: !isError ? color : AppColors.red,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'svg/upload.svg'.assetSafe,
                    width: 16,
                    colorFilter: ColorFilter.mode(
                      !isError ? color : AppColors.red,
                      BlendMode.srcIn,
                    ),
                  ),
                  const Gap(10),
                  Text(
                    label,
                    style: TextStyle(
                      color: !isError ? color : AppColors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      name: name,
      validator: validator,
    );
  }

  static FilteringTextInputFormatter defaultCurrencyInputFormatter() {
    return FilteringTextInputFormatter.allow(
      RegExp('^[0-9]*[.]?[0-9]*'),
    );
  }

  /// NOTE: make sure to only use this formatter for number fields
  static TextInputFormatter rangeInputFormatter(
      {double max = double.infinity,}) {
    return TextInputFormatter.withFunction((val1, val2) {
      if (val2.text.isEmpty) {
        return const TextEditingValue(text: '0');
      }

      final amount = double.parse(val2.text);

      if (amount > max) {
        return val1;
      }

      return val2;
    });
  }
}
