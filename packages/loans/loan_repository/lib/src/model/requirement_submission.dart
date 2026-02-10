import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'requirement_submission.g.dart';

@JsonSerializable()
final class RequirementSubmission {

  const RequirementSubmission({
    required this.url,
    required this.name,
    required this.requirementId,
  });

  factory RequirementSubmission.fromJson(Map<String, dynamic> json) {
    return _$RequirementSubmissionFromJson(json);
  }
  /// downloadable url
  @JsonKey(toJson: _handleFileUrlToJson)
  final FileUrl url;

  /// name of the submitted requirement.
  /// name should be the same as loan requirement
  final String name;

  /// ID of the requirement
  @JsonKey(name: 'requirement_id')
  final String requirementId;

  Map<String, dynamic> toJson() => _$RequirementSubmissionToJson(this);

  static Map<String, dynamic> _handleFileUrlToJson(FileUrl url) {
    return url.toJson();
  }
}
