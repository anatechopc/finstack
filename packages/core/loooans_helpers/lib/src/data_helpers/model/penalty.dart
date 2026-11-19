import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'penalty.g.dart';

/// How often a penalty is charged while a payment is late.
enum PenaltyFrequency {
  once('One time', 'once'),
  daily('Per day', 'per day'),
  monthly('Per month', 'per month'),
  @JsonValue('per_installment')
  perInstallment('Per installment (same as loan term)', 'per installment');

  const PenaltyFrequency(this.label, this.suffix);

  /// Dropdown label, e.g. "Per day".
  final String label;

  /// Label suffix, e.g. "per day".
  final String suffix;

  /// Number of penalty periods for a payment that is [daysLate] days late.
  /// A started period counts in full. Not late means no periods.
  ///
  /// [termDays] is the loan's installment period in days (see [termDaysOf]);
  /// only [perInstallment] uses it. Months are 30 days by convention.
  int periods(int daysLate, {int termDays = 30}) {
    if (daysLate <= 0) {
      return 0;
    }

    final installmentDays = termDays < 1 ? 30 : termDays;

    return switch (this) {
      PenaltyFrequency.once => 1,
      PenaltyFrequency.daily => daysLate,
      PenaltyFrequency.monthly => (daysLate / 30).ceil(),
      PenaltyFrequency.perInstallment => (daysLate / installmentDays).ceil(),
    };
  }
}

/// What a percentage penalty is a percent of, which also decides how it is
/// counted (owner, 2026-11-19): one on the missed bill is charged per missed
/// bill, each bill counting its own days late; one on the outstanding
/// balance is charged once for the loan per overdue stretch.
enum PenaltyBase {
  @JsonValue('missed_bill')
  missedBill('The missed bill', 'of the missed bill'),
  @JsonValue('outstanding_balance')
  outstandingBalance('The outstanding balance', 'of the balance');

  const PenaltyBase(this.label, this.phrase);

  /// Dialog option, e.g. "The missed bill".
  final String label;

  /// In a penalty's label, e.g. "10% of the missed bill, once".
  final String phrase;
}

/// Installment period in days for a product or loan `term`.
///
/// `1m` → 30, `15d` → 15, two salary dates such as `15,30` → 15, a single
/// salary date → 30, anything unparseable → 30. Months are 30 days by the
/// repo's convention (see `LoanScheduleEntity.interestDayMultiplier`).
int termDaysOf(String term) {
  final trimmed = term.trim();

  if (trimmed.contains(',')) {
    final dates = trimmed.split(',').where((s) => s.trim().isNotEmpty);
    return dates.length >= 2 ? 15 : 30;
  }

  final match = RegExp(r'^(\d+)([dm])$').firstMatch(trimmed);
  if (match == null) {
    return 30;
  }

  final count = int.parse(match.group(1)!);
  if (count < 1) {
    return 30;
  }

  return match.group(2) == 'd' ? count : count * 30;
}

/// A late-payment penalty definition.
///
/// Lives on a company as a default, on a product as the offer's terms, and is
/// copied onto a loan at creation so the borrower is bound by the terms they
/// applied under.
@JsonSerializable()
class Penalty extends Equatable {
  const Penalty({
    required this.id,
    required this.name,
    required this.amount,
    this.description = '',
    this.isPercentage = false,
    this.frequency = PenaltyFrequency.once,
    this.basedOn,
  });

  factory Penalty.fromJson(Map<String, dynamic> json) {
    return _$PenaltyFromJson(json);
  }

  final String id;
  final String name;

  @JsonKey(defaultValue: '')
  final String description;

  /// Fixed amount, or a percent (0–100) of [baseFor] when [isPercentage] is
  /// true.
  final double amount;

  @JsonKey(name: 'is_percentage', defaultValue: false)
  final bool isPercentage;

  @JsonKey(
    defaultValue: PenaltyFrequency.once,
    unknownEnumValue: PenaltyFrequency.once,
  )
  final PenaltyFrequency frequency;

  /// The lender's "Based on" choice. Null on flat amounts and on penalties
  /// saved before the option existed (2026-11-19): see [baseFor]. Not
  /// written when null, so those documents keep their shape.
  @JsonKey(
    name: 'based_on',
    unknownEnumValue: JsonKey.nullForUndefinedEnumValue,
  )
  final PenaltyBase? basedOn;

  /// The base in force on a loan of this type. A flat amount is charged as
  /// entered, and it and a penalty without [basedOn] keep the loan type's
  /// default: the missed installment on a fixed-term loan, the outstanding
  /// balance on an open-term loan (so existing loans do not change).
  PenaltyBase baseFor({required bool isOpenTerm}) =>
      (isPercentage ? basedOn : null) ??
      (isOpenTerm ? PenaltyBase.outstandingBalance : PenaltyBase.missedBill);

  Map<String, dynamic> toJson() {
    return _$PenaltyToJson(this)
      ..removeWhere((key, value) => key == 'based_on' && value == null);
  }

  /// For `@JsonKey(toJson: Penalty.listToJson)` on `List<Penalty>` fields.
  /// Firestore needs plain maps, not objects.
  static List<Map<String, dynamic>> listToJson(List<Penalty> penalties) {
    return penalties.map((p) => p.toJson()).toList();
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        amount,
        isPercentage,
        frequency,
        basedOn,
      ];
}
