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
    expect(find.text('Offer'), findsNothing);
  });

  testWidgets('falls back to the context type when no label was stored',
      (tester) async {
    // Rooms created before context_label existed carry only the type.
    await pumpRoom(tester, roomWith(contextType: 'product'));
    expect(find.text('Offer'), findsOneWidget);
  });

  testWidgets('renders no context pill for an unanchored room',
      (tester) async {
    await pumpRoom(tester, roomWith());
    expect(find.text('Offer'), findsNothing);
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

  testWidgets('the context label is not squeezed on a real phone',
      (tester) async {
    // takeException()/find.text() cannot catch this: find.text matches the
    // widget's data, not painted glyphs, and a Row whose children are all
    // Flexible can never overflow. An earlier cut wrapped the label in
    // Flexible, which CAPS a child at spacePerFlex * flex -- it rendered 34.6px
    // of a 140px label on a 390dp phone and every test still passed. So
    // measure the width instead of asserting the absence of an exception.
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const label = 'Loan ₱50k · Business loan';
    final room = roomWith(contextType: 'loan', contextLabel: label)
      ..lastSeq = 5; // also renders the staff "Awaiting" pill

    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [room],
        myUserId: 'staff1',
        myCompanyId: 'c1',
      ),
    );
    await tester.pumpApp(subject());

    // The full label needs ~275px and the line has ~210px, so it ellipsizes.
    // What must survive is the DISCRIMINATOR -- the kind and the amount -- so
    // several loans of one product stay tellable apart. Assert that prefix
    // fits, not the whole string.
    final discriminator = TextPainter(
      text: const TextSpan(
        text: 'Loan ₱50k · ',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rendered = tester.getSize(find.text(label)).width;

    expect(
      rendered,
      greaterThanOrEqualTo(discriminator.width),
      reason: 'truncation is eating the amount, which is what tells a '
          "borrower's loans apart",
    );
    expect(find.text('Awaiting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
