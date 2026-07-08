import 'package:json_annotation/json_annotation.dart';

part 'attachment.g.dart';

@JsonSerializable()
class Attachment {
  Attachment({
    required this.name,
    required this.url,
    required this.contentType,
    required this.size,
    this.thumbnailUrl,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  final String name;
  final String url;

  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;

  @JsonKey(name: 'content_type')
  final String contentType;

  final int size;

  Map<String, dynamic> toJson() => _$AttachmentToJson(this);
}
