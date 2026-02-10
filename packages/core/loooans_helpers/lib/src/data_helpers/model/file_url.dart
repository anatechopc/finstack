import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/src/data_helpers/constants.dart';

part 'file_url.g.dart';

@JsonSerializable()
class FileUrl extends Equatable {
  FileUrl({
    required String name,
    required String url,
  }) : this._(
          name: name,
          url: url,
        );

  FileUrl._({
    required this.name,
    required this.url,
  }) : createdAt = DateTime.timestamp();

  factory FileUrl.fromJson(Map<String, dynamic> json) {
    return _$FileUrlFromJson(json);
  }

  late final String name;
  late final String url;
  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return _$FileUrlToJson(this);
  }

  @override
  List<Object?> get props => [
        createdAt,
        name,
        url,
      ];
}
