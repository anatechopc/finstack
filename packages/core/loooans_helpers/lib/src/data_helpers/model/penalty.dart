import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'penalty.g.dart';

/// How often a penalty is charged while a payment is late.
enum PenaltyFrequency {
  once('One time', 'once'),
  daily('Per day', '/ day'),
  weekly('Per week', '/ week'),
  monthly('Per month', '/ month');

  const PenaltyFrequency(this.label, this.suffix);

  /// Dropdown label, e.g. "Per day".
  final String label;

  /// Chip suffix, e.g. "/ day".
  final String suffix;

  /// Number of penalty periods for a payment that is [daysLate] days late.
  /// A started period counts in full. Not late means no periods.
  int periods(int daysLate) {
    if (daysLate <= 0) {
      return 0;
    }

    return switch (this) {
      PenaltyFrequency.once => 1,
      PenaltyFrequency.daily => daysLate,
      PenaltyFrequency.weekly => (daysLate / 7).ceil(),
      PenaltyFrequency.monthly => (daysLate / 30).ceil(),
    };
  }
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
