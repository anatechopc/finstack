part of 'pdf_generator.dart';

pw.Widget openTermLoanNotes({
  required Loan loan,
}) {
  if (loan.dueAt != null) {
    return pw.Container();
  }

  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Notes:',
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(
        height: 4,
      ),
      noteItem(
        bulletIndicator: '1.',
        content:
            'It is possible to pay only for the interest  for Open term loans and by default, all payment made for the loan goes to interest payment, unless stated that extra payments goes to principal payment.',
      ),
      noteItem(
        bulletIndicator: '2.',
        content:
            'It is also possible to make an additional loan amount on top of the outstanding balance, provided that, it is acknowledged by the borrower.',
      ),
      noteItem(
        bulletIndicator: '3.',
        content:
            'Open term loan accounts will only be closed once the outstanding balance is fully paid OR an early settlement is made.',
      ),
      noteItem(
        bulletIndicator: '4.',
        content:
            'A statement of account (SOA) will be generated once an early settlement is made. The SOA will consist of all payments made, rebates from extra interest payments and other loan accounts that are not closed at the moment.',
      ),
      noteItem(
        bulletIndicator: '5.',
        content: 'Payment computation:',
      ),
      noteItem(
        bulletIndicator: '',
        content:
            'payment = outstanding balance * interest rate * (num of days / 30)',
        isSubItem: true,
      ),
      noteItem(
        bulletIndicator: '',
        content: 'payment = 100,000 * 10% * (15 / 30)',
        isSubItem: true,
      ),
      noteItem(
        bulletIndicator: '',
        content: 'payment = 100,000 * 10% * 0.5',
        isSubItem: true,
      ),
      noteItem(
        bulletIndicator: '',
        content: 'payment = 5,000',
        isSubItem: true,
      ),
      noteItem(
        bulletIndicator: '6.',
        content: 'Payment computation notes:',
      ),
      noteItem(
        bulletIndicator: '·',
        content:
            'A month consists of 30 days. For those months that have more than or less than 30 days (e.g. January, February), they are treated to have 30 days in them.',
        isSubItem: true,
      ),
    ],
  );
}

pw.Widget noteItem({
  required String bulletIndicator,
  required String content,
  bool isSubItem = false,
}) {
  const defaultStyle = pw.TextStyle(
    fontSize: 10,
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (isSubItem)
        pw.SizedBox(
          width: 24,
        ),
      pw.Text(
        '$bulletIndicator ',
        style: defaultStyle,
      ),
      pw.Expanded(
        child: pw.Text(
          content,
          style: defaultStyle,
        ),
      ),
    ],
  );
}
