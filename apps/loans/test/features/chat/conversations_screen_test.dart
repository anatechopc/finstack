import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/chat/screen/conversations_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockConversationsBloc
    extends MockBloc<ConversationsEvent, ConversationsState>
    implements ConversationsBloc {}

void main() {
  late ConversationsBloc bloc;
  setUp(() => bloc = _MockConversationsBloc());

  Widget subject() => BlocProvider<ConversationsBloc>.value(
        value: bloc,
        child: const ConversationsScreen(),
      );

  testWidgets('shows empty state when there are no rooms', (tester) async {
    when(() => bloc.state).thenReturn(
      const ConversationsState(status: ConversationsStatus.loaded),
    );
    await tester.pumpApp(subject());
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('lists a conversation with its counterpart name', (tester) async {
    final room = ChatRoom.create(
      participants: [
        Participant(id: 'u1', type: ParticipantType.user, displayName: 'Me'),
        Participant(id: 'c1', type: ParticipantType.company, displayName: 'Acme'),
      ],
      createdBy: 'u1',
    )..id = 'r1';
    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [room],
        myUserId: 'u1',
      ),
    );
    await tester.pumpApp(subject());
    expect(find.text('Acme'), findsOneWidget);
  });
}
