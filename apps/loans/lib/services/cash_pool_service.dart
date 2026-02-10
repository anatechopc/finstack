import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';

class CashPoolService {
  Future<void> handleBulkAddCashToPool(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null && result.files.isNotEmpty) {
      final resultFile = result.files.single;
      String csvString;

      if (!kIsWeb) {
        final filePath = resultFile.path!;
        final file = File(filePath);
        try {
          csvString = await file.readAsString();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reading file: $e')),
          );
          return;
        }
      } else {
        // For web, the file is read as bytes. We need to decode them.
        final fileBytes = resultFile.bytes;
        if (fileBytes == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read file bytes on the web.'),
            ),
          );
          return;
        }
        try {
          // Use utf8.decode to correctly convert the byte list to a string.
          csvString = utf8.decode(fileBytes);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error decoding file: $e')),
          );
          return;
        }
      }

      List<List<dynamic>> csvTable;
      try {
        csvTable = const CsvToListConverter(shouldParseNumbers: false)
            .convert(csvString);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error parsing CSV: $e')),
        );
        return;
      }

      if (csvTable.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV file is empty.')),
        );
        return;
      }

      var successCount = 0;
      var errorCount = 0;
      final errorMessages = <String>[];

      // Simple header detection: check if first row cells look like typical headers
      var hasHeader = false;
      if (csvTable.isNotEmpty) {
        final firstRow = csvTable[0];
        if (firstRow.length >= 3 &&
            (firstRow[0].toString().toLowerCase().contains('id') ||
                firstRow[0].toString().toLowerCase().contains('user')) &&
            (firstRow[1].toString().toLowerCase().contains('name')) &&
            (firstRow[2].toString().toLowerCase().contains('amount'))) {
          hasHeader = true;
        }
      }

      final recordsToProcess = hasHeader ? csvTable.sublist(1) : csvTable;

      if (recordsToProcess.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No data rows found in CSV (after potentially skipping header).',
            ),
          ),
        );
        return;
      }

      // Define the ButtonOption for adding to cash pool
      final addCashPoolOption = ButtonOption(
        label: 'Add to cash pool', // Label for consistency
        value: 'add_cash_pool', // Value used by the BLoC
      );

      for (var i = 0; i < recordsToProcess.length; i++) {
        final row = recordsToProcess[i];
        final rowNumber = i + (hasHeader ? 2 : 1);

        if (row.length >= 3) {
          final userId = row[0].toString().trim();
          final name = row[1].toString().trim(); // For comment
          final amountString = row[2].toString().trim();

          if (userId.isEmpty) {
            errorCount++;
            errorMessages.add('Row $rowNumber: User ID is empty.');
            continue;
          }

          double? amount;
          try {
            final cleanedAmountString = amountString
                .replaceAll(',', '') // Remove thousand separators
                .replaceAll(
                  RegExp(r'[^\d.]'),
                  '',
                ); // Remove non-numeric/non-dot
            amount = double.parse(cleanedAmountString);
            if (amount <= 0) {
              errorCount++;
              errorMessages.add(
                'Row $rowNumber: Amount for user $userId must be positive.',
              );
              continue;
            }
          } catch (e) {
            errorCount++;
            errorMessages.add(
              'Row $rowNumber: Invalid amount format ("$amountString") for user $userId.',
            );
            continue;
          }

          if (context.mounted) {
            try {
              context.read<CashPoolBloc>().addCashPoolRecord(
                    amount: amount,
                    userId: userId, // Use userId from CSV
                    comment:
                        'Bulk CSV Upload. User: $name. Amount: ${amount.toCurrency()}',
                    option: addCashPoolOption,
                  );
              successCount++;
            } catch (e) {
              errorCount++;
              errorMessages
                  .add('Row $rowNumber: Error processing user $userId: $e');
            }
          }
        } else {
          errorCount++;
          errorMessages.add(
            'Row $rowNumber: Incorrect number of columns (expected 3). Found ${row.length}.',
          );
        }
      }

      if (!context.mounted) return;
      // Show results dialog
      final _ = showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bulk Add Cash Report'),
          content: Container(
            width: 1400,
            // height: 1000,
            constraints: const BoxConstraints(maxHeight: 1000, maxWidth: 1400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Processed $successCount records successfully.'),
                Text('Failed to process $errorCount records.'),
                if (errorMessages.isNotEmpty) ...[
                  const Gap(10),
                  const Text(
                    'Errors:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: errorMessages.length,
                      itemBuilder: (ctx, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          errorMessages[index],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
    } else {
      // User canceled the picker
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File selection cancelled.')),
      );
    }
  }

  Future<void> handleCashPoolOptions(
    BuildContext context, {
    required String userId,
    required ButtonOption? selectedOption,
  }) {
    final key =
        GlobalKey<FormBuilderState>(debugLabel: 'add_cash_to_pool_dialog');
    return showDialog(
      context: context,
      builder: (context) {
        // ... existing single add cash dialog logic ...
        // No changes here for the single add
        return AlertDialog(
          title: Text(selectedOption?.label ?? 'Add cash to pool'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 300),
            child: FormBuilder(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppWidgets.defaultFormBuilderTextField(
                    name: 'amount',
                    label: 'Amount',
                    inputFormatters: [
                      AppWidgets.defaultCurrencyInputFormatter(),
                    ],
                    validator: FormBuilderValidators.required(),
                  ),
                  const Gap(16),
                  AppWidgets.defaultFormBuilderTextField(
                    name: 'comment',
                    label: 'Comment',
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: Text(selectedOption?.label ?? 'Add cash'),
                onPressed: () {
                  if (key.currentState?.saveAndValidate() ?? false) {
                    if (selectedOption == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please select an option.',
                          ),
                        ),
                      );
                      return;
                    }

                    final values = key.currentState?.value;
                    final amount = double.parse(values!['amount'] as String);
                    final comment = values['comment'] as String?;
                    context.read<CashPoolBloc>().addCashPoolRecord(
                          amount: amount,
                          userId: userId,
                          // This is for the currently viewed user
                          comment: comment,
                          option: selectedOption,
                        );
                    Navigator.of(context).pop();
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
