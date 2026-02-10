import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'total_summary_item.g.dart';

@JsonSerializable()
class TotalSummaryItem implements Equatable {
  TotalSummaryItem();

  factory TotalSummaryItem.fromJson(Map<String, dynamic> json) {
    return _$TotalSummaryItemFromJson(json);
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
    return _$TotalSummaryItemToJson(this);
  }
}
