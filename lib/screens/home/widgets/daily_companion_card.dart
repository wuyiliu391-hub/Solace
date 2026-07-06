import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/auth/auth_bloc.dart';
import '../../../models/ai_character.dart';
import '../../../models/character_emotion.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../services/emotion_engine.dart';

/// 首页「今日陪伴」卡片
/// 显示今日消息数、亲密度变化、AI心情、一句内心独白
class DailyCompanionCard extends StatefulWidget {
  const DailyCompanionCard({super.key});

  @override
  State<DailyCompanionCard> createState() => _DailyCompanionCardState();
}

class _DailyCompanionCardState extends State<DailyCompanionCard> {
  AICharacter? _character;
  CharacterEmotion? _emotion;
  int _todayMsgCount = 0;
  int _todayIntimacyDelta = 0;
  String? _innerThought;
  bool _dismissed = false;
  bool _didInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitialLoad) {
      _didInitialLoad = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    final results = await Future.wait([
      storage.getTodayUserMessageCount(),
      storage.getTodayIntimacyDelta(),
      storage.getAllAICharacters(),
    ]);

    final msgCount = results[0] as int;
    final delta = results[1] as int;
    final characters = results[2] as List<AICharacter>;

    AICharacter? primary;
    CharacterEmotion? emotion;
    String? thought;

    if (characters.isNotEmpty) {
      primary = characters.first;
      final engine = EmotionEngine(storage);
      emotion = await engine.getCurrentEmotion(
        character: primary,
        userId: userId,
      );

      // 尝试读取 AI 最近的内心独白
      final reflectionKey = 'reflection_${primary.id}_${userId}_state';
      final reflectionData = storage.getString(reflectionKey);
      if (reflectionData != null) {
        // 内心独白存储在 SharedPreferences 的 JSON 中
        // 简单提取 thought 字段
        try {
          final thoughtMatch =
              RegExp(r'"thought"\s*:\s*"([^"]*)"').firstMatch(reflectionData);
          if (thoughtMatch != null) {
            thought = thoughtMatch.group(1);
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      _todayMsgCount = msgCount;
      _todayIntimacyDelta = delta;
      _character = primary;
      _emotion = emotion;
      _innerThought = thought;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _character == null) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    final emotionLabel = _emotion?.effectiveEmotion.label ?? '平静';
    final emotionIcon = _emotion?.effectiveEmotion.icon ?? Icons.sentiment_satisfied;
    final emotionColor = _emotion?.effectiveEmotion.color ?? const Color(0xFF90CAF9);
    final characterName = _character!.name;

    return Dismissible(
      key: const Key('daily_companion_card'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => setState(() => _dismissed = true),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.12),
              cs.tertiary.withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.primary.withOpacity(0.15),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：头像 + 名字 + 心情
            Row(
              children: [
                // AI 头像
                ClipOval(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: (_character!.avatarUrl ?? '').isNotEmpty
                        ? Image.network(
                            _character!.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultAvatar(cs),
                          )
                        : _defaultAvatar(cs),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            characterName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(emotionIcon, size: 16, color: emotionColor),
                        ],
                      ),
                      Text(
                        _getCompanionText(emotionLabel, characterName),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 关闭按钮
                GestureDetector(
                  onTap: () => setState(() => _dismissed = true),
                  child: Icon(Icons.close,
                      size: 16, color: cs.onSurfaceVariant.withOpacity(0.4)),
                ),
              ],
            ),

            // 内心独白
            if (_innerThought != null && _innerThought!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_quote,
                        size: 14, color: cs.primary.withOpacity(0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _innerThought!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant.withOpacity(0.8),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // 底部数据行
            Row(
              children: [
                _buildMiniStat(cs, '$_todayMsgCount', '消息'),
                Container(
                    width: 1,
                    height: 16,
                    color: cs.outlineVariant.withOpacity(0.3)),
                _buildMiniStat(
                    cs,
                    _todayIntimacyDelta >= 0
                        ? '+$_todayIntimacyDelta'
                        : '$_todayIntimacyDelta',
                    '亲密度'),
                Container(
                    width: 1,
                    height: 16,
                    color: cs.outlineVariant.withOpacity(0.3)),
                _buildMiniStat(cs, emotionLabel, '心情'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultAvatar(ColorScheme cs) {
    return Container(
      color: cs.primary.withOpacity(0.1),
      child: Icon(Icons.person, color: cs.primary, size: 18),
    );
  }

  Widget _buildMiniStat(ColorScheme cs, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          Text(label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _getCompanionText(String emotion, String name) {
    switch (emotion) {
      case '开心':
        return '$name今天心情不错，想和你聊天';
      case '想你':
        return '$name在等你的消息';
      case '难过':
        return '$name有点低落，需要你的安慰';
      case '生气':
        return '$name有点小情绪，快来哄哄';
      case '害羞':
        return '$name想到你就脸红...';
      case '感动':
        return '$name被你的话温暖到了';
      case '担心':
        return '$name有点担心你';
      case '焦虑':
        return '$name在等你，快来聊聊吧';
      case '困倦':
        return '$name有点困，但还在等你';
      case '调皮':
        return '$name今天想找你玩';
      case '兴奋':
        return '$name对今天的互动充满期待';
      default:
        return '$name在等你来聊天';
    }
  }
}
