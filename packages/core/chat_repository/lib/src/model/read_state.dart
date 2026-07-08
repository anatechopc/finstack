import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'read_state.g.dart';

/// Per-user delivered/read watermarks stored in `chat_rooms.reads[userId]`.
@JsonSerializable()
class ReadState {
  ReadState({
    this.lastDeliveredSeq = 0,
    this.lastReadSeq = 0,
    this.lastDeliveredAt,
    this.lastReadAt,
  });

  factory ReadState.fromJson(Map<String, dynamic> json) =>
      _$ReadStateFromJson(json);

  @JsonKey(name: 'last_delivered_seq', defaultValue: 0)
  final int lastDeliveredSeq;

  @JsonKey(
    name: 'last_delivered_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastDeliveredAt;

  @JsonKey(name: 'last_read_seq', defaultValue: 0)
  final int lastReadSeq;

  @JsonKey(
    name: 'last_read_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastReadAt;

  Map<String, dynamic> toJson() => _$ReadStateToJson(this);
}
