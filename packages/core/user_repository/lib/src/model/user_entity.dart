import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/employment_details.dart';
import 'package:user_repository/src/model/sex.dart';
import 'package:user_repository/src/model/user.dart';
import 'package:user_repository/src/model/user_role.dart';

part 'user_entity.g.dart';

/// Data transfer object (DTO) that models how
/// user data is stored in database
@JsonSerializable()
class UserEntity implements BaseEntity {
  UserEntity();

  UserEntity._({
    required this.updatedAt,
    required this.createdAt,
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.birthDate,
    required this.mobileNumber,
    required this.emailAddress,
    required this.userRole,
    required this.profilePhotoUrl,
    required this.photoWithValidIdUrl,
    required this.karma,
    required this.verificationStatus,
  });

  /// convert from json to entity
  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @override
  late String id;

  @JsonKey(name: 'last_name')
  late String lastName;

  @JsonKey(name: 'first_name')
  late String firstName;

  @JsonKey(name: 'middle_name')
  String? middleName;

  @JsonKey(
    name: 'birth_date',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime birthDate;

  @JsonKey(name: 'mobile_number')
  late String mobileNumber;

  @JsonKey(name: 'email_address')
  late String emailAddress;

  @JsonKey(name: 'user_role')
  late UserRole userRole;

  @JsonKey(
    name: 'profile_photo_url',
    toJson: handleImageUrlToJson,
  )
  late ImageUrl? profilePhotoUrl;

  @JsonKey(
    name: 'photo_with_valid_id_url',
    toJson: handleImageUrlToJson,
  )
  late ImageUrl? photoWithValidIdUrl;

  @JsonKey(name: 'facebook_profile_url')
  String? facebookProfileUrl;

  /// for selfManaged users, this is labelled
  /// as Credit Score
  @JsonKey(defaultValue: 0)
  late double karma;

  @JsonKey(name: 'ai_verify_ref')
  String? aiVerifyRef;

  @JsonKey(
    name: 'mobile_verified_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? mobileVerifiedAt;

  /// verification status uses bitwise or operation
  /// to determine how many verification steps the user
  /// has passed.
  late int verificationStatus;

  /// Normally, companyId is reserved only to those users that are
  /// connected to a loan provider with the following user roles
  /// e.g admin, loan_office, reviewer.
  /// But, with the introduction of self managed companies
  /// [CompanyManagementType.selfManaged, a customer user should have
  /// a companyId. The companyId means to these users that they are
  /// customers of the company
  @JsonKey(name: 'company_id')
  String? companyId;

  /// True when the account was provisioned by a company admin via the
  /// addUser Cloud Function. The userCreated trigger checks this flag to
  /// suppress the generic "Verify your account" welcome email (admin-invited
  /// users receive the set-password invite instead).
  @JsonKey(name: 'invited_by_admin', defaultValue: false)
  late bool invitedByAdmin;

  /// Mandatory, but defaults to [Sex.other] for older/incomplete user
  /// documents that have no (or an unrecognized) `sex`, so login never crashes
  /// while keeping the field non-nullable. New users set it via registration.
  @JsonKey(defaultValue: Sex.other, unknownEnumValue: Sex.other)
  late Sex sex;

  @JsonKey(name: 'business_name')
  String? businessName;

  /// Defaults to a blank record when the document has no `employment_details`
  /// (e.g. customers who never filled them in) so login does not crash on a
  /// null map — see [_handleEmploymentDetailsFromJson].
  @JsonKey(
    name: 'employment_details',
    toJson: _handleEmploymentDetailsToJson,
    fromJson: _handleEmploymentDetailsFromJson,
  )
  late EmploymentDetails employmentDetails;

  /// converts User entity to user model
  User toUser() {
    return User()
      ..deletedAt = deletedAt
      ..updatedAt = updatedAt
      ..createdAt = createdAt
      ..id = id
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
      ..karma = karma
      ..aiVerifyRef = aiVerifyRef
      ..verificationStatus = verificationStatus
      ..mobileVerifiedAt = mobileVerifiedAt
      ..companyId = companyId
      ..invitedByAdmin = invitedByAdmin
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
  }

  @override
  List<Object?> get props => [
        deletedAt,
        updatedAt,
        createdAt,
        id,
        lastName,
        firstName,
        middleName,
        birthDate,
        mobileNumber,
        emailAddress,
        userRole,
        profilePhotoUrl,
        photoWithValidIdUrl,
        facebookProfileUrl,
        karma,
        aiVerifyRef,
        verificationStatus,
        mobileVerifiedAt,
        companyId,
        invitedByAdmin,
        sex,
        employmentDetails,
        businessName,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$UserEntityToJson(this);

  static Map<String, dynamic> _handleEmploymentDetailsToJson(
    EmploymentDetails details,
  ) {
    return details.toJson();
  }

  static EmploymentDetails _handleEmploymentDetailsFromJson(
    Map<String, dynamic>? json,
  ) {
    return json == null
        ? EmploymentDetails.createBlank()
        : EmploymentDetails.fromJson(json);
  }
}
