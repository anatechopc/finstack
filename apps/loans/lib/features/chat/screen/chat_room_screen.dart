import 'package:chat_repository/chat_repository.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/features/chat/chat_status.dart';
import 'package:loooans/features/chat/widget/message_bubble.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({required this.roomId, super.key});
  final String roomId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(const SubscribeChat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ChatBloc>().add(SendTextMessage(text));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = AuthenticationService.instance.user.id;
    final myCompanyId = AuthenticationService.instance.user.companyId;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => GoRouter.of(context).go('/'),
        ),
        title: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (a, b) => a.room != b.room,
          builder: (context, state) {
            final counterpart = state.room?.participants
                .where((p) => p.id != myUserId && p.id != myCompanyId)
                .map((p) => p.displayName)
                .firstOrNull;
            return Text(counterpart ?? 'Conversation');
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state.status == ChatStatus.loading &&
                    state.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say hello 👋',
                      style: TextStyle(color: AppColors.black, fontSize: 16),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final m = state.messages[index];
                    final isMine = m.senderParticipantId == myUserId ||
                        m.senderParticipantId == myCompanyId;
                    final room = state.room;
                    final status = (isMine && room != null)
                        ? messageStatus(
                            message: m,
                            counterpartReadStates: counterpartReadStates(
                              room,
                              myUserId: myUserId,
                              myCompanyId: myCompanyId,
                            ),
                          )
                        : null;
                    final senderLabel = (!isMine &&
                            room != null &&
                            m.senderParticipantId != myUserId)
                        ? room.participants
                            .firstWhere(
                              (p) => p.id == m.senderParticipantId,
                              orElse: () => room.participants.first,
                            )
                            .displayName
                        : null;
                    return MessageBubble(
                      message: m,
                      isMine: isMine,
                      status: status,
                      senderLabel: senderLabel,
                    );
                  },
                );
              },
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) => a.typingUserIds != b.typingUserIds,
            builder: (context, state) {
              if (state.typingUserIds.isEmpty) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'typing…',
                    style: TextStyle(
                      color: AppColors.black,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              );
            },
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: (v) => context
                    .read<ChatBloc>()
                    .add(TypingChanged(v.trim().isNotEmpty)),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Gap(8),
            IconButton.filled(
              onPressed: _send,
              style: IconButton.styleFrom(backgroundColor: AppColors.lightBlack),
              icon: const Icon(Icons.send, color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
