import 'package:address_repository/src/model/address.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'address_entity.g.dart';

@JsonSerializable()
class AddressEntity implements BaseEntity {

  AddressEntity();

  AddressEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.dataId,
    required this.dataType,
    required this.line1,
    required this.barangay,
    required this.city,
    required this.province,
    required this.country,
    required this.zipCode,
  });

  factory AddressEntity.fromJson(Map<String, dynamic> json) {
    return _$AddressEntityFromJson(json);
  }
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
      fromJson: handleDateTimeNullableFromJson,)
  @override
  DateTime? deletedAt;

  @override
  late String id;

  @JsonKey(
      name: 'updated_at',
      toJson: handleDateTimeToJson,
      fromJson: handleDateTimeFromJson,)
  @override
  late DateTime updatedAt;

  @JsonKey(name: 'data_id')
  late String dataId;

  @JsonKey(name: 'data_type')
  late DataType dataType;

  late String line1;
  String? line2;
  late String barangay;
  late String city;
  late String province;
  late String country;
  @JsonKey(name: 'zip_code')
  late String zipCode;
  double? latitude;
  double? longitude;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        dataId,
        dataType,
        line1,
        line2,
        barangay,
        city,
        province,
        country,
        zipCode,
        longitude,
        latitude,
        deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$AddressEntityToJson(this);
  }

  BaseEntity toEntity() {
    throw UnimplementedError();
  }

  Address toAddress() {
    return Address()
      ..id = id
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..dataId = dataId
      ..dataType = dataType
      ..line1 = line1
      ..line2 = line2
      ..barangay = barangay
      ..city = city
      ..province = province
      ..country = country
      ..zipCode = zipCode;
  }
}
