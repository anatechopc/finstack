import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  group('Penalty', () {
    test('round-trips through JSON with snake_case keys', () {
      const penalty = Penalty(
        id: 'abc12345',
        name: 'Late fee',
        description: 'Per day late',
        amount: 100,
        frequency: PenaltyFrequency.daily,
      );

      final json = penalty.toJson();

      expect(json, const {
        'id': 'abc12345',
        'name': 'Late fee',
        'description': 'Per day late',
        'amount': 100.0,
        'is_percentage': false,
        'frequency': 'daily',
      });
      expect(Penalty.fromJson(json), penalty);
    });

    test('fills defaults for missing keys', () {
      final penalty = Penalty.fromJson(const {
        'id': 'x',
        'name': 'Surcharge',
        'amount': 2,
      });

      expect(penalty.description, '');
      expect(penalty.isPercentage, false);
      expect(penalty.frequency, PenaltyFrequency.once);
    });

    test('unknown frequency falls back to once', () {
      final penalty = Penalty.fromJson(const {
        'id': 'x',
        'name': 'Surcharge',
        'amount': 2,
        'frequency': 'fortnightly',
      });

      expect(penalty.frequency, PenaltyFrequency.once);
    });

    test('listToJson maps every item', () {
      const a = Penalty(id: 'a', name: 'A', amount: 1);
      const b = Penalty(id: 'b', name: 'B', amount: 2, isPercentage: true);

      expect(Penalty.listToJson([a, b]), [a.toJson(), b.toJson()]);
    });

    test('per-installment frequency serializes as per_installment', () {
      const penalty = Penalty(
        id: 'p',
        name: 'Installment fee',
        amount: 100,
        frequency: PenaltyFrequency.perInstallment,
      );

      final json = penalty.toJson();

      expect(json['frequency'], 'per_installment');
      expect(Penalty.fromJson(json), penalty);
    });
  });

  group('Penalty.basedOn', () {
    test('serializes as based_on and round-trips', () {
      for (final (base, value) in [
        (PenaltyBase.missedBill, 'missed_bill'),
        (PenaltyBase.outstandingBalance, 'outstanding_balance'),
      ]) {
        final penalty = Penalty(
          id: 'p',
          name: 'Surcharge',
          amount: 10,
          isPercentage: true,
          basedOn: base,
        );

        final json = penalty.toJson();

        expect(json['based_on'], value);
        expect(Penalty.fromJson(json), penalty);
      }
    });

    test('null is not written; missing or unknown reads as null', () {
      const penalty = Penalty(id: 'p', name: 'Late fee', amount: 100);

      expect(penalty.toJson().containsKey('based_on'), isFalse);
      expect(
        Penalty.fromJson(const {'id': 'p', 'name': 'A', 'amount': 1}).basedOn,
        isNull,
      );
      expect(
        Penalty.fromJson(const {
          'id': 'p',
          'name': 'A',
          'amount': 1,
          'based_on': 'principal',
        }).basedOn,
        isNull,
      );
    });

    test('baseFor: null keeps the loan type default; a flat amount ignores it',
        () {
      const legacy = Penalty(id: 'p', name: 'A', amount: 1, isPercentage: true);
      expect(legacy.baseFor(isOpenTerm: false), PenaltyBase.missedBill);
      expect(legacy.baseFor(isOpenTerm: true), PenaltyBase.outstandingBalance);

      const onBill = Penalty(
        id: 'p',
        name: 'A',
        amount: 1,
        isPercentage: true,
        basedOn: PenaltyBase.missedBill,
      );
      expect(onBill.baseFor(isOpenTerm: true), PenaltyBase.missedBill);

      const flat = Penalty(
        id: 'p',
        name: 'A',
        amount: 100,
        basedOn: PenaltyBase.missedBill,
      );
      expect(flat.baseFor(isOpenTerm: true), PenaltyBase.outstandingBalance);
      expect(flat.baseFor(isOpenTerm: false), PenaltyBase.missedBill);
    });
  });

  group('PenaltyFrequency.periods', () {
    test('once is a single period whenever late', () {
      expect(PenaltyFrequency.once.periods(1), 1);
      expect(PenaltyFrequency.once.periods(45), 1);
    });

    test('daily counts each day', () {
      expect(PenaltyFrequency.daily.periods(19), 19);
    });

    test('monthly rounds a started 30-day month up', () {
      expect(PenaltyFrequency.monthly.periods(30), 1);
      expect(PenaltyFrequency.monthly.periods(31), 2);
    });

    test('per installment rounds a started term period up', () {
      expect(PenaltyFrequency.perInstallment.periods(15, termDays: 15), 1);
      expect(PenaltyFrequency.perInstallment.periods(16, termDays: 15), 2);
      expect(PenaltyFrequency.perInstallment.periods(30), 1);
      expect(PenaltyFrequency.perInstallment.periods(31), 2);
    });

    test('per installment treats a bad termDays as 30', () {
      expect(PenaltyFrequency.perInstallment.periods(31, termDays: 0), 2);
    });

    test('never charges when not late', () {
      for (final frequency in PenaltyFrequency.values) {
        expect(frequency.periods(0), 0, reason: frequency.name);
        expect(frequency.periods(-3), 0, reason: frequency.name);
      }
    });
  });

  group('termDaysOf', () {
    test('monthly term is 30 days', () => expect(termDaysOf('1m'), 30));
    test('twice-a-month term is 15 days', () => expect(termDaysOf('15d'), 15));
    test('two salary dates are 15 days', () => expect(termDaysOf('15,30'), 15));
    test('one salary date is 30 days', () => expect(termDaysOf('30'), 30));
    test('multi-month term scales by 30', () => expect(termDaysOf('2m'), 60));
    test('unparseable term falls back to 30', () {
      expect(termDaysOf(''), 30);
      expect(termDaysOf('weekly'), 30);
    });
  });
}
