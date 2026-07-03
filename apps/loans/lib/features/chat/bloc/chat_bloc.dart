import 'dart:async';
import 'dart:typed_data';

import 'package:chat_repository/chat_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:uuid/uuid.dart';

part 'chat_event.dart';
part 'chat_state.dart';

final _log = Logger('chat_bloc');

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  // Reads the auth singleton ONCE and delegates to the injectable path, rather
  // than scattering AuthenticationService.instance through the bloc (per the
  // "use the injected authService field, never AuthenticationService.instance in
  // BLoCs" rule in apps/loans/CLAUDE.md).
  factory ChatBloc(BuildContext context, {required String roomId}) {
    final user = AuthenticationService.instance.user;
    return ChatBloc.withDependencies(
      roomId: roomId,
      chatRoomRepository: context.read<ChatRoomRepository>(),
      messageRepository: MessageRepository(roomId: roomId),
      typingService: context.read<TypingService>(),
      storageRepository: context.read<StorageRepository>(),
      myUserId: user.id,
      mySenderParticipantId: user.companyId ?? user.id,
    );
  }

  ChatBloc.withDependencies({
    required String roomId,
    required ChatRoomRepository chatRoomRepository,
    required MessageRepository messageRepository,
    required TypingService typingService,
    required StorageRepository storageRepository,
    required String myUserId,
    required String mySenderParticipantId,
  })  : _roomId = roomId,
        _rooms = chatRoomRepository,
        _messages = messageRepository,
        _typing = typingService,
        _storage = storageRepository,
        _myUserId = myUserId,
        _mySenderParticipantId = mySenderParticipantId,
        super(const ChatState()) {
    _wire();
  }

  final String _roomId;
  final ChatRoomRepository _rooms;
  final MessageRepository _messages;
  final TypingService _typing;
  final StorageRepository _storage;
  final String _myUserId;
  final String _mySenderParticipantId;

  StreamSubscription<List<Message>>? _msgSub;
  StreamSubscription<ChatRoom>? _roomSub;
  StreamSubscription<List<String>>? _typingSub;

  // Highest seq already marked, so we only write a watermark when it advances.
  int _lastReadMarked = 0;
  int _lastHandledMarked = 0;

  void _wire() {
    on<SubscribeChat>(_onSubscribe);
    on<SendTextMessage>(_onSendText);
    on<MarkRoomRead>(_onMarkRead);
    on<_MessagesUpdated>(_onMessagesUpdated);
    on<_RoomUpdated>((e, emit) => emit(state.copyWith(room: e.room)));
    on<_ChatErrored>(
      (e, emit) =>
          emit(state.copyWith(status: ChatStatus.error, message: e.message)),
    );
    on<TypingChanged>(_onTyping);
    on<_TypingUsersUpdated>(
      (e, emit) => emit(state.copyWith(typingUserIds: e.userIds)),
    );
    on<EditMessage>(_onEdit);
    on<DeleteMessage>(_onDelete);
    on<SendImageAttachment>(_onSendImage);
    on<SendFileAttachment>(_onSendFile);

    // Subscriptions established synchronously so broadcast-stream tests don't
    // miss emissions fired right after SubscribeChat.
    _msgSub = _messages.dataStream.listen(
      (msgs) => add(_MessagesUpdated(msgs)),
      onError: (Object err) {
        _log.severe('messages stream error: $err');
        add(const _ChatErrored('Failed to load messages'));
      },
    );
    _roomSub = _rooms.watchRoom(_roomId).listen(
          (room) => add(_RoomUpdated(room)),
          onError: (Object err) => _log.severe('room stream error: $err'),
        );
    _typingSub = _typing
        .typingStream(
          roomId: _roomId,
          clock: () => DateTime.now().millisecondsSinceEpoch,
        )
        .listen(
          (ids) => add(
            _TypingUsersUpdated(
              ids.where((id) => id != _myUserId).toList(),
            ),
          ),
        );
  }

  Future<void> _onSubscribe(
    SubscribeChat event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loading));
    _messages.loadNext(reset: true);
  }

  Future<void> _onMessagesUpdated(
    _MessagesUpdated event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loaded, messages: event.messages));
    final latestSeq = event.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    // Coalesce: only write a watermark when it actually advances, so repeated
    // emissions (own sends, edits, deletes, re-deliveries) don't re-issue
    // identical reads/team_reads writes, and a stale/lower seq can't regress it.
    if (latestSeq > _lastReadMarked) {
      _lastReadMarked = latestSeq;
      await _rooms.markRead(
        roomId: _roomId,
        userId: _myUserId,
        seq: latestSeq,
      );
    }
    final iAmStaff = _mySenderParticipantId != _myUserId;
    if (iAmStaff && latestSeq > _lastHandledMarked) {
      _lastHandledMarked = latestSeq;
      await _rooms.markHandled(
        roomId: _roomId,
        companyId: _mySenderParticipantId,
        userId: _myUserId,
        seq: latestSeq,
      );
    }
  }

  Future<void> _onSendText(
    SendTextMessage event,
    Emitter<ChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty) return;
    emit(state.copyWith(sending: true));
    try {
      await _messages.add(
        data: Message.create(
          roomId: _roomId,
          senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.text,
          text: text,
        ),
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send'));
    }
  }

  Future<void> _onMarkRead(
    MarkRoomRead event,
    Emitter<ChatState> emit,
  ) async {
    final latestSeq = state.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latestSeq > 0) {
      await _rooms.markRead(
        roomId: _roomId,
        userId: _myUserId,
        seq: latestSeq,
      );
    }
  }

  Future<void> _onEdit(EditMessage event, Emitter<ChatState> emit) async {
    final text = event.text.trim();
    if (text.isEmpty) return;
    try {
      await _messages.editMessage(messageId: event.messageId, text: text);
    } catch (err) {
      _log.severe('edit failed: $err');
      emit(state.copyWith(message: 'Failed to edit'));
    }
  }

  Future<void> _onDelete(DeleteMessage event, Emitter<ChatState> emit) async {
    try {
      await _messages.deleteMessage(messageId: event.messageId);
    } catch (err) {
      _log.severe('delete failed: $err');
      emit(state.copyWith(message: 'Failed to delete'));
    }
  }

  Future<void> _onTyping(TypingChanged event, Emitter<ChatState> emit) async {
    if (event.isTyping) {
      await _typing.setTyping(
        roomId: _roomId,
        userId: _myUserId,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await _typing.clearTyping(roomId: _roomId, userId: _myUserId);
    }
  }

  Future<void> _onSendImage(
    SendImageAttachment e,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(sending: true));
    try {
      final msgId = const Uuid().v4();
      final img = await _storage.upload(
        data: e.bytes,
        folder: 'chat/$_roomId/$msgId',
        fileName: e.fileName,
        includeOriginal: true,
      );
      final att = Attachment(
        name: e.fileName,
        url: img.original ?? img.thumbnail ?? '',
        thumbnailUrl: img.thumbnail,
        contentType: 'image/*',
        size: e.bytes.length,
      );
      await _messages.add(
        data: Message.create(
          roomId: _roomId,
          senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.image,
          attachments: [att],
        )..id = msgId,
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('image send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send image'));
    }
  }

  Future<void> _onSendFile(
    SendFileAttachment e,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(sending: true));
    try {
      final msgId = const Uuid().v4();
      final file = await _storage.uploadFile(
        data: e.bytes,
        folder: 'chat/$_roomId/$msgId',
        fileName: e.fileName,
      );
      final att = Attachment(
        name: e.fileName,
        url: file.url,
        contentType: 'application/octet-stream',
        size: e.bytes.length,
      );
      await _messages.add(
        data: Message.create(
          roomId: _roomId,
          senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.file,
          attachments: [att],
        )..id = msgId,
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('file send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send file'));
    }
  }

  @override
  Future<void> close() {
    _msgSub?.cancel();
    _roomSub?.cancel();
    _typingSub?.cancel();
    return super.close();
  }
}
