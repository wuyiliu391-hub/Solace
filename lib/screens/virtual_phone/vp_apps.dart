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
  final VirtualPhoneState state;

  const VpAppPage({
    super.key,
    required this.kind,
    required this.ownerName,
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
        return _MessagesList(state: state, ownerName: ownerName);
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
  const _MessagesList({required this.state, required this.ownerName});

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
            ),
          )),
        );
      },
    );
  }
}

class _ChatThreadPage extends StatelessWidget {
  final VpChat chat;
  final List<VpChatMessage> messages;
  final String ownerName;
  const _ChatThreadPage({
    required this.chat,
    required this.messages,
    required this.ownerName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(chat.title), centerTitle: true),
      body: SafeArea(
        child: messages.isEmpty
            ? _emptyHint('没有消息')
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[i];
                  return _bubble(context, m);
                },
              ),
      ),
    );
  }

  Widget _bubble(BuildContext context, VpChatMessage m) {
    final theme = Theme.of(context);
    final mine = m.fromOwner; // 手机主人（角色本人）在右侧
    final bg = mine ? const Color(0xFF95EC69) : theme.colorScheme.surfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (m.timeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m.timeLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ),
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(m.content,
                style: TextStyle(
                    color: mine ? Colors.black87 : theme.colorScheme.onSurface)),
          ),
        ],
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
