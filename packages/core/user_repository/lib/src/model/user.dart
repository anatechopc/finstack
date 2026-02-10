import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/user_entity.dart';
import 'package:user_repository/user_repository.dart';

/// user model
class User extends UserEntity implements BaseModel<UserEntity> {
  /// default constructor
  User() : super();

  /// creates a new user model
  factory User.create({
    required String uid,
    required String firstName,
    required String lastName,
    required String mobileNumber,
    required String emailAddress,
    required ImageUrl profilePhotoUrl,
    required ImageUrl photoWithValidIdUrl,
    required UserRole userRole,
    required DateTime birthDate,
    required Sex sex,
    required EmploymentDetails employmentDetails,
    String? businessName,
    String? facebookProfileUrl,
    String? middleName,
    String? companyId,
  }) {
    if (userRole.index > UserRole.customer.index && companyId == null) {
      throw Exception(
          'Please supply companyId for user $lastName, $firstName with role ${userRole.label}',);
    } else if (userRole == UserRole.customer && facebookProfileUrl == null) {
      throw Exception('Please enter facebook profile url.');
    }

    final now = DateTime.timestamp();

    return User()
      ..id = uid
      ..updatedAt = now
      ..createdAt = now
      ..lastName = lastName
      ..firstName = firstName
      ..middleName = middleName
      ..birthDate = birthDate
      ..mobileNumber = mobileNumber
      ..emailAddress = emailAddress
      ..userRole = userRole
      ..profilePhotoUrl = profilePhotoUrl
      ..photoWithValidIdUrl = photoWithValidIdUrl
      ..facebookProfileUrl = facebookProfileUrl
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..companyId = companyId
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
  }

  /// creates a new user model for a company managed user
  factory User.createManagedUser({
    required String uid,
    required String firstName,
    required String lastName,
    required String mobileNumber,
    required String emailAddress,
    required UserRole userRole, required DateTime birthDate, required Sex sex, required EmploymentDetails employmentDetails, ImageUrl? profilePhotoUrl,
    ImageUrl? photoWithValidIdUrl,
    String? businessName,
    String? facebookProfileUrl,
    String? middleName,
    String? companyId,
  }) {
    if (userRole.index > UserRole.customer.index && companyId == null) {
      throw Exception(
          'Please supply companyId for user $lastName, $firstName with role ${userRole.label}',);
    } else if (userRole == UserRole.customer && facebookProfileUrl == null) {
      throw Exception('Please enter facebook profile url.');
    }

    final now = DateTime.timestamp();

    return User()
      ..id = uid
      ..updatedAt = now
      ..createdAt = now
      ..lastName = lastName
      ..firstName = firstName
      ..middleName = middleName
      ..birthDate = birthDate
      ..mobileNumber = mobileNumber
      ..emailAddress = emailAddress
      ..userRole = userRole
      ..profilePhotoUrl = profilePhotoUrl
      ..photoWithValidIdUrl = photoWithValidIdUrl
      ..facebookProfileUrl = facebookProfileUrl
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..companyId = companyId
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
  }

  /// creates a new user model for a company managed customer
  factory User.createManagedCustomer({
    required String firstName,
    required String lastName,
    required String mobileNumber,
    required ImageUrl? profilePhotoUrl, required ImageUrl? photoWithValidIdUrl, required DateTime birthDate, required Sex sex, required EmploymentDetails employmentDetails, required String companyId, String? emailAddress,
    String? middleName,
    String? businessName,
  }) {
    final now = DateTime.timestamp();

    return User()
      ..id = NO_ID
      ..updatedAt = now
      ..createdAt = now
      ..lastName = lastName
      ..firstName = firstName
      ..middleName = middleName
      ..birthDate = birthDate
      ..mobileNumber = mobileNumber
      ..emailAddress = emailAddress ?? ''
      ..userRole = UserRole.customer
      ..profilePhotoUrl = profilePhotoUrl
      ..photoWithValidIdUrl = photoWithValidIdUrl
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName
      ..companyId = companyId;
  }

  factory User.createPlaceholder({
    required String lastName,
    String? firstName,
  }) {
    final now = DateTime.timestamp();

    return User()
      ..isPlaceholder = true
      ..id = NO_ID
      ..updatedAt = now
      ..createdAt = now
      ..lastName = lastName
      ..firstName = firstName ?? ''
      ..middleName = ''
      ..birthDate = now
      ..mobileNumber = ''
      ..emailAddress = ''
      ..userRole = UserRole.customer
      ..profilePhotoUrl = null
      ..photoWithValidIdUrl = null
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..sex = Sex.male
      ..employmentDetails = EmploymentDetails.createBlank()
      ..businessName = null;
  }

  bool isPlaceholder = false;

  String get initials => (firstName[0] + lastName[0]).toUpperCase();

  @override
  UserEntity toEntity() {
    return this;
  }

  String get completeNameEasternOrder =>
      '$lastName, $firstName${middleName != null ? ' $middleName' : ''}';

  String get completeNameWesternOrder =>
      '$firstName${middleName != null ? ' $middleName' : ''} $lastName';
}
