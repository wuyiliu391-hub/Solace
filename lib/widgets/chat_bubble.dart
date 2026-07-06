import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// 微信风格聊天气泡
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final String? companionAvatar;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.companionAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _buildAvatar(context),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF95EC69) : Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                message.content,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 40,
        height: 40,
        color: const Color(0xFFD2E3FC),
        child: companionAvatar != null
            ? Image.file(File(companionAvatar!), fit: BoxFit.cover)
            : Center(
                child: Text(
                  message.senderName?.characters.first ?? '?',
                  style: const TextStyle(color: Color(0xFF1A73E8), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
      ),
    );
  }
}
