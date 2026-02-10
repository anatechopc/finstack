part of 'pdf_generator.dart';

pw.Widget _personalDetails(String title, String content) {
  return pw.RichText(
    text: pw.TextSpan(
      text: '$title: ',
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
      ),
      children: [
        pw.TextSpan(
          text: content,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _quotationWidget({
  required Loan loan,
  required Product product,
}) {
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Quotation',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(
        height: 8,
      ),
      _quotationItem(
        title: 'Loan amount',
        detail: loan.amount.toCurrency(),
      ),
      _quotationItem(
        title: 'Period',
        detail: loan.period.toString(),
      ),
      _quotationItem(
        title: 'Interest rate',
        detail: '${loan.interestRate}%',
      ),
      ...product.additionalCharges.map(
        (charge) {
          var detail = charge.amount.toCurrency();

          if (charge.isPercentage) {
            detail = '${charge.amount}%';
          }

          return _quotationItem(
            title: 'Add: ${charge.description}',
            detail: detail,
          );
        },
      ),
      ...product.deductions.map(
        (deduction) {
          var detail = deduction.amount.toCurrency();

          if (deduction.isPercentage) {
            detail = '${deduction.amount}%';
          }

          return _quotationItem(
            title: 'Less: ${deduction.description}',
            detail: detail,
          );
        },
      ),
      pw.Divider(),
      _quotationItem(
        title: 'Total payable',
        detail: _computeTotalPayable(loan).toCurrency(),
      ),
      _quotationItem(
        title: 'Monthly Amortization',
        detail: loan.amortization.toCurrency(),
      ),
    ],
  );
}

pw.Widget _quotationItem({
  required String title,
  required String detail,
}) {
  const textStyle = pw.TextStyle();

  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            title,
            style: textStyle,
          ),
        ),
        pw.Text(
          detail,
          style: textStyle,
        ),
      ],
    ),
  );
}

double _computeTotalPayable(Loan loan) {
  return (loan.amortization * loan.period) +
      loan.additionalCharges -
      loan.deductions;
}

pw.Widget signatories({
  required String name,
  required String description,
}) {
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8),
        decoration:
            const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide())),
        child: pw.Text(name),
      ),
      pw.Text(
        description,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  );
}

pw.Widget _tableItemWidget(
  String text, {
  double? height,
  bool expand = true,
  bool boldText = false,
  double? fontSize,
}) {
  final itemWidget = pw.Container(
    height: height,
    padding: const pw.EdgeInsets.only(
      top: 4,
      bottom: 4,
    ),
    child: pw.Center(
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: boldText ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: fontSize,
        ),
        textAlign: pw.TextAlign.center,
      ),
    ),
  );

  if (expand) {
    return pw.Expanded(child: itemWidget);
  }

  return itemWidget;
}

pw.Widget _soaTotalItem(
  String title,
  String detail, {
  bool bottomBorder = false,
  bool isDoubleBorder = false,
}) {
  var drawBottomBorder = bottomBorder;

  if (isDoubleBorder) {
    drawBottomBorder = true;
  }

  return pw.LayoutBuilder(
    builder: (context, constraints) {
      return pw.Container(
        margin: pw.EdgeInsets.only(
          left: constraints!.maxWidth * 0.25,
        ),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Expanded(
              flex: 2,
              child: pw.Text(title),
            ),
            pw.Container(
              width: 80,
              margin: const pw.EdgeInsets.only(left: 16),
              padding:
                  !isDoubleBorder ? null : const pw.EdgeInsets.only(bottom: 4),
              decoration: !isDoubleBorder
                  ? null
                  : const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(),
                      ),
                    ),
              child: pw.Container(
                padding: const pw.EdgeInsets.only(
                  top: 4,
                  bottom: 4,
                ),
                decoration: !drawBottomBorder
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(),
                        ),
                      ),
                child: pw.Text(detail),
              ),
            ),
            pw.Expanded(
              child: pw.Container(),
            ),
          ],
        ),
      );
    },
  );
}

pw.Widget _companyDetails({
  required Company company,
  Address? companyAddress,
}) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            company.name,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (companyAddress != null) ...[
            pw.SizedBox(
              height: 4,
            ),
            pw.Text(
              companyAddress.completeAddress,
              style: const pw.TextStyle(
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
      pw.Container(
        width: 56,
        height: 56,
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(),
        ),
        child: pw.Text('Company logo here'),
      ),
    ],
  );
}
