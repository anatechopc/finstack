import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    this.status,
    this.senderLabel,
    super.key,
  });

  final Message message;
  final bool isMine;
  final MessageStatus? status;
  final String? senderLabel;

  @override
  Widget build(BuildContext context) {
    final deleted = message.deletedAt != null;
    final edited = message.editedAt != null && !deleted;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.lightBlack : AppColors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine && senderLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  senderLabel!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (deleted)
              Text(
                'This message was deleted',
                style: TextStyle(
                  color: isMine ? AppColors.white : AppColors.black,
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (message.type == MessageType.image &&
                message.attachments.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.attachments.first.thumbnailUrl ??
                      message.attachments.first.url,
                  width: 180,
                  fit: BoxFit.cover,
                ),
              )
            else if (message.type == MessageType.file &&
                message.attachments.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    color: isMine ? AppColors.white : AppColors.black,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      message.attachments.first.name,
                      style: TextStyle(
                        color: isMine ? AppColors.white : AppColors.black,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.text ?? '',
                style: TextStyle(
                  color: isMine ? AppColors.white : AppColors.black,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited)
                  Text(
                    'edited',
                    style: TextStyle(
                      fontSize: 10,
                      color: (isMine ? AppColors.white : AppColors.black)
                          .withValues(alpha: 0.6),
                    ),
                  ),
                if (isMine && status != null) ...[
                  const SizedBox(width: 6),
                  _StatusTick(status: status!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});
  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MessageStatus.sending => (Icons.schedule, AppColors.white),
      MessageStatus.sent => (Icons.check, AppColors.white),
      MessageStatus.delivered => (Icons.done_all, AppColors.white),
      MessageStatus.read => (Icons.done_all, AppColors.blue),
    };
    return Icon(icon, size: 14, color: color.withValues(alpha: 0.9));
  }
}
