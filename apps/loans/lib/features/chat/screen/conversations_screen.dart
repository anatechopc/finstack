import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/chat/chat_context_label.dart';
import 'package:loooans/utils/screen_helpers.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  // No SubscribeConversations dispatch here: the bloc auto-subscribes at
  // construction (for the app-bar badge) and the stream is already a live
  // snapshot listener — re-dispatching on every screen open just re-runs the
  // query for nothing.

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
          if (state.status == ConversationsStatus.loading &&
              state.rooms.isEmpty) {
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
    // Exclude BOTH my user id and my company id — for staff the personal id is
    // not a participant at all, so excluding only myUserId would resolve the
    // counterpart to the company itself (matching chat_status/chat_room_screen).
    final counterpart = room.participants.firstWhere(
      (p) => p.id != myUserId && p.id != myCompanyId,
      orElse: () => room.participants.first,
    );
    final unread = unreadFor(room, myUserId);
    final preview = room.lastMessage?.text ?? '';
    final pill = contextPillText(
      contextType: room.contextType,
      contextLabel: room.contextLabel,
    );
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
        // The "Awaiting" chip lives on the subtitle line: stacking it in the
        // trailing column with the time + unread badge exceeded the ListTile
        // trailing height (28px overflow seen in the dev smoke test), and a
        // FittedBox workaround shrank the text inconsistently per row.
        subtitle: Row(
          children: [
            if (pill != null) ...[
              Flexible(child: _Pill(text: pill, color: AppColors.green1_6)),
              const Gap(8),
            ],
            Flexible(
              flex: 3,
              child:
                  Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (myCompanyId != null &&
                isAwaitingResponse(room, myCompanyId!)) ...[
              const Gap(8),
              const Flexible(
                child: _Pill(text: 'Awaiting', color: AppColors.ubOrange),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: const TextStyle(fontSize: 11)),
            if (unread > 0) ...[
              const Gap(4),
              _UnreadBadge(count: unread),
            ],
          ],
        ),
        onTap: () => GoRouter.of(context)
            .go(Paths.chatRoom.replaceFirst(':roomId', room.id)),
      ),
    );
  }
}

/// Small rounded label used on the subtitle line.
///
/// Every child of that Row is Flexible, so the row can never exceed its
/// constraints: on a narrow phone the pills shrink and ellipsize rather than
/// overflowing. The preview carries the largest flex, so it yields first and
/// the labels stay readable. An earlier cut sized the pills intrinsically and
/// let only the preview shrink, which overflows once both pills render — the
/// staff inbox case. This row has form: see the 28px trailing-column overflow
/// in apps/loans/MEMORY.md.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
    final parts =
        trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
