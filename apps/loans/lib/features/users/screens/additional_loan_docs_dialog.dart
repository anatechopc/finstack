import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Shows a dialog with additional loan documents
Future<void> showAdditionalLoanDocsDialog(
    BuildContext context, List<FileUrl> documents,) {
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text(
          'Additional Loan Documents:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SizedBox(
          width: 800,
          height: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your additional loan amount is being submitted and is being reviewed. '
                'Please see the attached documents below, download them and submit them to the teller once signed',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Gap(16),
              Expanded(
                child: ListView.builder(
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return ListTile(
                      title: Text(document.name),
                      leading: const Icon(Icons.description),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              content: SizedBox(
                                width: 800,
                                height: 600,
                                child: FileViewerWidget(
                                  items: documents.map((document) {
                                    return RequirementSubmission(
                                      url: document,
                                      name: document.name,
                                      requirementId:
                                      'additional_loan_doc_$index',
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppWidgets.defaultOutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
