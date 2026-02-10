import 'package:json_annotation/json_annotation.dart';

part 'requirement.g.dart';

@JsonSerializable()
final class Requirement {
  Requirement({
    required this.id,
    required this.name,
    required this.quantity,
  });

  factory Requirement.fromJson(Map<String, dynamic> json) {
    return _$RequirementFromJson(json);
  }

  final String id;
  final String name;
  int quantity;

  Map<String, dynamic> toJson() {
    return _$RequirementToJson(this);
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
