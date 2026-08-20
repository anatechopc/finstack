import 'dart:typed_data';

import 'package:chat_repository/chat_repository.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/features/chat/chat_context_label.dart';
import 'package:loooans/features/chat/chat_status.dart';
import 'package:loooans/features/chat/widget/message_bubble.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

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
        // Two-line title (name + "Re: <anchor>") needs more than the 56px
        // default: AppBar clamps the title box to kToolbarHeight and centres
        // it, so a taller child paints outside the bar.
        toolbarHeight: 72,
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
            // Spec section 8.2's context line: which product or loan this
            // conversation is about. Two rooms with the same counterpart are
            // otherwise indistinguishable once you are inside one.
            final anchorLabel = contextPillText(
              contextType: state.room?.contextType,
              contextLabel: state.room?.contextLabel,
            );
            if (anchorLabel == null) {
              return Text(counterpart ?? 'Conversation');
            }
            // The app theme sets centerTitle: true, so the title box is
            // centred as a block — the lines must be centred too or they read
            // as misaligned against every other screen.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(counterpart ?? 'Conversation'),
                Text(
                  'Re: $anchorLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Explicit weight/colour: the inherited titleTextStyle is
                  // headlineLarge/w600, which renders this as a second heading
                  // rather than a de-emphasised context line.
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.lightBlack,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: BlocListener<ChatBloc, ChatState>(
        listenWhen: (a, b) => b.message != null && b.message != a.message,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message!)));
        },
        child: Column(
          children: [
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.status == ChatStatus.loading &&
                      state.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.messages.isEmpty) {
                    if (state.status == ChatStatus.error) {
                      return Center(
                        child: Text(
                          state.message ?? 'Could not load messages',
                          style: const TextStyle(
                            color: AppColors.black,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
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
                      final bubble = MessageBubble(
                        message: m,
                        isMine: isMine,
                        status: status,
                        senderLabel: senderLabel,
                      );
                      if (!isMine) return bubble;
                      return GestureDetector(
                        onLongPress: () => _showMessageActions(context, m),
                        child: bubble,
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
      ),
    );
  }

  Future<void> _showMessageActions(BuildContext context, Message m) async {
    if (m.deletedAt != null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      final edited = await _editDialog(context, m.text ?? '');
      if (edited != null && context.mounted) {
        context.read<ChatBloc>().add(EditMessage(m.id, edited));
      }
    } else if (action == 'delete') {
      context.read<ChatBloc>().add(DeleteMessage(m.id));
    }
  }

  Future<String?> _editDialog(BuildContext context, String initial) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit message'),
          content: TextField(controller: ctrl, autofocus: true, maxLines: 4),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'photo') {
      final data = await AppWidgets.defaultMediaChooserDialog(context);
      if (data != null && mounted) {
        context.read<ChatBloc>().add(
              SendImageAttachment(
                fileName: data['name'] as String,
                bytes: data['bytes'] as Uint8List,
              ),
            );
      }
    } else {
      final res = await FilePicker.platform.pickFiles(withData: true);
      final f = res?.files.single;
      if (f?.bytes != null && mounted) {
        context.read<ChatBloc>().add(
              SendFileAttachment(fileName: f!.name, bytes: f.bytes!),
            );
      }
    }
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _attach,
            ),
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
              style:
                  IconButton.styleFrom(backgroundColor: AppColors.lightBlack),
              icon: const Icon(Icons.send, color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
