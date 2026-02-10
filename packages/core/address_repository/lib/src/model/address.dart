import 'package:address_repository/src/model/address_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class Address extends AddressEntity implements BaseModel<AddressEntity> {
  Address() : super();

  factory Address.create({
    required String dataId,
    required DataType dataType,
    required String line1,
    required String barangay,
    required String city,
    required String province,
    required String country,
    required String zipCode,
    String? line2,
  }) {
    final now = DateTime.timestamp();
    return Address()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
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

  factory Address.createIncomplete({
    required String line1,
    required String barangay,
    required String city,
    required String province,
    required String country,
    required String zipCode,
    String? line2,
  }) {
    final now = DateTime.timestamp();
    return Address()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
      ..dataId = NO_ID
      ..dataType = DataType.user
      ..line1 = line1
      ..line2 = line2
      ..barangay = barangay
      ..city = city
      ..province = province
      ..country = country
      ..zipCode = zipCode;
  }

  factory Address.noAddress({
    required DataType dataType,
  }) {
    final now = DateTime.timestamp();
    return Address()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
      ..dataId = NO_ID
      ..dataType = dataType
      ..line1 = 'No address'
      ..line2 = ''
      ..barangay = ''
      ..city = ''
      ..province = ''
      ..country = ''
      ..zipCode = '';
  }

  @override
  AddressEntity toEntity() {
    return this;
  }

  String get completeAddress {
    if (line1.toLowerCase() == 'no address') {
      return 'No address for ${dataType.name}';
    }

    return '$line1 ${line2 != null ? "$line2" : ''} $barangay\n$city, $province, $country, $zipCode';
  }

  String get completeAddress1Line {
    if (line1.toLowerCase() == 'no address') {
      return 'No address for ${dataType.name}';
    }

    return '$line1 ${line2 != null ? "$line2" : ''} $barangay $city, $province, $country, $zipCode';
  }

  @override
  String toString() {
    return '$line1\n${line2 != null ? "$line2\n" : ''}'
        '$barangay\n'
        '$city, $province\n'
        '$country, $zipCode';
  }
}
