import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'sales_data.g.dart';

@JsonSerializable()
class SalesData implements BaseEntity {
  SalesData();

  factory SalesData.fromJson(Map<String, dynamic> json) {
    return _$SalesDataFromJson(json);
  }

  @override
  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime updatedAt;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @override
  late String id;

  @JsonKey(name: 'product_type')
  late String productType;

  @JsonKey(name: 'loan_id')
  late String loanId;

  late double amount;

  late double interest;

  late double principal;

  @override
  List<Object?> get props => [
        createdAt,
        productType,
        loanId,
        amount,
        interest,
        principal,
        updatedAt,
        deletedAt,
        id,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$SalesDataToJson(this);
  }
}
