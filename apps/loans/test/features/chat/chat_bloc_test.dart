import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:storage_repository/storage_repository.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}

class _MockMessageRepo extends Mock implements MessageRepository {}

class _MockTyping extends Mock implements TypingService {}

class _MockStorage extends Mock implements StorageRepository {}

class _FakeMessage extends Fake implements Message {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeMessage());
    registerFallbackValue(Uint8List(0));
  });

  late _MockChatRoomRepo rooms;
  late _MockMessageRepo messages;
  late _MockTyping typing;
  late _MockStorage storage;
  late StreamController<List<Message>> msgCtrl;
  late StreamController<ChatRoom> roomCtrl;
  late StreamController<List<String>> typingCtrl;

  setUp(() {
    rooms = _MockChatRoomRepo();
    messages = _MockMessageRepo();
    typing = _MockTyping();
    storage = _MockStorage();
    msgCtrl = StreamController<List<Message>>.broadcast();
    roomCtrl = StreamController<ChatRoom>.broadcast();
    typingCtrl = StreamController<List<String>>.broadcast();
    when(() => messages.dataStream).thenAnswer((_) => msgCtrl.stream);
    when(
      () => messages.loadNext(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenReturn(null);
    when(() => rooms.watchRoom(any())).thenAnswer((_) => roomCtrl.stream);
    when(
      () => rooms.markRead(
        roomId: any(named: 'roomId'),
        userId: any(named: 'userId'),
        seq: any(named: 'seq'),
      ),
    ).thenAnswer((_) async {});
    when(() => messages.add(data: any(named: 'data'))).thenAnswer(
      (invocation) async => invocation.namedArguments[#data] as Message,
    );
    when(
      () => messages.editMessage(
        messageId: any(named: 'messageId'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => messages.deleteMessage(messageId: any(named: 'messageId')),
    ).thenAnswer((_) async {});
    when(
      () => typing.typingStream(
        roomId: any(named: 'roomId'),
        clock: any(named: 'clock'),
      ),
    ).thenAnswer((_) => typingCtrl.stream);
  });

  tearDown(() {
    msgCtrl.close();
    roomCtrl.close();
    typingCtrl.close();
  });

  ChatBloc build() => ChatBloc.withDependencies(
        roomId: 'r1',
        chatRoomRepository: rooms,
        messageRepository: messages,
        typingService: typing,
        storageRepository: storage,
        myUserId: 'u1',
        mySenderParticipantId: 'u1',
      );

  blocTest<ChatBloc, ChatState>(
    'subscribe -> emits incoming messages',
    build: build,
    act: (bloc) {
      bloc.add(const SubscribeChat());
      msgCtrl.add([
        Message.create(
          roomId: 'r1',
          senderId: 'c1',
          senderParticipantId: 'c1',
          type: MessageType.text,
          text: 'hi',
        )..seq = 1,
      ]);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.status, ChatStatus.loaded);
      expect(bloc.state.messages.single.text, 'hi');
    },
  );

  blocTest<ChatBloc, ChatState>(
    'SendText -> calls messageRepository.add with a text message',
    build: build,
    act: (bloc) {
      bloc.add(const SubscribeChat());
      bloc.add(const SendTextMessage('yo'));
    },
    wait: const Duration(milliseconds: 20),
    verify: (_) {
      final captured =
          verify(() => messages.add(data: captureAny(named: 'data'))).captured;
      final sent = captured.single as Message;
      expect(sent.text, 'yo');
      expect(sent.senderParticipantId, 'u1');
      expect(sent.type, MessageType.text);
    },
  );

  blocTest<ChatBloc, ChatState>(
    'typingStream -> filters own userId and updates typingUserIds',
    build: build,
    act: (bloc) {
      bloc.add(const SubscribeChat());
      typingCtrl.add(['c1']);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.typingUserIds, ['c1']);
    },
  );

  blocTest<ChatBloc, ChatState>(
    'EditMessage calls messageRepository.editMessage',
    build: build,
    act: (bloc) => bloc.add(const EditMessage('m1', 'new text')),
    wait: const Duration(milliseconds: 10),
    verify: (_) {
      verify(
        () => messages.editMessage(messageId: 'm1', text: 'new text'),
      ).called(1);
    },
  );

  blocTest<ChatBloc, ChatState>(
    'DeleteMessage calls messageRepository.deleteMessage',
    build: build,
    act: (bloc) => bloc.add(const DeleteMessage('m2')),
    wait: const Duration(milliseconds: 10),
    verify: (_) {
      verify(
        () => messages.deleteMessage(messageId: 'm2'),
      ).called(1);
    },
  );

  blocTest<ChatBloc, ChatState>(
    'SendImageAttachment uploads image and adds image message',
    build: () {
      when(
        () => storage.upload(
          data: any(named: 'data'),
          folder: any(named: 'folder'),
          fileName: any(named: 'fileName'),
          includeOriginal: any(named: 'includeOriginal'),
        ),
      ).thenAnswer(
        (_) async => ImageUrl(name: 'p.jpg', thumbnail: 'thumb', original: 'orig'),
      );
      return build();
    },
    act: (bloc) => bloc.add(
      SendImageAttachment(
        fileName: 'p.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ),
    wait: const Duration(milliseconds: 20),
    verify: (_) {
      final captured =
          verify(() => messages.add(data: captureAny(named: 'data'))).captured;
      final sent = captured.single as Message;
      expect(sent.type, MessageType.image);
      expect(sent.attachments.single.thumbnailUrl, 'thumb');
    },
  );
}
