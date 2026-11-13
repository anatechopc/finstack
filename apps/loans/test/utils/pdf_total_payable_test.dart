import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_repository/user_repository.dart';

// finstack#124: the PDF quotation's "Total payable" is the sum of the
// amortization of the schedules it prints. Hand-derived (5% a month):
//   G1 monthly: 10000, 3 months. A = 10000 * 0.05 / (1 - 1.05^-3)
//               = 500 / 0.1361624 = 3672.0856;  3 * A = 11016.26
//   G8 monthly: principal 10000 + charges 650 - deductions 150 = 10500 (the
//               upfront 200 is collected separately), 3 months.
//               A = 10500 * 0.05 / 0.1361624 = 3855.6899;  3 * A = 11567.07
//               The old formula A * period + 650 - 150 showed 12067.07.
//   15-day:     10000, entered as 6 payments; loans_bloc stores period 3
//               (months). Rate 2.5% per payment, 6 payments.
//               A = 10000 * 0.025 / (1 - 1.025^-6) = 250 / 0.1377033
//               = 1815.4997;  6 * A = 10893.00
//               The old formula A * period showed 5446.50.
//   Open-term:  period 0, no total known in advance: the line is hidden.
//               The old formula showed 650 - 150 = 500.00 for G8.
final _date = DateTime.utc(2026); // 2026-01-01

List<LoanSchedule> _fixed(double amount, int months, String term) {
  return LoanCalculationService.calculateFixedTerm(
    amount: amount,
    monthsToPay: months,
    date: _date,
    interestRate: 5,
    term: term,
    companyId: 'c',
  ).schedules;
}

/// One real open-term row (G8 principal 10500, interest 525), so the
/// open-term tests fail if the period check becomes an emptiness check.
List<LoanSchedule> _open() {
  final s = LoanCalculationService.calculateOpenTerm(
    amount: 10500,
    date: _date,
    interestRate: 5,
    term: '1m',
    companyId: 'c',
  ).schedules;
  expect(s, isNotEmpty);
  return s;
}

Loan _loan({
  required int period,
  required String term,
  required double amortization,
  double amount = 10000,
  double additionalCharges = 0,
  double deductions = 0,
}) {
  return Loan.create(
    userId: 'u',
    companyId: 'c',
    productId: 'p',
    amount: amount,
    additionalCharges: additionalCharges,
    deductions: deductions,
    period: period,
    requirements: const [],
    isForceCollect: false,
    status: LoanStatus.approved,
    dueAt: period > 0 ? _date : null,
    reason: 'test',
    interestRate: 5,
    term: term,
    amortization: amortization,
  );
}

Product _product() => Product()
  ..loanType = 'Personal'
  ..additionalCharges = const []
  ..deductions = const []
  ..penalties = const [];

User _user() => User()
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz';

/// Inflates every FlateDecode stream of [pdf] and returns the page text
/// operators, so a test can look for a printed string.
String _contentText(Uint8List pdf) {
  final raw = latin1.decode(pdf);
  final out = StringBuffer();
  final stream = RegExp('stream\r?\n');
  var from = 0;
  while (true) {
    final m = stream.firstMatch(raw.substring(from));
    if (m == null) break;
    final start = from + m.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) break;
    try {
      out.write(
        latin1.decode(zlib.decode(pdf.sublist(start, end)), allowInvalid: true),
      );
    } on Object {
      // Not a deflated stream (fonts, images); skip it.
    }
    from = end;
  }
  // The generator writes one `[(word)]TJ` per word; join the words.
  return RegExp(r'\[\((.*?)\)\]TJ')
      .allMatches(out.toString())
      .map((m) => m.group(1))
      .join(' ');
}

void main() {
  group('pdfTotalPayable', () {
    test('G1 monthly: 11016.26', () {
      final s = _fixed(10000, 3, '1m');
      final loan = _loan(period: 3, term: '1m', amortization: s.first.amortization);
      expect(pdfTotalPayable(loan, s), closeTo(11016.26, 0.005));
    });

    test('G8 monthly: 11567.07, charges and deductions not added again', () {
      final s = _fixed(10500, 3, '1m');
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: s.first.amortization,
        additionalCharges: 650,
        deductions: 150,
      );
      expect(pdfTotalPayable(loan, s), closeTo(11567.07, 0.005));
    });

    test('15-day, 6 payments stored as period 3: 10893.00', () {
      final s = _fixed(10000, 3, '15d');
      expect(s, hasLength(6));
      final loan = _loan(period: 3, term: '15d', amortization: s.first.amortization);
      expect(pdfTotalPayable(loan, s), closeTo(10893.00, 0.005));
    });

    test('open-term (period 0): null, the line is hidden', () {
      final loan = _loan(
        period: 0,
        term: '1m',
        amortization: 525,
        additionalCharges: 650,
        deductions: 150,
      );
      expect(pdfTotalPayable(loan, _open()), isNull);
    });
  });

  group('PdfGenerator.buildPdfBytes', () {
    testWidgets('G8 monthly prints Total payable 11,567.07', (tester) async {
      final s = _fixed(10500, 3, '1m');
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: s.first.amortization,
        additionalCharges: 650,
        deductions: 150,
      );
      final bytes = await tester.runAsync(
        () => PdfGenerator.buildPdfBytes(
          schedules: s,
          loan: loan,
          product: _product(),
          user: _user(),
        ),
      );
      final text = _contentText(bytes!);

      expect(text, contains('Total payable'));
      expect(text, contains('11,567.07'));
      expect(text, isNot(contains('12,067.07')));
    });

    testWidgets('open-term prints no Total payable line', (tester) async {
      final loan = _loan(
        period: 0,
        term: '1m',
        amortization: 525,
        additionalCharges: 650,
        deductions: 150,
      );
      final bytes = await tester.runAsync(
        () => PdfGenerator.buildPdfBytes(
          schedules: _open(),
          loan: loan,
          product: _product(),
          user: _user(),
        ),
      );
      final text = _contentText(bytes!);

      expect(text, contains('Monthly Amortization'));
      expect(text, isNot(contains('Total payable')));
    });
  });
}
