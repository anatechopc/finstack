import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/penalty_dialog.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  group('penaltyFromFields', () {
    test('parses a fixed amount', () {
      final penalty = penaltyFromFields({
        'amount': '100',
        'name': 'Late fee',
        'description': 'Per day late',
        'frequency': PenaltyFrequency.daily,
      });

      expect(penalty.id, hasLength(8));
      expect(penalty.name, 'Late fee');
      expect(penalty.description, 'Per day late');
      expect(penalty.amount, 100);
      expect(penalty.isPercentage, false);
      expect(penalty.frequency, PenaltyFrequency.daily);
    });

    test('a trailing percent sign means percentage', () {
      final penalty = penaltyFromFields({
        'amount': '2.5%',
        'name': 'Surcharge',
        'frequency': PenaltyFrequency.monthly,
      });

      expect(penalty.amount, 2.5);
      expect(penalty.isPercentage, true);
      expect(penalty.description, '');
    });

    test('missing frequency defaults to once', () {
      final penalty = penaltyFromFields({'amount': '500', 'name': 'Cheque'});

      expect(penalty.frequency, PenaltyFrequency.once);
    });
  });

  group('validatePenaltyAmount', () {
    const accepted = <String>['100', '0.5', '5.', '2.5%', '100%'];
    const rejected = <String>['0', '-1', '5.5.5', '%', '0%', '100.1%', 'abc'];

    test('accepts positive amounts and percentages up to 100', () {
      for (final value in accepted) {
        expect(validatePenaltyAmount(value), isNull, reason: value);
      }
    });

    test('rejects zero, negatives, malformed and percentages over 100', () {
      for (final value in rejected) {
        expect(validatePenaltyAmount(value), isNotNull, reason: value);
      }
    });

    test('leaves empty input to the required validator', () {
      expect(validatePenaltyAmount(null), isNull);
      expect(validatePenaltyAmount(''), isNull);
    });
  });

  group('PenaltyLabels', () {
    test('formats fixed and percentage amounts with the frequency suffix', () {
      const fixed = Penalty(
        id: 'a',
        name: 'Late fee',
        amount: 100,
        frequency: PenaltyFrequency.daily,
      );
      const pct = Penalty(
        id: 'b',
        name: 'Surcharge',
        amount: 2,
        isPercentage: true,
        frequency: PenaltyFrequency.monthly,
      );

      expect(fixed.amountLabel, '${100.0.toCurrency()} / day');
      expect(fixed.chipLabel, 'Late fee · ${100.0.toCurrency()} / day');
      expect(pct.amountLabel, '2% / month');
    });
  });
}
