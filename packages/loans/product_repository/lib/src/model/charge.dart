import 'package:json_annotation/json_annotation.dart';

part 'charge.g.dart';

@JsonSerializable()
final class Charge {
  const Charge({
    required this.id,
    required this.amount,
    required this.description,
    this.isPercentage = false,
    this.isUpfrontCollection = false,
  });

  factory Charge.fromJson(Map<String, dynamic> json) {
    return _$ChargeFromJson(json);
  }

  final double amount;
  final String description;
  final String id;
  @JsonKey(name: 'is_percentage')
  final bool isPercentage;

  /// these are charges that are collected upfront.
  @JsonKey(
    name: 'is_upfront_collection',
    defaultValue: false,
  )
  final bool isUpfrontCollection;

  Map<String, dynamic> toJson() {
    return _$ChargeToJson(this);
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
