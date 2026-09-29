import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../blocs/virtual_phone/virtual_phone_bloc.dart';
import '../../models/virtual_phone/vp_chat.dart';
import '../../models/virtual_phone/vp_contact.dart';
import '../../models/virtual_phone/vp_moment.dart';
import '../../models/virtual_phone/vp_note.dart';
import '../../config/phone_theme.dart';
import '../../widgets/phone/phone_glass.dart';
import '../../widgets/message_actions_sheet.dart';
import '../../widgets/message_status_indicator.dart';

enum VpAppKind { messages, contacts, notes, moments }

extension VpAppKindInfo on VpAppKind {
  String get title {
    switch (this) {
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

  IconData get icon {
    switch (this) {
      case VpAppKind.messages:
        return Icons.chat_bubble_rounded;
      case VpAppKind.contacts:
        return Icons.people_alt_rounded;
      case VpAppKind.notes:
        return Icons.edit_note_rounded;
      case VpAppKind.moments:
        return Icons.auto_awesome_rounded;
    }
  }

  Color get accent {
    switch (this) {
      case VpAppKind.messages:
        return const Color(0xFF5AC8FA);
      case VpAppKind.contacts:
        return const Color(0xFF30D158);
      case VpAppKind.notes:
        return const Color(0xFFFFD60A);
      case VpAppKind.moments:
        return const Color(0xFFBF5AF2);
    }
  }

  String get emptyHint {
    switch (this) {
      case VpAppKind.messages:
        return '还没有聊天记录';
      case VpAppKind.contacts:
        return '通讯录是空的';
      case VpAppKind.notes:
        return '没有备忘';
      case VpAppKind.moments:
        return '还没有动态';
    }
  }
}

/// 虚拟手机内页（只读）。
/// 所有内容都使用深层玻璃质感，与手机桌面统一视觉语言。
class VpAppPage extends StatelessWidget {
  final VpAppKind kind;
  final String ownerName;
  final String? ownerAvatarUrl;
  final VirtualPhoneState state;
  final PhoneWallpaperTheme wallpaperTheme;

  const VpAppPage({
    super.key,
    required this.kind,
    required this.ownerName,
    this.ownerAvatarUrl,
    required this.state,
    this.wallpaperTheme = PhoneWallpaperTheme.dawn,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhoneWallpaperPalette.of(wallpaperTheme).mid,
      body: PhoneWallpaper(
        theme: wallpaperTheme,
        child: SafeArea(
          child: Column(
            children: [
              _AppTopBar(kind: kind, onBack: () => Navigator.of(context).maybePop()),
              Expanded(child: _buildContent(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (kind) {
      case VpAppKind.messages:
        return _MessagesList(
          state: state,
          ownerName: ownerName,
          ownerAvatarUrl: ownerAvatarUrl,
          wallpaperTheme: wallpaperTheme,
        );
      case VpAppKind.contacts:
        return _ContactsList(contacts: state.contacts, accent: kind.accent);
      case VpAppKind.notes:
        return _NotesList(notes: state.notes, accent: kind.accent);
      case VpAppKind.moments:
        return _MomentsList(
          moments: state.moments,
          ownerName: ownerName,
          accent: kind.accent,
        );
    }
  }
}

// ─────────────────── 顶栏 ───────────────────

class _AppTopBar extends StatelessWidget {
  final VpAppKind kind;
  final VoidCallback onBack;

  const _AppTopBar({required this.kind, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: PhoneGlassPanel(
        radius: 18,
        fillOpacity: 0.26,
        borderOpacity: 0.45,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: onBack,
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kind.accent.withValues(alpha: 0.9),
                    kind.accent.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: kind.accent.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(kind.icon, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                kind.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── 空状态 ───────────────────

Widget _emptyState(String hint, IconData icon) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────── 信息列表 ───────────────────

class _MessagesList extends StatelessWidget {
  final VirtualPhoneState state;
  final String ownerName;
  final String? ownerAvatarUrl;
  final PhoneWallpaperTheme wallpaperTheme;

  const _MessagesList({
    required this.state,
    required this.ownerName,
    this.ownerAvatarUrl,
    required this.wallpaperTheme,
  });

  @override
  Widget build(BuildContext context) {
    if (state.chats.isEmpty) {
      return _emptyState('还没有聊天记录', Icons.forum_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: state.chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final chat = state.chats[i];
        final letter = chat.title.isNotEmpty
            ? String.fromCharCode(chat.title.runes.first)
            : '?';
        final msgs = state.messagesByChat[chat.id] ?? const <VpChatMessage>[];
        final preview = msgs.isNotEmpty ? msgs.last.content : chat.lastPreview;

        return PhoneGlassPanel(
          radius: 20,
          fillOpacity: 0.26,
          borderOpacity: 0.4,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ChatThreadPage(
              chat: chat,
              messages: msgs,
              ownerName: ownerName,
              ownerAvatarUrl: ownerAvatarUrl,
              wallpaperTheme: wallpaperTheme,
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 渐变头像
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF30D158).withValues(alpha: 0.8),
                        const Color(0xFF30D158).withValues(alpha: 0.5),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF30D158).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (msgs.isNotEmpty && msgs.last.timeLabel.isNotEmpty)
                      Text(
                        msgs.last.timeLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────── 聊天线程 ───────────────────

class _ChatThreadPage extends StatelessWidget {
  final VpChat chat;
  final List<VpChatMessage> messages;
  final String ownerName;
  final String? ownerAvatarUrl;
  final PhoneWallpaperTheme wallpaperTheme;

  const _ChatThreadPage({
    required this.chat,
    required this.messages,
    required this.ownerName,
    this.ownerAvatarUrl,
    required this.wallpaperTheme,
  });

  static const double _avatarSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final partnerName = chat.title.isEmpty ? '对方' : chat.title;

    return Scaffold(
      backgroundColor: PhoneWallpaperPalette.of(wallpaperTheme).mid,
      body: PhoneWallpaper(
        theme: wallpaperTheme,
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: PhoneGlassPanel(
                  radius: 18,
                  fillOpacity: 0.26,
                  borderOpacity: 0.45,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      _chatAvatar(partnerName),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          partnerName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              // 消息区
              Expanded(
                child: messages.isEmpty
                    ? _emptyState('没有消息', Icons.chat_bubble_outline)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => _messageRow(context, messages[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatAvatar(String name) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBF5AF2), Color(0xFF8A5CF6)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? String.fromCharCode(name.runes.first) : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _messageRow(BuildContext context, VpChatMessage m) {
    final mine = m.fromOwner;
    final isRecall = m.content.trim() == '（撤回了一条消息）' ||
        m.content.trim() == '撤回了一条消息';

    if (isRecall) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '撤回了一条消息',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
    }

    // 手机主人（角色本人）：右侧，用品牌色渐变
    // 对方：左侧，用白色半透明
    final bubbleDecoration = mine
        ? BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5AC8FA), Color(0xFF0A84FF)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          );

    final textColor = mine ? Colors.white : Colors.white.withValues(alpha: 0.92);

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: bubbleDecoration,
      child: Text(
        m.content,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
      ),
    );

    final avatar = mine
        ? _messageAvatar(ownerAvatarUrl, ownerName, isOwner: true)
        : _messageAvatar(null, chat.title, isOwner: false);

    return GestureDetector(
      onLongPress: () => _showOptions(context, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: mine
                  ? [bubble, const SizedBox(width: 8), avatar]
                  : [avatar, const SizedBox(width: 8), bubble],
            ),
            if (m.timeLabel.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  left: mine ? 0 : _avatarSize + 8,
                  right: mine ? _avatarSize + 8 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.timeLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const MessageStatusIndicator(
                      state: MessageDeliveryState.sent,
                      showLabel: false,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, VpChatMessage message) {
    MessageActionsSheet.show(
      context: context,
      actions: [
        MessageActionItem(
          label: '复制',
          icon: Icons.copy,
          color: Colors.teal,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('已复制到剪贴板'),
              duration: Duration(seconds: 1),
            ));
          },
        ),
      ],
    );
  }

  Widget _messageAvatar(String? url, String name, {required bool isOwner}) {
    Widget fallback() => Container(
          width: _avatarSize,
          height: _avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isOwner
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5AC8FA), Color(0xFF0A84FF)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFBF5AF2), Color(0xFF8A5CF6)],
                  ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isOwner ? const Color(0xFF0A84FF) : const Color(0xFF8A5CF6))
                    .withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? String.fromCharCode(name.runes.first) : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );

    if (url == null || url.isEmpty) return fallback();

    final isFile = url.startsWith('/') || url.startsWith('C:') || url.startsWith('\\\\');
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOwner ? const Color(0xFF0A84FF) : const Color(0xFF8A5CF6))
                .withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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

// ─────────────────── 通讯录 ───────────────────

class _ContactsList extends StatelessWidget {
  final List<VpContact> contacts;
  final Color accent;
  const _ContactsList({required this.contacts, required this.accent});

  static const _tagColors = [
    Color(0xFF30D158),
    Color(0xFF5AC8FA),
    Color(0xFFFF9F0A),
    Color(0xFFBF5AF2),
    Color(0xFFFF375F),
    Color(0xFF64D2FF),
    Color(0xFFFFD60A),
  ];

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return _emptyState('通讯录是空的', Icons.people_alt_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = contacts[i];
        final letter = c.name.isNotEmpty ? String.fromCharCode(c.name.runes.first) : '?';
        final tagColor = _tagColors[i % _tagColors.length];

        return PhoneGlassPanel(
          radius: 20,
          fillOpacity: 0.26,
          borderOpacity: 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 彩色标签头像
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tagColor.withValues(alpha: 0.85),
                        tagColor.withValues(alpha: 0.55),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tagColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (c.isUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF375F), Color(0xFFFF6B8A)],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF375F)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Text(
                                '我',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (c.relation.isNotEmpty || c.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          [c.relation, c.note].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────── 备忘录 ───────────────────

class _NotesList extends StatelessWidget {
  final List<VpNote> notes;
  final Color accent;
  const _NotesList({required this.notes, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return _emptyState('没有备忘', Icons.edit_note_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final n = notes[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PhoneGlassPanel(
            radius: 20,
            fillOpacity: 0.28,
            borderOpacity: 0.42,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title.isEmpty ? '无标题' : n.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (n.aboutUser)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF375F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite,
                                color: Color(0xFFFF8FAB), size: 12),
                            const SizedBox(width: 3),
                            Text(
                              '关于我',
                              style: TextStyle(
                                color: const Color(0xFFFF8FAB)
                                    .withValues(alpha: 0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (n.dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    n.dateLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  n.body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.55,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────── 动态 ───────────────────

class _MomentsList extends StatelessWidget {
  final List<VpMoment> moments;
  final String ownerName;
  final Color accent;
  const _MomentsList({
    required this.moments,
    required this.ownerName,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) {
      return _emptyState('还没有动态', Icons.auto_awesome_outlined);
    }
    final letter =
        ownerName.isNotEmpty ? String.fromCharCode(ownerName.runes.first) : '?';
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: moments.length,
      itemBuilder: (context, i) {
        final m = moments[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PhoneGlassPanel(
            radius: 20,
            fillOpacity: 0.28,
            borderOpacity: 0.42,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF375F), Color(0xFFFF6B8A)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF375F)
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          letter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ownerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (m.timeLabel.isNotEmpty)
                          Text(
                            m.timeLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  m.content,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
                if (m.likes > 0 || m.commentList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.favorite_rounded,
                          color: const Color(0xFFFF8FAB)
                              .withValues(alpha: 0.8),
                          size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '${m.likes}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (m.commentList.isNotEmpty)
                        Text(
                          '${m.commentList.length} 条评论',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
                if (m.commentList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: m.commentList
                          .map((c) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
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
