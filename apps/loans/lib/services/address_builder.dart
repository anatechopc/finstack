import 'package:address_repository/address_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';

class AddressBuilder {
  const AddressBuilder._();

  static Address buildFromFields(
    Map<String, dynamic> fields, {
    String? dataId,
    DataType? dataType,
  }) {
    if (dataId != null && dataType != null) {
      return Address.create(
        dataId: dataId,
        dataType: dataType,
        line1: fields['line_1'] as String,
        line2: fields['line_2'] as String?,
        barangay: fields['barangay'] as String,
        city: fields['city'] as String,
        province: fields['province'] as String,
        country: fields['country'] as String,
        zipCode: fields['zip'] as String,
      );
    }

    return Address.createIncomplete(
      line1: fields['line_1'] as String,
      line2: fields['line_2'] as String?,
      barangay: fields['barangay'] as String,
      city: fields['city'] as String,
      province: fields['province'] as String,
      country: fields['country'] as String,
      zipCode: fields['zip'] as String,
    );
  }

  static void updateFromFields(Address address, Map<String, dynamic> fields) {
    address
      ..line1 = fields['line_1'] as String
      ..line2 = fields['line_2'] as String?
      ..barangay = fields['barangay'] as String
      ..city = fields['city'] as String
      ..province = fields['province'] as String
      ..country = fields['country'] as String
      ..zipCode = fields['zip'] as String;
  }
}
