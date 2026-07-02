part of 'conversations_bloc.dart';

sealed class ConversationsEvent extends Equatable {
  const ConversationsEvent();
  @override
  List<Object?> get props => [];
}

final class SubscribeConversations extends ConversationsEvent {
  const SubscribeConversations();
}

final class _ConversationsUpdated extends ConversationsEvent {
  const _ConversationsUpdated(this.rooms);
  final List<ChatRoom> rooms;
  @override
  List<Object?> get props => [rooms];
}

final class _ConversationsErrored extends ConversationsEvent {
  const _ConversationsErrored(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
