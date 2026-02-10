part of 'pdf_generator.dart';

Future<Uint8List> _buildPdfSoa(
  PdfPageFormat format, {
  required SOAModel soaModel,
  Company? company,
  Address? companyAddress,
}) async {
  final pdfTheme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
      boldItalic: await PdfGoogleFonts.robotoBoldItalic(),
      italic: await PdfGoogleFonts.robotoItalic(),
      icons: await PdfGoogleFonts.robotoRegular(),);
// Create the Pdf document
  final doc = pw.Document(theme: pdfTheme);
  debugPrint('pageFormat: $format');
  final finalFormat = format.copyWith(
    marginLeft: 1.0 * PdfPageFormat.cm,
    marginRight: 1.0 * PdfPageFormat.cm,
    marginTop: 1.0 * PdfPageFormat.cm,
    marginBottom: 1.0 * PdfPageFormat.cm,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: finalFormat,
      build: (pw.Context context) {
        return [
          if (company != null) ...[
            _companyDetails(
              company: company,
              companyAddress: companyAddress,
            ),
            pw.SizedBox(
              height: 14,
            ),
          ],
          pw.SizedBox(
            width: double.infinity,
            child: pw.Text(
              'Statement of Account',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(
            width: double.infinity,
            child: pw.Text(
              'As of ${DateTime.now().toWesternDateFormatWithDay()}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                fontSize: 10,
              ),
            ),
          ),
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.LayoutBuilder(
                builder: (context, constraints) {
                  return pw.SizedBox(
                    width: double.infinity,
                    child: pw.SizedBox(
                      width: constraints!.maxWidth * 0.5,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: constraints.maxWidth * 0.14,
                            child: pw.Text(
                              'Name'.toUpperCase(),
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Text(soaModel.fullName),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // spacing
              pw.SizedBox(
                height: 4,
              ),
              pw.LayoutBuilder(
                builder: (context, constraints) {
                  return pw.SizedBox(
                    width: double.infinity,
                    child: pw.SizedBox(
                      width: constraints!.maxWidth * 0.5,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: constraints.maxWidth * 0.14,
                            child: pw.Text(
                              'Interest rate'.toUpperCase(),
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Text('${soaModel.interest}% / ${soaModel.term}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
              pw.SizedBox(
                height: 24,
              ),
              // add _table
              pw.Table(
                children: [
                  pw.TableRow(
                    repeat: true,
                    children: Constants.statementOfAccountHeaders
                        .mapIndexed((index, header) {
                      return _tableItemWidget(header,
                          height: 40, boldText: true,);
                    }).toList(),
                  ),
                  ...soaModel.entries.mapIndexed((index, entry) {
                    return pw.TableRow(
                      decoration: !entry.isTotal
                          ? null
                          : pw.BoxDecoration(
                              color: PdfColor.fromRYB(0, 0, 0, 0.8),
                              border: const pw.Border(
                                top: pw.BorderSide(),
                                bottom: pw.BorderSide(),
                              ),),
                      children: [
                        _tableItemWidget(entry.isTotal
                            ? 'Total'
                            : entry.date.toDefaultDateFormat(),),
                        _tableItemWidget(
                          entry.numberOfDays,
                        ),
                        _tableItemWidget(
                          entry.principalLoan.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                        _tableItemWidget(
                          entry.interestCharge.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                        _tableItemWidget(
                          entry.advanceInterest.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                        _tableItemWidget(
                          entry.interestPayment.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                        _tableItemWidget(
                          entry.principalPayment.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                        _tableItemWidget(
                          entry.principalBalance.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(
                height: 8,
              ),
              _soaTotalItem('Total interest charged',
                  soaModel.totalInterestCharge.toCurrency(),),
              _soaTotalItem('Less: Advance interest',
                  soaModel.lessAdvanceInterest.toCurrency(),),
              _soaTotalItem(
                'Less: Total interest collected',
                soaModel.lessTotalInterestCollected.toCurrency(),
                bottomBorder: true,
              ),
              _soaTotalItem(
                'Rebates',
                soaModel.deductions.first.amount.toCurrency(
                  removeNegative: false,
                ),
                isDoubleBorder: true,
              ),
              _soaTotalItem('Outstanding principal balance',
                  soaModel.outstandingPrincipalBalance.toCurrency(),),
              _soaTotalItem('Less: Total interest collected',
                  soaModel.lessTotalInterestCollected.toCurrency(),),
              ...soaModel.deductions.mapIndexed(
                (index, deduction) {
                  return _soaTotalItem(
                    'Less: ${deduction.description}',
                    deduction.amount.toCurrency(
                      removeNegative: false,
                    ),
                    bottomBorder: index == soaModel.deductions.length - 1,
                  );
                },
              ),
              _soaTotalItem('Total amount'.toUpperCase(),
                  soaModel.totalAmount.toCurrency(),),
              ...soaModel.additionalCharges.mapIndexed((index, charge) {
                return _soaTotalItem(
                  'Add: ${charge.description}',
                  charge.amount.toCurrency(
                    removeNegative: false,
                  ),
                  bottomBorder: index == soaModel.deductions.length - 1,
                );
              }),
              _soaTotalItem(
                'Total amount due'.toUpperCase(),
                soaModel.totalAmountDue.toCurrency(),
                isDoubleBorder: true,
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
        ];
      },
    ),
  );

  return doc.save();
}
