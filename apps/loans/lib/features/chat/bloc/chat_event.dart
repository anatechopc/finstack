part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

final class SubscribeChat extends ChatEvent {
  const SubscribeChat();
}

final class SendTextMessage extends ChatEvent {
  const SendTextMessage(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

final class MarkRoomRead extends ChatEvent {
  const MarkRoomRead();
}

final class _MessagesUpdated extends ChatEvent {
  const _MessagesUpdated(this.messages);
  final List<Message> messages;
  @override
  List<Object?> get props => [messages];
}

final class _RoomUpdated extends ChatEvent {
  const _RoomUpdated(this.room);
  final ChatRoom room;
  @override
  List<Object?> get props => [room];
}

final class _ChatErrored extends ChatEvent {
  const _ChatErrored(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

final class TypingChanged extends ChatEvent {
  const TypingChanged(this.isTyping);
  final bool isTyping;
  @override
  List<Object?> get props => [isTyping];
}

final class _TypingUsersUpdated extends ChatEvent {
  const _TypingUsersUpdated(this.userIds);
  final List<String> userIds;
  @override
  List<Object?> get props => [userIds];
}

final class EditMessage extends ChatEvent {
  const EditMessage(this.messageId, this.text);
  final String messageId;
  final String text;
  @override
  List<Object?> get props => [messageId, text];
}

final class DeleteMessage extends ChatEvent {
  const DeleteMessage(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

final class SendImageAttachment extends ChatEvent {
  const SendImageAttachment({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
  @override
  List<Object?> get props => [fileName, bytes.length];
}

final class SendFileAttachment extends ChatEvent {
  const SendFileAttachment({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
  @override
  List<Object?> get props => [fileName, bytes.length];
}
