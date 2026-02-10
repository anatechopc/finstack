import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/employment_status.dart';

part 'employment_details.g.dart';

@JsonSerializable()
class EmploymentDetails implements BaseEntity {
  EmploymentDetails();

  factory EmploymentDetails.fromJson(Map<String, dynamic> json) {
    return _$EmploymentDetailsFromJson(json);
  }

  factory EmploymentDetails.createBlank() {
    final now = DateTime.timestamp();

    return EmploymentDetails()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..userId = NO_ID
      ..employmentStatus = EmploymentStatus.selfEmployed
      ..salaryDays = [];
  }

  EmploymentDetails._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
    required this.employmentStatus,
  });

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

  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'employment_status')
  late EmploymentStatus employmentStatus;

  @JsonKey(name: 'employer_name')
  String? employerName;

  @JsonKey(name: 'salary_days')
  late List<int> salaryDays;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        userId,
        employmentStatus,
        employerName,
        salaryDays,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$EmploymentDetailsToJson(this);
  }
}
