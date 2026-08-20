import 'package:chat_repository/src/model/chat_room.dart';
import 'package:chat_repository/src/model/last_message.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';
import 'package:chat_repository/src/model/team_read_state.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'chat_room_entity.g.dart';

@JsonSerializable()
class ChatRoomEntity implements BaseEntity {
  ChatRoomEntity();

  factory ChatRoomEntity.fromJson(Map<String, dynamic> json) =>
      _$ChatRoomEntityFromJson(json);

  @override
  late String id;

  @JsonKey(toJson: ChatRoomEntity._participantsToJson, defaultValue: <Participant>[])
  late List<Participant> participants;

  @JsonKey(name: 'member_ids', defaultValue: <String>[])
  late List<String> memberIds;

  @JsonKey(name: 'context_type')
  String? contextType;

  @JsonKey(name: 'context_id')
  String? contextId;

  /// Human-readable name of the anchor (the product's or loan's `loanType`),
  /// denormalized at creation so the inbox can label a room without a second
  /// fetch. A snapshot: it is never refreshed if the product is renamed, the
  /// same trade-off as [Participant.displayName].
  ///
  /// Deliberately NOT part of the dedup key — see `roomMatchesAnchor`.
  /// Null on rooms created before this field existed; callers fall back to
  /// [contextType].
  @JsonKey(name: 'context_label')
  String? contextLabel;

  @JsonKey(name: 'last_seq', defaultValue: 0)
  late int lastSeq;

  @JsonKey(
    name: 'last_message',
    toJson: ChatRoomEntity._lastMessageToJson,
    fromJson: ChatRoomEntity._lastMessageFromJson,
  )
  LastMessage? lastMessage;

  @JsonKey(
    toJson: ChatRoomEntity._readsToJson,
    fromJson: ChatRoomEntity._readsFromJson,
    defaultValue: <String, ReadState>{},
  )
  late Map<String, ReadState> reads;

  @JsonKey(
    name: 'team_reads',
    toJson: ChatRoomEntity._teamReadsToJson,
    fromJson: ChatRoomEntity._teamReadsFromJson,
    defaultValue: <String, TeamReadState>{},
  )
  late Map<String, TeamReadState> teamReads;

  @JsonKey(name: 'created_by')
  late String createdBy;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @override
  List<Object?> get props => [
        id, participants, memberIds, contextType, contextId, contextLabel, lastSeq,
        lastMessage, reads, teamReads, createdBy, createdAt, updatedAt, deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$ChatRoomEntityToJson(this);

  ChatRoom toChatRoom() {
    return ChatRoom()
      ..id = id
      ..participants = participants
      ..memberIds = memberIds
      ..contextType = contextType
      ..contextId = contextId
      ..contextLabel = contextLabel
      ..lastSeq = lastSeq
      ..lastMessage = lastMessage
      ..reads = reads
      ..teamReads = teamReads
      ..createdBy = createdBy
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt;
  }

  static List<Map<String, dynamic>> _participantsToJson(List<Participant> items) =>
      items.map((p) => p.toJson()).toList();

  static Map<String, dynamic>? _lastMessageToJson(LastMessage? m) => m?.toJson();

  static LastMessage? _lastMessageFromJson(Object? json) {
    if (json == null) return null;
    return LastMessage.fromJson(_asStringMap(json));
  }

  static Map<String, Map<String, dynamic>> _readsToJson(Map<String, ReadState> m) =>
      m.map((k, v) => MapEntry(k, v.toJson()));

  static Map<String, ReadState> _readsFromJson(Object? json) {
    if (json == null) return <String, ReadState>{};
    return (json as Map).map(
      (k, v) => MapEntry(k as String, ReadState.fromJson(_asStringMap(v))),
    );
  }

  static Map<String, Map<String, dynamic>> _teamReadsToJson(
    Map<String, TeamReadState> m,
  ) =>
      m.map((k, v) => MapEntry(k, v.toJson()));

  static Map<String, TeamReadState> _teamReadsFromJson(Object? json) {
    if (json == null) return <String, TeamReadState>{};
    return (json as Map).map(
      (k, v) => MapEntry(k as String, TeamReadState.fromJson(_asStringMap(v))),
    );
  }

  /// Firestore/RTDB nested maps can arrive as `Map<Object?,Object?>`.
  static Map<String, dynamic> _asStringMap(Object? v) =>
      (v! as Map).map((k, val) => MapEntry(k as String, val));
}
