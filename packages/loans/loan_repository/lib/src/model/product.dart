import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

@JsonSerializable()
class Product {
  Product();

  factory Product.fromJson(Map<String, dynamic> json) {
    return _$ProductFromJson(json);
  }

  late String name;

  @JsonKey(name: 'total_interest_payment')
  late double totalInterestPayment;

  @JsonKey(name: 'total_collection')
  late double totalCollection;

  Map<String, dynamic> toJson() {
    return _$ProductToJson(this);
  }
}