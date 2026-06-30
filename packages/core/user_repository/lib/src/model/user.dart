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
      ..mobileVerifiedAt = null
      ..companyId = companyId
      ..invitedByAdmin = false
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
      ..mobileVerifiedAt = null
      ..companyId = companyId
      ..invitedByAdmin = false
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
  }

  /// Creates a user for the admin "Add team member / Add borrower" flow. The
  /// account is provisioned server-side, so [id] is left as [NO_ID] (the
  /// backend stamps the real Firebase Auth uid). Email is required because the
  /// user is invited by email and must pass the email-verification gate.
  factory User.createInvited({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String mobileNumber,
    required String emailAddress,
    required DateTime birthDate,
    required Sex sex,
    required EmploymentDetails employmentDetails,
    String? companyId,
    ImageUrl? profilePhotoUrl,
    ImageUrl? photoWithValidIdUrl,
    String? middleName,
    String? businessName,
    String? facebookProfileUrl,
  }) {
    if (emailAddress.trim().isEmpty) {
      throw Exception('Email address is required for invited users');
    }

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
      ..emailAddress = emailAddress
      ..userRole = role
      ..profilePhotoUrl = profilePhotoUrl
      ..photoWithValidIdUrl = photoWithValidIdUrl
      ..facebookProfileUrl = facebookProfileUrl
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..mobileVerifiedAt = null
      ..companyId = companyId
      ..invitedByAdmin = false
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
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
      ..mobileVerifiedAt = null
      ..invitedByAdmin = false
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
