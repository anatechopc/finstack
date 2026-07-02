import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/features/chat/screen/chat_room_screen.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

class _MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

void main() {
  late ChatBloc bloc;

  setUpAll(() {
    // Seed AuthenticationService so the screen's build() can read user.id
    // without throwing "Please login".
    AuthenticationService.instance.user = User()..id = 'u1';
  });

  setUp(() => bloc = _MockChatBloc());

  Widget subject() => BlocProvider<ChatBloc>.value(
        value: bloc,
        child: const ChatRoomScreen(roomId: 'r1'),
      );

  testWidgets('renders messages and a composer', (tester) async {
    when(() => bloc.state).thenReturn(
      ChatState(
        status: ChatStatus.loaded,
        messages: [
          Message.create(
            roomId: 'r1',
            senderId: 'c1',
            senderParticipantId: 'c1',
            type: MessageType.text,
            text: 'hello there',
          )..seq = 1,
        ],
      ),
    );
    await tester.pumpApp(subject());
    expect(find.text('hello there'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
