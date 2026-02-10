part of 'pdf_generator.dart';

Future<Uint8List> _buildPdf(
  PdfPageFormat format, {
  required List<LoanSchedule> schedules, required Loan loan, required Product product, User? user,
  Address? userAddress,
  Company? company,
  Address? companyAddress,
}) async {
  final pdfTheme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
      boldItalic: await PdfGoogleFonts.robotoBoldItalic(),
      italic: await PdfGoogleFonts.robotoItalic(),
      icons: await PdfGoogleFonts.robotoRegular(),);
// Create the Pdf documentf
  final doc = pw.Document(theme: pdfTheme);
  debugPrint('pageFormat: $format');
  final finalFormat = format.copyWith(
    marginLeft: 1.0 * PdfPageFormat.cm,
    marginRight: 1.0 * PdfPageFormat.cm,
    marginTop: 1.0 * PdfPageFormat.cm,
    marginBottom: 1.0 * PdfPageFormat.cm,
  );

// Add one page with centered text "Hello World"
// pw.Partitions
  doc.addPage(
    pw.MultiPage(
// orientation: pw.PageOrientation.landscape,
      pageFormat: finalFormat,
      build: (pw.Context context) {
        return [
          pw.Container(
// width: format.availableWidth * 0.3,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (company != null) ...[
                  _companyDetails(
                    company: company,
                    companyAddress: companyAddress,
                  ),
                  pw.SizedBox(
                    height: 16,
                  ),
                ],
                if (user != null) ...[
                  pw.SizedBox(
                    height: 8,
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _personalDetails(
                            'Name',
                            user.completeNameEasternOrder,
                          ),
                          if (userAddress != null) ...[
                            pw.SizedBox(height: 4),
                            _personalDetails(
                              'Address',
                              user.completeNameEasternOrder,
                            ),
                          ],
                          pw.SizedBox(height: 4),
                          _personalDetails('Payment term', loan.completeTerm),
                          pw.SizedBox(height: 4),
                          _personalDetails('Loan type', product.loanType),
                        ],
                      ),
                      pw.Container(
                        width: 250,
// height: 100,
                        padding: const pw.EdgeInsets.all(16),
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(),
                            borderRadius: pw.BorderRadius.circular(16),),
                        child: _quotationWidget(
                          loan: loan,
                          product: product,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(
            height: 8,
          ),
          pw.RichText(
            text: pw.TextSpan(
              text: 'Loan schedule',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
              children: [
                if (loan.dueAt == null)
                  pw.TextSpan(
                    text: ' (sample)',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(
            height: 8,
          ),
          pw.Table(
            children: [
              pw.TableRow(
                repeat: true,
                children: Constants.printLoanScheduleHeaders
                    .mapIndexed(
                      (index, header) => pw.Expanded(
                        child: pw.Container(
                          margin: const pw.EdgeInsets.only(bottom: 4),
                          height: 40,
                          child: pw.Center(
                            child: pw.Text(
                              header,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
// beginning of schedule
              pw.TableRow(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        '0',
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        loan.createdAt.toDefaultDateFormat(),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        loan.amount.toCurrency(),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        '',
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        '',
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(
                        bottom: 4,
                      ),
                      child: pw.Text(
                        '',
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              ...schedules.mapIndexed(
                (index, schedule) => pw.TableRow(
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          '${index + 1}',
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          schedule.dueAt.toDefaultDateFormat(),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          (schedule.outstandingBalance +
                                  schedule.principalPayment)
                              .toCurrency(),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          schedule.interestPayment.toCurrency(),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          schedule.principalPayment.toCurrency(),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(
                          bottom: 4,
                        ),
                        child: pw.Text(
                          schedule.outstandingBalance.toCurrency(),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.Expanded(
            child: pw.Container(),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              signatories(name: 'Juan Gom Borza', description: 'Checked by'),
              signatories(
                  name: 'Juan Gom Borza with a very long ame',
                  description: 'Received by',),
            ],
          ),
          pw.Divider(),
          openTermLoanNotes(loan: loan),
        ];
      },
    ),
  );

// Build and return the final Pdf file data
  return doc.save();
}
