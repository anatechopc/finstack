import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}

ChatRoom _room(String id, {int lastSeq = 0, Map<String, ReadState>? reads}) {
  return ChatRoom.create(
    participants: [
      Participant(id: 'u1', type: ParticipantType.user),
      Participant(id: 'c1', type: ParticipantType.company),
    ],
    createdBy: 'u1',
  )
    ..id = id
    ..lastSeq = lastSeq
    ..reads = reads ?? {};
}

void main() {
  late _MockChatRoomRepo repo;
  late StreamController<List<ChatRoom>> controller;

  setUp(() {
    repo = _MockChatRoomRepo();
    controller = StreamController<List<ChatRoom>>.broadcast();
    when(() => repo.dataStream).thenAnswer((_) => controller.stream);
    when(() => repo.loadNext(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        )).thenReturn(null);
  });

  tearDown(() => controller.close());

  blocTest<ConversationsBloc, ConversationsState>(
    'emits rooms and computes unread total for the current user',
    build: () => ConversationsBloc.withDependencies(
      chatRoomRepository: repo,
      myUserId: 'u1',
      myCompanyId: null,
    ),
    act: (bloc) async {
      bloc.add(const SubscribeConversations());
      // Yield so the Subscribe handler runs (it attaches the dataStream
      // listener AFTER loadNext — see ConversationsBloc._onSubscribe) before
      // emitting on the broadcast controller.
      await Future<void>.delayed(Duration.zero);
      controller.add([
        _room('r1', lastSeq: 3, reads: {'u1': ReadState(lastReadSeq: 1)}),
        _room('r2', lastSeq: 2, reads: {'u1': ReadState(lastReadSeq: 2)}),
      ]);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.status, ConversationsStatus.loaded);
      expect(bloc.state.rooms.length, 2);
      expect(bloc.state.totalUnread, 2); // (3-1) + (2-2)
    },
  );
}
