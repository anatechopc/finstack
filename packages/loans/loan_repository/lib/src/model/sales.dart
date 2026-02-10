import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/src/model/product.dart';
import 'package:loan_repository/src/model/sales_data.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'sales.g.dart';

@JsonSerializable()
class Sales implements BaseEntity {
  Sales();

  factory Sales.fromJson(Map<String, dynamic> json) {
    return _$SalesFromJson(json);
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

  @JsonKey(name: 'total_collections')
  late double totalCollections;

  @JsonKey(name: 'total_interest_payments')
  late double totalInterestPayments;

  @JsonKey(toJson: _handleProductToJson)
  late Map<String, Product> products;

  @JsonKey(toJson: _handleDataToJson)
  late Map<String, Map<String, Map<String, Map<String, SalesData>>>> data;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        totalCollections,
        totalInterestPayments,
        products,
        data,
      ];

  @override
  bool? get stringify => true;

  static Map<String, Map<String, dynamic>> _handleProductToJson(
      Map<String, Product> products,) {
    return products.map((key, value) {
      return MapEntry(key, value.toJson());
    });
  }

  static Map<String,
          Map<String, Map<String, Map<String, Map<String, dynamic>>>>>
      _handleDataToJson(
          Map<String, Map<String, Map<String, Map<String, SalesData>>>> data,) {
    return data.map((k, v) {
      return MapEntry(k, v.map((k2, v2) {
        return MapEntry(k2, v2.map((k3, v3) {
          return MapEntry(k3, v3.map((k4, v4) {
            return MapEntry(k4, v4.toJson());
          }),);
        }),);
      }),);
    });
  }

  Map<String, dynamic> toJson() {
    return _$SalesToJson(this);
  }
}
