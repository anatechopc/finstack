import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'data_item.g.dart';

enum ItemType {
  release,
  bad_debt,
  collection,
  add_capital,
  refresh_capital;
}

@JsonSerializable()
class DataItem implements Equatable {
  DataItem();

  factory DataItem.fromJson(Map<String, dynamic> json) {
    return _$DataItemFromJson(json);
  }

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime createdAt;

  late double amount;

  late double? interest;

  late double? principal;

  /// product type or loan type
  @JsonKey(name: 'product_type')
  String? productType;

  @JsonKey(name: 'capital_id')
  String? capitalId;

  @JsonKey(name: 'loan_id')
  String? loanId;

  @JsonKey(name: 'data_type')
  late ItemType dataType;

  @override
  List<Object?> get props => [
        createdAt,
        amount,
        interest,
        principal,
        productType,
        capitalId,
        loanId,
        dataType,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$DataItemToJson(this);
  }
}
