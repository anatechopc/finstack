import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:reports_repository/src/model/capital_usage.dart';
import 'package:reports_repository/src/model/data_item.dart';
import 'package:reports_repository/src/model/product_totals.dart';
import 'package:reports_repository/src/model/sales.dart';
import 'package:reports_repository/src/model/total_summary_item.dart';

part 'report_summary.g.dart';

@JsonSerializable()
class ReportSummary implements BaseEntity {
  ReportSummary();

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return _$ReportSummaryFromJson(json);
  }

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: _handleDateTimeFromJsonWithDefault,
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
  @JsonKey(defaultValue: NO_ID)
  late String id;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: _handleDateTimeFromJsonWithDefault,
  )
  @override
  late DateTime updatedAt;

  /// Custom fromJson that returns current timestamp if value is null
  static DateTime _handleDateTimeFromJsonWithDefault(num? value) {
    if (value == null) {
      return DateTime.timestamp();
    }
    return handleDateTimeFromJson(value);
  }

  @JsonKey(
    name: 'capital_usage',
    toJson: _handleCapitalUsageToJson,
  )
  CapitalUsage? capitalUsage;

  @JsonKey(toJson: _handleSalesToJson)
  Sales? sales;

  @JsonKey(toJson: _handleProductsToJson)
  Map<String, ProductTotals>? products;

  @JsonKey(
    name: 'total_summary',
    toJson: _handleTotalSummaryToJson,
  )
  Map<String, TotalSummaryItem>? totalSummary;

  @JsonKey(toJson: _handleDataToJson)
  Map<String, DataItem>? data;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        capitalUsage,
        sales,
        totalSummary,
        data,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$ReportSummaryToJson(this);
  }

  static Map<String, dynamic>? _handleSalesToJson(Sales? sales) {
    return sales?.toJson();
  }

  static Map<String, dynamic>? _handleCapitalUsageToJson(CapitalUsage? usage) {
    return usage?.toJson();
  }

  static Map<String, Map<String, dynamic>>? _handleProductsToJson(
      Map<String, ProductTotals>? products,) {
    return products?.map((k, v) {
      return MapEntry(k, v.toJson());
    });
  }

  static Map<String, Map<String, dynamic>>?
      _handleTotalSummaryToJson(
          Map<String, TotalSummaryItem>? totalSummary,) {
    return totalSummary?.map((k, v) {
      return MapEntry(k, v.toJson());
    });
  }

  static Map<String, Map<String, dynamic>>? _handleDataToJson(
      Map<String, DataItem>? data,) {
    return data?.map((k, v) {
      return MapEntry(k, v.toJson());
    });
  }
}
