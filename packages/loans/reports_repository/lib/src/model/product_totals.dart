import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_totals.g.dart';

@JsonSerializable()
class ProductTotals implements Equatable {
  ProductTotals();

  factory ProductTotals.fromJson(Map<String, dynamic> json) {
    return _$ProductTotalsFromJson(json);
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

  @JsonKey(
    name: 'total_bad_debts',
    defaultValue: 0,
  )
  late double totalBadDebts;

  @override
  List<Object?> get props => [
        totalAmountReleased,
        totalCollections,
        totalInterestPayments,
        totalPrincipalPayments,
        totalBadDebts,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$ProductTotalsToJson(this);
  }
}
