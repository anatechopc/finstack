import 'package:product_repository/product_repository.dart';

typedef ChargeResult = ({double totalAmount, double totalUpfrontCollection});

typedef ChargeAmountResult = ({double amount, bool isPercentage});

typedef DetailedChargeResult = ({
  double totalAmount,
  double totalUpfrontCollection,
  double totalAdditionalCharges,
  double totalDeductions,
});

class ChargeCalculator {
  const ChargeCalculator._();

  static ChargeAmountResult parseChargeAmount(String rawAmount) {
    final isPercentage = rawAmount.contains('%');
    final amount = isPercentage
        ? double.parse(rawAmount.substring(0, rawAmount.length - 1))
        : double.parse(rawAmount);
    return (amount: amount, isPercentage: isPercentage);
  }

  static ChargeResult applyChargesAndDeductions({
    required double baseAmount,
    required List<Charge> charges,
    required List<Charge> deductions,
  }) {
    var totalAmount = baseAmount;
    var totalUpfrontCollection = 0.0;

    for (final charge in charges) {
      if (charge.isUpfrontCollection) {
        if (charge.isPercentage) {
          totalUpfrontCollection += (charge.amount / 100) * baseAmount;
        } else {
          totalUpfrontCollection += charge.amount;
        }
        continue;
      }

      if (charge.isPercentage) {
        totalAmount += (charge.amount / 100) * baseAmount;
      } else {
        totalAmount += charge.amount;
      }
    }

    for (final deduction in deductions) {
      if (deduction.isPercentage) {
        totalAmount -= (deduction.amount / 100) * baseAmount;
      } else {
        totalAmount -= deduction.amount;
      }
    }

    return (totalAmount: totalAmount, totalUpfrontCollection: totalUpfrontCollection);
  }

  static DetailedChargeResult applyChargesAndDeductionsDetailed({
    required double baseAmount,
    required List<Charge> charges,
    required List<Charge> deductions,
  }) {
    var totalAmount = baseAmount;
    var totalUpfrontCollection = 0.0;
    var totalAdditionalCharges = 0.0;
    var totalDeductions = 0.0;

    for (final charge in charges) {
      if (charge.isUpfrontCollection) {
        if (charge.isPercentage) {
          totalUpfrontCollection += (charge.amount / 100) * baseAmount;
        } else {
          totalUpfrontCollection += charge.amount;
        }
        continue;
      }

      if (charge.isPercentage) {
        final chargeAmount = (charge.amount / 100) * baseAmount;
        totalAdditionalCharges += chargeAmount;
        totalAmount += chargeAmount;
      } else {
        totalAdditionalCharges += charge.amount;
        totalAmount += charge.amount;
      }
    }

    for (final deduction in deductions) {
      if (deduction.isPercentage) {
        final chargeAmount = (deduction.amount / 100) * baseAmount;
        totalAmount -= chargeAmount;
        totalDeductions += chargeAmount;
      } else {
        totalAmount -= deduction.amount;
        totalDeductions += deduction.amount;
      }
    }

    return (
      totalAmount: totalAmount,
      totalUpfrontCollection: totalUpfrontCollection,
      totalAdditionalCharges: totalAdditionalCharges,
      totalDeductions: totalDeductions,
    );
  }
}
