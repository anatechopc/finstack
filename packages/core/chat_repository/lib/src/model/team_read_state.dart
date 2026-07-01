import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'team_read_state.g.dart';

/// Company team handled watermark, `chat_rooms.team_reads[companyId]`.
@JsonSerializable()
class TeamReadState {
  TeamReadState({
    this.lastHandledSeq = 0,
    this.lastHandledAt,
    this.handledBy,
  });

  factory TeamReadState.fromJson(Map<String, dynamic> json) =>
      _$TeamReadStateFromJson(json);

  @JsonKey(name: 'last_handled_seq', defaultValue: 0)
  final int lastHandledSeq;

  @JsonKey(
    name: 'last_handled_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastHandledAt;

  @JsonKey(name: 'handled_by')
  final String? handledBy;

  Map<String, dynamic> toJson() => _$TeamReadStateToJson(this);
}
