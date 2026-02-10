import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'capital_usage.g.dart';

@JsonSerializable()
class CapitalUsage implements Equatable {
  CapitalUsage();

  factory CapitalUsage.fromJson(Map<String, dynamic> json) {
    return _$CapitalUsageFromJson(json);
  }

  @JsonKey(
    name: 'total_capital',
    defaultValue: 0,
  )
  late double totalCapital;

  @JsonKey(
    name: 'total_bad_debts',
    defaultValue: 0,
  )
  late double totalBadDebts;

  @override
  List<Object?> get props => [
        totalCapital,
        totalBadDebts,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$CapitalUsageToJson(this);
  }
}
