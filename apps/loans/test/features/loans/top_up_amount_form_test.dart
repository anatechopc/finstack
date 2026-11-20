import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/widget/top_up_amount_form.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_repository/product_repository.dart';
import 'package:storage_repository/storage_repository.dart';

// The two lines of both top-up dialogs (owner, 2026-11-20; finstack#123).
//
// G8 product (charge_calculator_test.dart), top-up of 10,000:
//   charges:    5% of 10,000 = 500; flat 150                  -> 650
//   upfront:    2% of 10,000 = 200 (isUpfrontCollection)
//   deductions: 1% of 10,000 = 100; flat 50                   -> 150
//   Added to the loan = amount + charges = 10,000 + 650 = 10,650. The
//     engine adds `topUp.amount + topUp.additionalCharges`; the upfront
//     charge is not in `additionalCharges` and deductions are not
//     subtracted (#127).
//   Cash handed over = proceedsOf = amount - deductions - upfront
//     = 10,000 - 150 - 200 = 9,650. The upfront 200 is taken from the cash,
//     not added to the loan.
//   Stored top-up (AdditionalLoanBloc): amount 10,000, additionalCharges
//     650, advanceCharges 200, deductions 150; proceeds(stored) = 9,650.
//   Before: one line "Total:" 10,500 (amount + charges - deductions), which
//     is neither figure.
// G8 without deductions: added 10,650 (owner's decision 1), cash 10,000 -
//   200 = 9,800.
// Dev product of loan l7ajZ6uJ5BxbmZMkLn8Z (5% + 150, 1% + 50, no upfront),
//   5,000: added 5,000 + 250 + 150 = 5,400; cash 5,000 - 50 - 50 = 4,900
//   (#149's warning showed 4,900).

const _pct5 = Charge(
  id: 'c-pct',
  amount: 5,
  description: 'processing',
  isPercentage: true,
);
const _flat150 = Charge(id: 'c-flat', amount: 150, description: 'notarial');
const _upfront2 = Charge(
  id: 'c-upfront',
  amount: 2,
  description: 'advance interest',
  isPercentage: true,
  isUpfrontCollection: true,
);
const _pct1 = Charge(
  id: 'd-pct',
  amount: 1,
  description: 'insurance',
  isPercentage: true,
);
const _flat50 = Charge(id: 'd-flat', amount: 50, description: 'id card');

Product _g8({bool withDeductions = true}) => Product()
  ..additionalCharges = const [_pct5, _flat150, _upfront2]
  ..deductions = withDeductions ? const [_pct1, _flat50] : const [];

Product _dev() => Product()
  ..additionalCharges = const [_pct5, _flat150]
  ..deductions = const [_pct1, _flat50];

class _Loans extends Mock implements LoanRepository {}

class _Storage extends Mock implements StorageRepository {}

void main() {
  group('the two lines', () {
    test('G8, 10,000: added 10,650, cash 9,650 (upfront 200 out of cash)',
        () {
      expect(topUpAddedToLoan(_g8(), '10000'), closeTo(10650, 0.000001));
      expect(topUpCashHandedOver(_g8(), '10000'), closeTo(9650, 0.000001));
    });

    test('G8 without deductions: added 10,650, cash 9,800', () {
      final product = _g8(withDeductions: false);
      expect(topUpAddedToLoan(product, '10000'), closeTo(10650, 0.000001));
      expect(topUpCashHandedOver(product, '10000'), closeTo(9800, 0.000001));
    });

    test('the dev product, 5,000: added 5,400, cash 4,900', () {
      expect(topUpAddedToLoan(_dev(), '5000'), closeTo(5400, 0.000001));
      expect(topUpCashHandedOver(_dev(), '5000'), closeTo(4900, 0.000001));
    });

    test('no charges and no deductions: both are the amount', () {
      final plain = Product()
        ..additionalCharges = const []
        ..deductions = const [];
      expect(topUpAddedToLoan(plain, '2500.50'), closeTo(2500.50, 0.000001));
      expect(topUpCashHandedOver(plain, '2500.50'), closeTo(2500.50, 0.000001));
    });

    test('empty, null or unparsable input: 0', () {
      for (final text in [null, '', '.']) {
        expect(topUpAddedToLoan(_g8(), text), 0, reason: '$text');
        expect(topUpCashHandedOver(_g8(), text), 0, reason: '$text');
      }
    });
  });

  test('the lines equal the top-up AdditionalLoanBloc stores (G8, 10,000)',
      () async {
    registerFallbackValue(Loan());
    registerFallbackValue(Uint8List(0));
    final loans = _Loans();
    final storage = _Storage();
    final loan = Loan()
      ..id = 'loan-1'
      ..userId = 'u1';
    Loan? written;
    when(() => loans.get(id: any(named: 'id'))).thenAnswer((_) async => loan);
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
        updateAdditionalLoanAmounts: any(named: 'updateAdditionalLoanAmounts'),
      ),
    ).thenAnswer((invocation) async {
      return written = invocation.namedArguments[#data] as Loan;
    });
    when(
      () => storage.upload(
        data: any(named: 'data'),
        folder: any(named: 'folder'),
        fileName: any(named: 'fileName'),
        uploadOriginalSize: any(named: 'uploadOriginalSize'),
        includeOriginal: any(named: 'includeOriginal'),
        forceDecodeToImage: any(named: 'forceDecodeToImage'),
      ),
    ).thenAnswer((_) async => ImageUrl(name: 'upload'));

    final bloc = AdditionalLoanBloc.withDependencies(
      loanRepository: loans,
      storageRepository: storage,
    );
    addTearDown(bloc.close);
    bloc.addLoanAmount(
      'loan-1',
      '10000',
      additionalCharges: _g8().additionalCharges,
      deductions: _g8().deductions,
      selfiePhoto: SimpleFileData('selfie.png', Uint8List(1)),
      signatureBytes: Uint8List(1),
    );
    final state = await bloc.stream.firstWhere(
      (s) =>
          s.status == AdditionalLoanStatus.success ||
          s.status == AdditionalLoanStatus.error,
    );
    expect(state.status, AdditionalLoanStatus.success, reason: state.message);

    final stored = written!.additionalLoanAmounts.single;
    expect(stored.amount, 10000);
    expect(stored.additionalCharges, closeTo(650, 0.000001));
    expect(stored.advanceCharges, closeTo(200, 0.000001));
    expect(stored.deductions, closeTo(150, 0.000001));
    expect(
      stored.amount + stored.additionalCharges,
      topUpAddedToLoan(_g8(), '10000'),
    );
    expect(
      TopUpOverdueService.proceeds(stored),
      topUpCashHandedOver(_g8(), '10000'),
    );
  });

  group('TopUpAmountForm in a dialog', () {
    Future<GlobalKey<FormBuilderState>> openDialog(
      WidgetTester tester,
      Product? product,
    ) async {
      final formKey = GlobalKey<FormBuilderState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Add loan amount'),
                  content: TopUpAmountForm(formKey: formKey, product: product),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return formKey;
    }

    String lineValue(WidgetTester tester, String label) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      final texts = tester.widgetList<Text>(
        find.descendant(of: row.first, matching: find.byType(Text)),
      );
      return texts.last.data!;
    }

    testWidgets('G8: 0 before typing, then 10,650 added and 9,650 cash',
        (tester) async {
      final formKey = await openDialog(tester, _g8());

      expect(lineValue(tester, 'Added to the loan:'), 0.0.toCurrency());
      expect(lineValue(tester, 'Cash handed over:'), 0.0.toCurrency());

      await tester.enterText(find.byType(TextField), '10000');
      await tester.pump();

      expect(lineValue(tester, 'Added to the loan:'), 10650.0.toCurrency());
      expect(lineValue(tester, 'Cash handed over:'), 9650.0.toCurrency());
      expect(find.text('Total:'), findsNothing);
      expect(find.text(10500.0.toCurrency()), findsNothing);
      // What is added to the loan, then what comes out of the cash; the
      // upfront charge is with the cash, not under "Add:".
      expect(find.text('Add: advance interest:'), findsNothing);
      expect(
        [
          'Added to the loan:',
          'Add: processing:',
          'Add: notarial:',
          'Cash handed over:',
          'Less: insurance:',
          'Less: id card:',
          'Less: advance interest (collected upfront):',
        ].map((label) => tester.getTopLeft(find.text(label)).dy).toList(),
        isA<List<double>>().having(
          (ys) => [for (var i = 1; i < ys.length; i++) ys[i] > ys[i - 1]],
          'each line below the one before',
          everyElement(isTrue),
        ),
      );
      // The dialogs' Add button reads the amount through the key.
      expect(formKey.currentState!.saveAndValidate(), isTrue);
      expect(formKey.currentState!.value['amount'], '10000');
    });

    testWidgets('the dev product, 5,000: 5,400 added and 4,900 cash',
        (tester) async {
      await openDialog(tester, _dev());
      await tester.enterText(find.byType(TextField), '5000');
      await tester.pump();

      expect(lineValue(tester, 'Added to the loan:'), 5400.0.toCurrency());
      expect(lineValue(tester, 'Cash handed over:'), 4900.0.toCurrency());
      expect(find.textContaining('(collected upfront)'), findsNothing);
    });

    testWidgets('no product: only the amount', (tester) async {
      await openDialog(tester, null);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Added to the loan:'), findsNothing);
      expect(find.text('Cash handed over:'), findsNothing);
    });
  });
}
