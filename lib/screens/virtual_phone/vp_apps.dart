import 'dart:io';

import 'package:flutter/material.dart';

import '../../blocs/virtual_phone/virtual_phone_bloc.dart';
import '../../models/virtual_phone/vp_chat.dart';
import '../../models/virtual_phone/vp_contact.dart';
import '../../models/virtual_phone/vp_moment.dart';
import '../../models/virtual_phone/vp_note.dart';

enum VpAppKind { messages, contacts, notes, moments }

/// 虚拟手机内页（只读）。内容全部虚构、纯本地。
class VpAppPage extends StatelessWidget {
  final VpAppKind kind;
  final String ownerName;

  /// 手机主人（角色本人）头像，用于聊天页气泡/顶栏，视觉对齐单聊。
  final String? ownerAvatarUrl;
  final VirtualPhoneState state;

  const VpAppPage({
    super.key,
    required this.kind,
    required this.ownerName,
    this.ownerAvatarUrl,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_title),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildContent(context)),
    );
  }

  String get _title {
    switch (kind) {
      case VpAppKind.messages:
        return '信息';
      case VpAppKind.contacts:
        return '通讯录';
      case VpAppKind.notes:
        return '备忘录';
      case VpAppKind.moments:
        return '动态';
    }
  }

  Widget _buildContent(BuildContext context) {
    switch (kind) {
      case VpAppKind.messages:
        return _MessagesList(
            state: state,
            ownerName: ownerName,
            ownerAvatarUrl: ownerAvatarUrl);
      case VpAppKind.contacts:
        return _ContactsList(contacts: state.contacts);
      case VpAppKind.notes:
        return _NotesList(notes: state.notes);
      case VpAppKind.moments:
        return _MomentsList(moments: state.moments, ownerName: ownerName);
    }
  }
}

Widget _emptyHint(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ),
    );

// ==================== 信息 ====================

class _MessagesList extends StatelessWidget {
  final VirtualPhoneState state;
  final String ownerName;
  final String? ownerAvatarUrl;
  const _MessagesList(
      {required this.state, required this.ownerName, this.ownerAvatarUrl});

  @override
  Widget build(BuildContext context) {
    if (state.chats.isEmpty) return _emptyHint('还没有聊天记录');
    return ListView.separated(
      itemCount: state.chats.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final chat = state.chats[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF34C759),
            child: Text(
              chat.title.isNotEmpty ? chat.title.characters.first : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(chat.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(chat.lastPreview,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ChatThreadPage(
              chat: chat,
              messages: state.messagesByChat[chat.id] ?? const [],
              ownerName: ownerName,
              ownerAvatarUrl: ownerAvatarUrl,
            ),
          )),
        );
      },
    );
  }
}

/// 虚拟手机聊天记录页 —— 视觉 1:1 对齐单聊页（抖音风）。
/// 手机主人（角色本人，fromOwner=true）在右侧蓝色气泡（等同单聊里的"我"），
/// 对方（chat.title）在左侧白色气泡。纯文本、只读。
class _ChatThreadPage extends StatelessWidget {
  final VpChat chat;
  final List<VpChatMessage> messages;
  final String ownerName;
  final String? ownerAvatarUrl;
  const _ChatThreadPage({
    required this.chat,
    required this.messages,
    required this.ownerName,
    this.ownerAvatarUrl,
  });

  // 抖音风格配色（与单聊 _MessageBubble 保持一致）
  static const Color _douyinBlue = Color(0xFF2B7BF5);
  static const Color _douyinBlueDark = Color(0xFF4A90F7);
  static const Color _bubbleLight = Color(0xFFFFFFFF);
  static const Color _bubbleDark = Color(0xFF2C2C2C);
  static const Color _textOnBlue = Colors.white;
  static const Color _textOnWhite = Color(0xFF1A1A1A);
  static const Color _textOnDark = Color(0xFFE8EAED);
  static const double _avatarSize = 32.0;
  static const double _bubbleRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF000000) : const Color(0xFFF5F5F5);
    final partnerName = chat.title.isEmpty ? '对方' : chat.title;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _appBarAvatar(partnerName),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                partnerName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: messages.isEmpty
            ? _emptyHint('没有消息')
            : ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: messages.length,
                itemBuilder: (context, i) => _row(context, messages[i], isDark),
              ),
      ),
    );
  }

  /// 顶栏对方头像（首字母）+ 绿色在线点，模拟单聊。
  Widget _appBarAvatar(String name) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE8E4EC),
            child: Text(
              name.isNotEmpty ? name.characters.first : '?',
              style: const TextStyle(
                  color: Color(0xFF9C27B0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, VpChatMessage m, bool isDark) {
    final mine = m.fromOwner; // 主人（角色）在右，等同单聊里的"我"
    final bubbleColor = mine
        ? (isDark ? _douyinBlueDark : _douyinBlue)
        : (isDark ? _bubbleDark : _bubbleLight);
    final textColor =
        mine ? _textOnBlue : (isDark ? _textOnDark : _textOnWhite);

    final avatar = mine
        ? _avatar(ownerAvatarUrl, ownerName, isOwner: true)
        : _avatar(null, chat.title, isOwner: false);

    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(_bubbleRadius),
      ),
      child: Text(m.content,
          style: TextStyle(color: textColor, fontSize: 15, height: 1.35)),
    );

    final rowChildren = mine
        ? [bubble, const SizedBox(width: 8), avatar]
        : [avatar, const SizedBox(width: 8), bubble];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ),
          if (m.timeLabel.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                  top: 3, left: mine ? 0 : _avatarSize + 8,
                  right: mine ? _avatarSize + 8 : 0),
              child: Text(m.timeLabel,
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 10)),
            ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, String name, {required bool isOwner}) {
    Widget fallback() => Container(
          width: _avatarSize,
          height: _avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOwner
                ? const Color(0xFFD2E3FC)
                : const Color(0xFFE8E4EC),
          ),
          child: Text(
            name.isNotEmpty ? name.characters.first : '?',
            style: TextStyle(
                color: isOwner
                    ? const Color(0xFF1A73E8)
                    : const Color(0xFF9C27B0),
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
        );

    if (url == null || url.isEmpty) return fallback();

    final isFile =
        url.startsWith('/') || url.startsWith('C:') || url.startsWith('\\');
    return SizedBox(
      width: _avatarSize,
      height: _avatarSize,
      child: ClipOval(
        child: isFile
            ? Image.file(File(url),
                width: _avatarSize,
                height: _avatarSize,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback())
            : Image.network(url,
                width: _avatarSize,
                height: _avatarSize,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback()),
      ),
    );
  }
}

// ==================== 通讯录 ====================

class _ContactsList extends StatelessWidget {
  final List<VpContact> contacts;
  const _ContactsList({required this.contacts});

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return _emptyHint('通讯录是空的');
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final c = contacts[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(c.accentColor),
            child: Text(
              c.name.isNotEmpty ? c.name.characters.first : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                  child: Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (c.isUser) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('我',
                      style: TextStyle(
                          color: Color(0xFFFF2D55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          subtitle: Text(
            [c.relation, c.note].where((e) => e.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

// ==================== 备忘录 ====================

class _NotesList extends StatelessWidget {
  final List<VpNote> notes;
  const _NotesList({required this.notes});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return _emptyHint('没有备忘');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final n = notes[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title.isEmpty ? '无标题' : n.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    if (n.aboutUser)
                      const Icon(Icons.favorite,
                          color: Color(0xFFFF2D55), size: 16),
                  ],
                ),
                if (n.dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(n.dateLabel,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
                const SizedBox(height: 8),
                Text(n.body, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==================== 动态 ====================

class _MomentsList extends StatelessWidget {
  final List<VpMoment> moments;
  final String ownerName;
  const _MomentsList({required this.moments, required this.ownerName});

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) return _emptyHint('还没有动态');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: moments.length,
      itemBuilder: (context, i) {
        final m = moments[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFFF2D55),
                      child: Text(
                        ownerName.isNotEmpty ? ownerName.characters.first : '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(ownerName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (m.timeLabel.isNotEmpty)
                      Text(m.timeLabel,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(m.content, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.favorite,
                        color: Color(0xFFFF2D55), size: 15),
                    const SizedBox(width: 4),
                    Text('${m.likes}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                if (m.commentList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceVariant
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: m.commentList
                          .map((c) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2),
                                child: Text(c,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
