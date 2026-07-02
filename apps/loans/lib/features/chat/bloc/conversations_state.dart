part of 'conversations_bloc.dart';

enum ConversationsStatus { initial, loading, loaded, error }

final class ConversationsState extends Equatable {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.rooms = const [],
    this.myUserId = '',
    this.message,
  });

  final ConversationsStatus status;
  final List<ChatRoom> rooms;
  final String myUserId;
  final String? message;

  /// Sum of the current user's unread across all rooms.
  int get totalUnread =>
      rooms.fold(0, (sum, r) => sum + unreadFor(r, myUserId));

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<ChatRoom>? rooms,
    String? myUserId,
    String? message,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      rooms: rooms ?? this.rooms,
      myUserId: myUserId ?? this.myUserId,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, rooms, myUserId, message];
}
