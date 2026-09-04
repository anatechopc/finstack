import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'penalty.g.dart';

/// How often a penalty is charged while a payment is late.
enum PenaltyFrequency {
  once('One time', 'once'),
  daily('Per day', '/ day'),
  monthly('Per month', '/ month'),
  @JsonValue('per_installment')
  perInstallment('Per installment (same as loan term)', '/ installment');

  const PenaltyFrequency(this.label, this.suffix);

  /// Dropdown label, e.g. "Per day".
  final String label;

  /// Chip suffix, e.g. "/ day".
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
  });

  factory Penalty.fromJson(Map<String, dynamic> json) {
    return _$PenaltyFromJson(json);
  }

  final String id;
  final String name;

  @JsonKey(defaultValue: '')
  final String description;

  /// Fixed amount, or a percent (0–100) of the installment when
  /// [isPercentage] is true.
  final double amount;

  @JsonKey(name: 'is_percentage', defaultValue: false)
  final bool isPercentage;

  @JsonKey(
    defaultValue: PenaltyFrequency.once,
    unknownEnumValue: PenaltyFrequency.once,
  )
  final PenaltyFrequency frequency;

  Map<String, dynamic> toJson() {
    return _$PenaltyToJson(this);
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
      ];
}
