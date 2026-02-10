import 'package:company_repository/src/model/company_entity.dart';
import 'package:company_repository/src/model/company_management_type.dart';
import 'package:company_repository/src/model/company_type.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// NOTE: only super user can add companies
/// company admin can only change name, address
/// and description
class Company extends CompanyEntity implements BaseModel<CompanyEntity> {
  Company() : super();

  factory Company.create({
    required String name,
    required String tin,
    required String emailAddress,
    required CompanyType type,
    required CompanyManagementType managementType,
    String? tagLine,
    String? secNumber,
    ImageUrl? companyProfilePhotoUrl,
  }) {
    if (type == CompanyType.secRegistered && secNumber == null) {
      throw Exception('Please enter SEC number');
    }

    final now = DateTime.timestamp();

    return Company()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..name = name
      ..tagLine = tagLine
      ..secNumber = secNumber
      ..tin = tin
      ..companyProfilePhotoUrl = companyProfilePhotoUrl
      ..emailAddress = emailAddress
      ..totalRating = 0
      ..reviewCount = 0
      ..type = type
      ..managementType = managementType;
  }

  @override
  CompanyEntity toEntity() {
    return this;
  }
}
