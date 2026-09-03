import 'package:company_repository/company_repository.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'company_entity.g.dart';

/// NOTE:
///
@JsonSerializable()
class CompanyEntity implements BaseEntity {
  CompanyEntity();

  CompanyEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.name,
    required this.tin,
    required this.emailAddress,
    required this.totalRating,
    required this.reviewCount,
    required this.type,
    required this.managementType,
  });

  factory CompanyEntity.fromJson(Map<String, dynamic> json) {
    return _$CompanyEntityFromJson(json);
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

  @override
  late String id;

  late String name;

  @JsonKey(name: 'tag_line')
  String? tagLine;

  @JsonKey(name: 'sec_number')
  String? secNumber;

  late String tin;

  @JsonKey(
    name: 'company_profile_photo_url',
    toJson: handleImageUrlToJson,
  )
  ImageUrl? companyProfilePhotoUrl;

  /// email address of the provider
  @JsonKey(name: 'email_address')
  late String emailAddress;

  @JsonKey(
    name: 'total_rating',
    defaultValue: 0,
  )
  late double totalRating;

  @JsonKey(
    name: 'review_count',
    defaultValue: 0,
  )
  late int reviewCount;

  late CompanyType type;

  /// refers to how the company is managed.
  ///
  /// if managementType == app, clients or customers of the company
  /// are app-regulated and app-registered
  ///
  /// if managementType == selfManaged, clients or customers of the
  /// company are managed by the company itself.
  ///
  /// This is especially important if the managementType of the company
  /// is selfManaged to determine how they are getting the clients.
  @JsonKey(
    name: 'management_type',
    defaultValue: CompanyManagementType.app,
  )
  late CompanyManagementType managementType;

  /// Penalties every new product of this company starts with. Copied into
  /// the product at creation; editing these does not touch existing products.
  @JsonKey(
    name: 'default_penalties',
    defaultValue: [],
    toJson: Penalty.listToJson,
  )
  List<Penalty> defaultPenalties = [];

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        name,
        tagLine,
        secNumber,
        tin,
        companyProfilePhotoUrl,
        emailAddress,
        totalRating,
        reviewCount,
        type,
        managementType,
        defaultPenalties,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$CompanyEntityToJson(this);
  }

  Company toCompany() {
    return Company()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..name = name
      ..tagLine = tagLine
      ..secNumber = secNumber
      ..tin = tin
      ..companyProfilePhotoUrl = companyProfilePhotoUrl
      ..emailAddress = emailAddress
      ..totalRating = totalRating
      ..reviewCount = reviewCount
      ..type = type
      ..managementType = managementType
      ..defaultPenalties = defaultPenalties;
  }
}
