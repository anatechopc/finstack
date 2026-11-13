import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/users/widget/client_detail/top_up_total_row.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:product_repository/product_repository.dart';

// finstack#123. G8 product (charge_calculator_test.dart), top-up of 10,000:
//   charges:    5% of 10000 = 500;  flat 150            -> +650
//   upfront:    2% of 10000 = 200 (collected up front, not in the total)
//   deductions: 1% of 10000 = 100;  flat 50             -> -150
//   total = 10000 + 650 - 150 = 10500
// The old ProductBloc helpers showed 20600:
//   (10000 + 650 - 200) - (-150 - 10000) = 10450 + 10150 = 20600.
// Without deductions the total is 10000 + 650 = 10650 (the old helper showed
// 10450 because it subtracted the upfront charge).
Product _g8({bool withDeductions = true}) => Product()
  ..additionalCharges = const [
    Charge(id: 'c-pct', amount: 5, description: 'processing', isPercentage: true),
    Charge(id: 'c-flat', amount: 150, description: 'notarial'),
    Charge(
      id: 'c-upfront',
      amount: 2,
      description: 'advance interest',
      isPercentage: true,
      isUpfrontCollection: true,
    ),
  ]
  ..deductions = withDeductions
      ? const [
          Charge(
            id: 'd-pct',
            amount: 1,
            description: 'insurance',
            isPercentage: true,
          ),
          Charge(id: 'd-flat', amount: 50, description: 'id card'),
        ]
      : const [];

void main() {
  group('topUpDialogTotal', () {
    test('G8 with deductions: 10500', () {
      expect(topUpDialogTotal(_g8(), '10000'), closeTo(10500, 0.001));
    });

    test('G8 without deductions: 10650', () {
      expect(
        topUpDialogTotal(_g8(withDeductions: false), '10000'),
        closeTo(10650, 0.001),
      );
    });

    test('no charges and no deductions: the amount itself', () {
      final plain = Product()
        ..additionalCharges = const []
        ..deductions = const [];
      expect(topUpDialogTotal(plain, '2500.50'), closeTo(2500.50, 0.001));
    });

    test('empty, null or unparsable input: 0', () {
      expect(topUpDialogTotal(_g8(), null), 0);
      expect(topUpDialogTotal(_g8(), ''), 0);
      expect(topUpDialogTotal(_g8(), '.'), 0);
    });
  });

  group('TopUpTotalRow', () {
    testWidgets('renders the G8 total as 10,500.00', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopUpTotalRow(product: _g8(), amountText: '10000'),
          ),
        ),
      );

      expect(find.text('Total:'), findsOneWidget);
      expect(find.text(10500.toCurrency()), findsOneWidget);
      expect(find.text(20600.toCurrency()), findsNothing);
    });
  });
}
