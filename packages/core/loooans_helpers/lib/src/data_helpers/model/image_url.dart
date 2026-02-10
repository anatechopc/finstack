import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'image_url.g.dart';

@JsonSerializable()
class ImageUrl extends Equatable {

  /// container of image urls
  ImageUrl({
    required this.name,
    this.thumbnail,
    this.original,
    this.isPrimary = false,
  });

  factory ImageUrl.fromJson(Map<String, dynamic> json) {
    return _$ImageUrlFromJson(json);
  }
  final String name;
  final String? thumbnail;
  final String? original;
  final DateTime createdAt = DateTime.timestamp();
  @JsonKey(name: 'is_primary', defaultValue: false)
  final bool isPrimary;

  String get url {
    if (thumbnail != null) {
      return thumbnail!;
    }

    if (original != null) {
      return original!;
    }

    throw Exception('no image found');
  }

  Map<String, dynamic> toJson() {
    return _$ImageUrlToJson(this);
  }

  @override
  List<Object?> get props => [
    thumbnail,
    original,
    createdAt,
    name,
    isPrimary,
  ];
}
