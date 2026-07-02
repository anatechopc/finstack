import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}

class _MockMessageRepo extends Mock implements MessageRepository {}

class _FakeMessage extends Fake implements Message {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeMessage()));

  late _MockChatRoomRepo rooms;
  late _MockMessageRepo messages;
  late StreamController<List<Message>> msgCtrl;
  late StreamController<ChatRoom> roomCtrl;

  setUp(() {
    rooms = _MockChatRoomRepo();
    messages = _MockMessageRepo();
    msgCtrl = StreamController<List<Message>>.broadcast();
    roomCtrl = StreamController<ChatRoom>.broadcast();
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
  });

  tearDown(() {
    msgCtrl.close();
    roomCtrl.close();
  });

  ChatBloc build() => ChatBloc.withDependencies(
        roomId: 'r1',
        chatRoomRepository: rooms,
        messageRepository: messages,
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
}
