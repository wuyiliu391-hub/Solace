import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../config/claw_dolls.dart';
import '../../models/chat_message.dart';
import '../../models/owned_doll.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/claw_service.dart';

/// 娃娃柜 —— 展示抓到的娃娃，可「送给 TA」提升亲密度。
class DollCabinetScreen extends StatefulWidget {
  const DollCabinetScreen({super.key});

  @override
  State<DollCabinetScreen> createState() => _DollCabinetScreenState();
}

class _DollCabinetScreenState extends State<DollCabinetScreen> {
  late final ClawService _claw;
  List<OwnedDoll> _dolls = [];

  static const int _giftIntimacyReward = 2;

  @override
  void initState() {
    super.initState();
    _claw = ClawService(RepositoryProvider.of<LocalStorageRepository>(context));
    _reload();
  }

  void _reload() {
    setState(() => _dolls = _claw.getCabinet());
  }

  DollRarity _rarityOf(String name) => DollRarity.values.firstWhere(
        (r) => r.name == name,
        orElse: () => DollRarity.common,
      );

  Future<void> _giftDoll(OwnedDoll doll) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final charId = doll.characterId;
    if (charId == null || charId.isEmpty) {
      _toast('这只娃娃没有关联角色，无法赠送');
      return;
    }
    final sessions = await storage.getChatSessionsByCharacterId(charId);
    final session = sessions.isNotEmpty ? sessions.first : null;
    if (session == null) {
      _toast('找不到和 ${doll.characterName ?? "TA"} 的会话');
      return;
    }

    final newLevel = (session.intimacyLevel + _giftIntimacyReward).clamp(0, 100);
    await storage.saveChatSession(session.copyWith(
      intimacyLevel: newLevel,
      lastMessageTime: DateTime.now(),
    ));
    await storage.saveChatMessage(ChatMessage(
      id: 'clawgift_${DateTime.now().millisecondsSinceEpoch}',
      chatId: session.id,
      senderId: 'system',
      content: '把抓到的「${doll.name}」${doll.emoji} 送给了你',
      type: MessageType.system,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
    ));
    await _claw.markGifted(doll.uid);
    _reload();
    _toast('已送给 ${doll.characterName ?? "TA"}，亲密度 +$_giftIntimacyReward ❤️');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _onTapDoll(OwnedDoll doll) {
    final cs = Theme.of(context).colorScheme;
    final rarity = _rarityOf(doll.rarity);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(doll.emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 8),
              Text(doll.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: rarity.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(rarity.label,
                    style: TextStyle(fontSize: 12, color: rarity.color)),
              ),
              const SizedBox(height: 4),
              Text(
                '抓于 ${DateFormat('yyyy/MM/dd HH:mm').format(doll.obtainedAt)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (doll.gifted)
                Text('已送给 ${doll.characterName ?? "TA"}',
                    style: TextStyle(color: cs.onSurfaceVariant))
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _giftDoll(doll);
                    },
                    icon: const Icon(Icons.card_giftcard),
                    label: Text('送给 ${doll.characterName ?? "TA"}（亲密度+2）'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('娃娃柜 · ${_dolls.length} 只'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _dolls.isEmpty
          ? _buildEmpty(cs)
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: _dolls.length,
              itemBuilder: (context, index) {
                final doll = _dolls[index];
                final rarity = _rarityOf(doll.rarity);
                return GestureDetector(
                  onTap: () => _onTapDoll(doll),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: rarity.color.withOpacity(0.4), width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(doll.emoji,
                                style: const TextStyle(fontSize: 40)),
                            if (doll.gifted)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Icon(Icons.favorite,
                                    size: 14, color: cs.primary),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(doll.name,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                        Text(rarity.label,
                            style:
                                TextStyle(fontSize: 10, color: rarity.color)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: cs.onSurface.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('娃娃柜还是空的',
              style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
          const SizedBox(height: 8),
          Text('去抓娃娃机抓几只吧～',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withOpacity(0.3))),
        ],
      ),
    );
  }
}
