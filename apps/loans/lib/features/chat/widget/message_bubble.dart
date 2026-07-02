import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, required this.isMine, super.key});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final deleted = message.deletedAt != null;
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
        child: Text(
          deleted ? 'This message was deleted' : (message.text ?? ''),
          style: TextStyle(
            color: isMine ? AppColors.white : AppColors.black,
            fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}
