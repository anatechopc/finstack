import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_repository/user_repository.dart';

// finstack#124: the PDF quotation's "Total payable" is the sum of the
// interest and principal it prints for each schedule row: a bill's own split
// (its amortization) until it is paid, what was paid once it is.
// Hand-derived (5% a month):
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
//
// After #156 (G16, fixed_term_shortfall_golden_test.dart), G1 dated
// 2026-01-10. The PDF gets the loan's rows (`LoansBloc.clientLoanRows`:
// stored rows, then the engine's) and prints one bill per due date
// (`LoanCalculationService.wholeBills`):
//   Carried shortfall (G16a): bill 1 (3,672.0856 = 500 + 3,172.0856) paid
//     500 + 3,000, so 172.09 is carried. Bill 2 = 3,672.09 + 172.09 =
//     3,844.18 (350 + 3,494.18); bill 3 = 175.29 + 3,505.82 = 3,681.11.
//     Printed: 3,500 + 3,844.18 + 3,681.11 = 11,025.29. Summing the
//     amortizations gives 3,672.0856 + 3,844.18 + 3,681.11 = 11,197.38:
//     the 172.09 once in bill 1 and again in bill 2.
//   Part-paid last bill (G16c): bills 1 and 2 paid as billed (3,672.0856
//     each): bill 1 500 + 3,172.08565, balance 6,827.91435; bill 2
//     341.39572 + 3,330.68993, balance 3,497.22443.
//     Before the part payment bill 3 is 3,497.2244 x 5% = 174.8612 +
//     3,497.2244 = 3,672.0856, and the total is 3 x 3,672.0856 = 11,016.26.
//     Bill 3 paid 174.8612 + 3,000: 497.2244 is still owed. The screens
//     show bill 3 as that rest; the PDF prints it whole: interest 174.8612,
//     principal 3,000 + 497.2244 = 3,497.2244, amount 3,672.0856, of which
//     3,174.8612 is paid and 497.2244 still owed. Total 11,016.26, as
//     before the part payment (#126; summing the rest alone gave
//     2 x 3,672.0856 + 497.2244 = 7,841.40). The rest paid: the same row,
//     paid, 11,016.26.
final _date = DateTime.utc(2026); // 2026-01-01
final _g16Date = DateTime(2026, 1, 10);

LoanCalculationResult _g1After(List<LoanSchedule> stored) =>
    LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: _g16Date,
      interestRate: 5,
      term: '1m',
      companyId: 'c',
      paidSchedules: List.of(stored),
    );

/// The rows `LoansBloc.clientLoanRows` holds for G1 after [stored].
List<LoanSchedule> _g1Rows(List<LoanSchedule> stored) =>
    [...stored, ..._g1After(stored).schedules];

/// The rows the PDF prints for [rows].
List<LoanSchedule> _printed(List<LoanSchedule> rows) =>
    [for (final bill in LoanCalculationService.wholeBills(rows)) bill.bill];

/// The rows the PDF prints for G1 after [stored].
List<LoanSchedule> _g1Shown(List<LoanSchedule> stored) =>
    _printed(_g1Rows(stored));

/// [stored] plus the next G1 bill, paid at a teller as [interest] +
/// [principal] (default: as billed).
List<LoanSchedule> _payNext(
  List<LoanSchedule> stored, {
  double? interest,
  double? principal,
}) {
  final next = _g1After(stored).schedules.first;
  PaymentConfirmationService.recordTellerPayment(
    next,
    interestPayment: interest ?? next.interestPayment,
    principalPayment: principal ?? next.principalPayment,
  );

  return [
    ...stored,
    next
      ..id = 'row-${stored.length + 1}'
      ..loanId = 'loan-1'
      ..status = LoanStatus.paid_on_time,
  ];
}

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

    test('carried shortfall (G16a): 3,500 + 3,844.18 + 3,681.11 = 11,025.29',
        () {
      final shown = _g1Shown(_payNext(const [], interest: 500, principal: 3000));
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: shown.first.amortization,
      );

      expect(
        shown.map((s) => (s.interestPayment + s.principalPayment).toStringAsFixed(2)),
        ['3500.00', '3844.18', '3681.11'],
      );
      expect(pdfTotalPayable(loan, shown), closeTo(11025.29, 0.005));
      final amortizations =
          shown.fold<double>(0, (sum, s) => sum + s.amortization);
      expect(amortizations, closeTo(11197.38, 0.005), reason: 'the old sum');
    });

    test('part-paid last bill (G16c): printed whole, 11,016.26 before the '
        'part payment, while the rest is owed and once it is paid', () {
      final twoPaid = _payNext(_payNext(const []));
      // The bill's interest as billed (174.86122), principal 3,000.
      final short = _payNext(twoPaid, principal: 3000);
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: short.first.amortization,
      );

      final before = pdfTotalPayable(loan, _g1Shown(twoPaid));
      expect(before, closeTo(11016.26, 0.005));

      // The screens still show bill 3 as its rest.
      expect(
        LoanCalculationService.oneBillPerDueDate(_g1Rows(short)).last
            .amortization,
        closeTo(497.2244, 0.0001),
      );
      final bills = LoanCalculationService.wholeBills(_g1Rows(short));
      expect(bills, hasLength(3));
      expect(bills.map((b) => b.owed), [0, 0, closeTo(497.2244, 0.0001)]);
      final bill3 = bills.last.bill;
      expect(bill3.amortization, closeTo(3672.0856, 0.0001));
      expect(bill3.interestPayment, closeTo(174.8612, 0.0001));
      expect(bill3.principalPayment, closeTo(3497.2244, 0.0001));
      expect(bill3.outstandingBalance, closeTo(0, 0.000001));
      expect(
        bill3.status,
        isNot(anyOf(LoanStatus.paid_on_time, LoanStatus.paid_late)),
      );
      final owed = pdfTotalPayable(loan, [for (final b in bills) b.bill]);
      expect(owed, closeTo(before!, 0.000001));
      expect(
        pdfPartPaidNote(3, bill3, bills.last.owed),
        allOf(contains('3,672.09'), contains('3,174.86'), contains('497.22')),
      );

      final paid = _g1Shown(_payNext(short));
      expect(paid, hasLength(3));
      expect(
        paid.last.interestPayment + paid.last.principalPayment,
        closeTo(3672.0856, 0.0001),
      );
      expect(pdfTotalPayable(loan, paid), closeTo(11016.26, 0.005));
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

    testWidgets('carried shortfall prints Total payable 11,025.29',
        (tester) async {
      final shown = _g1Shown(_payNext(const [], interest: 500, principal: 3000));
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: shown.first.amortization,
      );
      final bytes = await tester.runAsync(
        () => PdfGenerator.buildPdfBytes(
          schedules: shown,
          loan: loan,
          product: _product(),
          user: _user(),
        ),
      );
      final text = _contentText(bytes!);

      expect(text, contains('Total payable'));
      expect(text, contains('11,025.29'));
      expect(text, isNot(contains('11,197.38')));
    });

    testWidgets('part-paid last bill prints whole: Total payable 11,016.26, '
        'the paid part once', (tester) async {
      final rows = _g1Rows(
        _payNext(_payNext(_payNext(const [])), principal: 3000),
      );
      final loan = _loan(
        period: 3,
        term: '1m',
        amortization: rows.first.amortization,
      );
      final bytes = await tester.runAsync(
        () => PdfGenerator.buildPdfBytes(
          schedules: rows,
          loan: loan,
          product: _product(),
          user: _user(),
        ),
      );
      final text = _contentText(bytes!);

      expect(text, contains('11,016.26'));
      expect(text, isNot(contains('7,841.40')));
      expect(text, contains('still owed'));
      expect(RegExp(r'3,174\.86').allMatches(text), hasLength(1));
      // Three bills: the short payment is not a row of its own.
      expect(
        RegExp('2026-Apr-10').allMatches(text),
        hasLength(2),
        reason: 'bill 3 row and its note',
      );
    });
  });
}
