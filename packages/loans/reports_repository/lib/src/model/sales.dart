import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sales.g.dart';

@JsonSerializable()
class Sales implements Equatable {
  Sales();

  factory Sales.fromJson(Map<String, dynamic> json) {
    return _$SalesFromJson(json);
  }

  @JsonKey(
    name: 'total_amount_released',
    defaultValue: 0,
  )
  late double totalAmountReleased;

  @JsonKey(
    name: 'total_collections',
    defaultValue: 0,
  )
  late double totalCollections;

  @JsonKey(
    name: 'total_interest_payments',
    defaultValue: 0,
  )
  late double totalInterestPayments;

  @JsonKey(
    name: 'total_principal_payments',
    defaultValue: 0,
  )
  late double totalPrincipalPayments;

  @override
  List<Object?> get props => [
        totalAmountReleased,
        totalCollections,
        totalInterestPayments,
        totalPrincipalPayments,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$SalesToJson(this);
  }
}
