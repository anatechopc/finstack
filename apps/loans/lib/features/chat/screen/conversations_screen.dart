import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ConversationsBloc>().add(const SubscribeConversations());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppColors.green1,
        centerTitle: false,
      ),
      body: BlocBuilder<ConversationsBloc, ConversationsState>(
        builder: (context, state) {
          if (state.status == ConversationsStatus.loading && state.rooms.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.rooms.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet',
                style: TextStyle(color: AppColors.black, fontSize: 16),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.rooms.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (context, index) {
              final room = state.rooms[index];
              return _ConversationRow(
                room: room,
                myUserId: state.myUserId,
                myCompanyId: state.myCompanyId,
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.room,
    required this.myUserId,
    this.myCompanyId,
  });

  final ChatRoom room;
  final String myUserId;
  final String? myCompanyId;

  @override
  Widget build(BuildContext context) {
    final counterpart = room.participants.firstWhere(
      (p) => p.id != myUserId,
      orElse: () => room.participants.first,
    );
    final unread = unreadFor(room, myUserId);
    final preview = room.lastMessage?.text ?? '';
    final time = room.lastMessage == null
        ? ''
        : Jiffy.parseFromDateTime(room.lastMessage!.createdAt).fromNow();

    return Card(
      color: AppColors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.green1,
          child: Text(
            (counterpart.displayName ?? '?').initialsSafe,
            style: const TextStyle(color: AppColors.black),
          ),
        ),
        title: Text(counterpart.displayName ?? 'Conversation'),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: const TextStyle(fontSize: 11)),
            if (unread > 0) ...[
              const Gap(4),
              _UnreadBadge(count: unread),
            ],
            if (myCompanyId != null &&
                isAwaitingResponse(room, myCompanyId!)) ...[
              const Gap(4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ubOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Awaiting',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.ubOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        onTap: () => GoRouter.of(context)
            .go(Paths.chatRoom.replaceFirst(':roomId', room.id)),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.green1_6,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension _Initials on String {
  String get initialsSafe {
    final parts = trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
