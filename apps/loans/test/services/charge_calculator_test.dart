import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:product_repository/product_repository.dart';

// Golden scenario G8 (finstack#112, campaign Gate 1).
//
// Derivation (base 10000; every percentage is OF THE BASE, never of the
// running total — the contract finstack#107 must restore in loans_bloc):
//   charges:    5% of 10000 = 500;  flat 150            -> additional 650
//   upfront:    2% of 10000 = 200 (collected up front, NOT added to total)
//   deductions: 1% of 10000 = 100;  flat 50             -> deductions 150
//   totalAmount = 10000 + 650 - 150 = 10500
void main() {
  const charges = [
    Charge(
      id: 'c-pct',
      amount: 5,
      description: 'processing',
      isPercentage: true,
    ),
    Charge(id: 'c-flat', amount: 150, description: 'notarial'),
    Charge(
      id: 'c-upfront',
      amount: 2,
      description: 'advance interest',
      isPercentage: true,
      isUpfrontCollection: true,
    ),
  ];
  const deductions = [
    Charge(
      id: 'd-pct',
      amount: 1,
      description: 'insurance',
      isPercentage: true,
    ),
    Charge(id: 'd-flat', amount: 50, description: 'id card'),
  ];

  group('G8 charges trio', () {
    test('detailed: 650 charges, 200 upfront, 150 deductions, 10500 total',
        () {
      final r = ChargeCalculator.applyChargesAndDeductionsDetailed(
        baseAmount: 10000,
        charges: charges,
        deductions: deductions,
      );

      expect(r.totalAdditionalCharges, closeTo(650, 0.01));
      expect(r.totalUpfrontCollection, closeTo(200, 0.01));
      expect(r.totalDeductions, closeTo(150, 0.01));
      expect(r.totalAmount, closeTo(10500, 0.01));
    });

    test('simple variant agrees with the detailed one', () {
      final r = ChargeCalculator.applyChargesAndDeductions(
        baseAmount: 10000,
        charges: charges,
        deductions: deductions,
      );

      expect(r.totalAmount, closeTo(10500, 0.01));
      expect(r.totalUpfrontCollection, closeTo(200, 0.01));
    });

    test('parseChargeAmount reads the % suffix', () {
      expect(
        ChargeCalculator.parseChargeAmount('5%'),
        (amount: 5.0, isPercentage: true),
      );
      expect(
        ChargeCalculator.parseChargeAmount('150'),
        (amount: 150.0, isPercentage: false),
      );
    });
  });
}
