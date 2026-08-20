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

  ChatRoom roomWith({String? contextType, String? contextLabel}) =>
      ChatRoom.create(
        participants: [
          Participant(id: 'u1', type: ParticipantType.user, displayName: 'Me'),
          Participant(
            id: 'c1',
            type: ParticipantType.company,
            displayName: 'Acme',
          ),
        ],
        createdBy: 'u1',
        contextType: contextType,
        contextId: contextType == null ? null : 'x1',
        contextLabel: contextLabel,
      )..id = 'r1';

  Future<void> pumpRoom(WidgetTester tester, ChatRoom room) async {
    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [room],
        myUserId: 'u1',
      ),
    );
    await tester.pumpApp(subject());
  }

  testWidgets('labels a room with its denormalized context label',
      (tester) async {
    await pumpRoom(
      tester,
      roomWith(contextType: 'product', contextLabel: 'Business loan'),
    );
    expect(find.text('Business loan'), findsOneWidget);
    expect(find.text('Product'), findsNothing);
  });

  testWidgets('falls back to the context type when no label was stored',
      (tester) async {
    // Rooms created before context_label existed carry only the type.
    await pumpRoom(tester, roomWith(contextType: 'product'));
    expect(find.text('Product'), findsOneWidget);
  });

  testWidgets('renders no context pill for an unanchored room',
      (tester) async {
    await pumpRoom(tester, roomWith());
    expect(find.text('Product'), findsNothing);
    expect(find.text('Loan'), findsNothing);
    expect(find.text('Acme'), findsOneWidget);
  });

  testWidgets('two rooms with the same counterpart are tellable apart',
      (tester) async {
    // The reported symptom: three D2 Finance rows that looked identical.
    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [
          roomWith(contextType: 'product', contextLabel: 'Business loan')
            ..id = 'r1',
          roomWith(contextType: 'product', contextLabel: 'Open Term Loan')
            ..id = 'r2',
          roomWith(contextType: 'loan', contextLabel: 'Salary Loan')..id = 'r3',
        ],
        myUserId: 'u1',
      ),
    );
    await tester.pumpApp(subject());
    expect(find.text('Acme'), findsNWidgets(3));
    expect(find.text('Business loan'), findsOneWidget);
    expect(find.text('Open Term Loan'), findsOneWidget);
    expect(find.text('Salary Loan'), findsOneWidget);
  });

  testWidgets('a labelled awaiting row fits a 320dp phone without overflowing',
      (tester) async {
    // The staff inbox renders BOTH pills. Sized intrinsically they exceed a
    // narrow row and RenderFlex overflows — no other test reaches this case,
    // because none sets myCompanyId and the default surface is 800dp wide.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final room = roomWith(
      contextType: 'product',
      contextLabel: 'Emergency loan',
    );
    room.lastSeq = 5; // unhandled by the team => "Awaiting" renders

    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [room],
        myUserId: 'staff1',
        myCompanyId: 'c1',
      ),
    );
    await tester.pumpApp(subject());

    expect(find.text('Awaiting'), findsOneWidget);
    expect(find.text('Emergency loan'), findsOneWidget);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });
}
