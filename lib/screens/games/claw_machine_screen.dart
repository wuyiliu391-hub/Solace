import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/claw_dolls.dart';
import '../../config/constants.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../services/claw_service.dart';
import '../../services/game_service.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import 'doll_cabinet_screen.dart';

/// 机台上的一只娃娃（带水平位置与是否已被抓走）
class _StageDoll {
  final ClawDoll doll;
  double x; // 0~1 归一化水平位置
  bool taken = false;
  _StageDoll(this.doll, this.x);
}

/// 角色当下的情绪 —— 决定头像上的表情
enum _Mood { idle, aim, drop, happy, sad }

extension _MoodX on _Mood {
  String get emoji {
    switch (this) {
      case _Mood.idle:
        return '🙂';
      case _Mood.aim:
        return '👀';
      case _Mood.drop:
        return '😤';
      case _Mood.happy:
        return '😄';
      case _Mood.sad:
        return '🥺';
    }
  }
}

/// 抓娃娃机 —— 移动爪子对位 + 下爪，AI 角色全程陪玩（打字机台词 + 表情）。
class ClawMachineScreen extends StatefulWidget {
  final AICharacter character;
  final ChatSession session;

  const ClawMachineScreen({
    super.key,
    required this.character,
    required this.session,
  });

  @override
  State<ClawMachineScreen> createState() => _ClawMachineScreenState();
}

class _ClawMachineScreenState extends State<ClawMachineScreen>
    with SingleTickerProviderStateMixin {
  late final ClawService _claw;
  late final GameService _game;
  late final AnimationController _drop;
  final Random _rand = Random();

  double _clawX = 0.5;
  final List<_StageDoll> _dolls = [];
  _StageDoll? _grabbed;
  int _coins = 0;
  int _missStreak = 0;
  bool _busy = false;
  bool _wasAligned = false;

  // 台词打字机
  Timer? _typeTimer;
  String _shownLine = '';
  String _fullLine = '';
  bool _thinking = false; // AI 生成中 → 显示「正在输入…」
  _Mood _mood = _Mood.idle;
  int _reqSeq = 0; // AI 台词请求序列号：旧请求晚到时丢弃，防止乱序覆盖
  bool _coinFree = false; // 金币经济关闭 → 免费畅玩，不显示扣费

  static const double _stageHeight = 380;
  static const double _dollBottom = 14;
  static const double _clawTravel = 210;

  // 高频小互动用本地台词库（省 token），关键节点才调 AI
  static const List<String> _aimLines = [
    '就是这只！对准了~',
    '嗯…这只有戏',
    '稳住，别抖',
    '看好了这只哦',
    '这个位置不错！',
  ];
  static const List<String> _dropLines = [
    '就是现在！',
    '下！冲鸭~',
    '抓住它！',
    '看你的了！',
  ];
  static const List<String> _dropLinesBuff = [
    '我帮你稳住，下！',
    '别慌有我在，抓！',
    '这次我盯着，冲！',
  ];

  bool get _hasBuff => widget.session.intimacyLevel >= 60;
  String get _charName => widget.character.userAlias ?? widget.character.name;

  @override
  void initState() {
    super.initState();
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    _claw = ClawService(storage);
    _game = GameService(storage);
    _coinFree = !storage.isCoinEconomyEnabled();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _spawnDolls();
    _loadCoins();
    _greet();
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _loadCoins() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = await storage.getCurrentUser();
    if (mounted) setState(() => _coins = user?.coins ?? 0);
  }

  void _spawnDolls() {
    final picked = _claw.rollStageDolls();
    _dolls.clear();
    for (var i = 0; i < picked.length; i++) {
      final x = ((i + 0.5) / picked.length).clamp(0.08, 0.92);
      _dolls.add(_StageDoll(picked[i], x.toDouble()));
    }
  }

  void _refillIfNeeded() {
    final alive = _dolls.where((d) => !d.taken).length;
    if (alive >= 4) return;
    final fresh = _claw.rollStageDolls();
    var fi = 0;
    for (var i = 0; i < _dolls.length && fi < fresh.length; i++) {
      if (_dolls[i].taken) {
        _dolls[i] = _StageDoll(fresh[fi], _dolls[i].x);
        fi++;
      }
    }
    if (mounted) setState(() {});
  }

  // ─────────── 台词打字机 ───────────

  /// 逐字显示一句话（本地台词直接用；AI 台词拿到全文后也走这里）
  void _say(String text, {_Mood? mood}) {
    _typeTimer?.cancel();
    final full = text.trim();
    setState(() {
      _thinking = false;
      _fullLine = full;
      _shownLine = '';
      if (mood != null) _mood = mood;
    });
    var i = 0;
    _typeTimer = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (i >= _fullLine.length) {
        t.cancel();
        return;
      }
      i++;
      if (mounted) {
        setState(() => _shownLine = _fullLine.substring(0, i));
      } else {
        t.cancel();
      }
    });
  }

  void _showThinking() {
    _typeTimer?.cancel();
    setState(() {
      _thinking = true;
      _shownLine = '';
    });
  }

  // ─────────── AI 陪玩台词 ───────────

  Future<void> _greet() async {
    final seq = ++_reqSeq;
    _showThinking();
    try {
      // GameService 内部有场景兜底不会抛错；外层 10s 超时防止「正在输入…」长挂
      final line = await _game
          .clawGreeting(character: widget.character)
          .timeout(const Duration(seconds: 10));
      if (mounted && seq == _reqSeq) _say(line, mood: _Mood.idle);
    } catch (_) {
      if (mounted && seq == _reqSeq) _say('来吧，我陪你抓娃娃~', mood: _Mood.idle);
    }
  }

  Future<void> _reactResult(String outcome,
      {String? dollName, String? rarityLabel}) async {
    final seq = ++_reqSeq;
    _showThinking();
    try {
      final line = await _game
          .reactToClawResult(
            character: widget.character,
            outcome: outcome,
            dollName: dollName,
            rarityLabel: rarityLabel,
            missStreak: _missStreak,
          )
          .timeout(const Duration(seconds: 10));
      if (mounted && seq == _reqSeq) {
        _say(line, mood: outcome == 'caught' ? _Mood.happy : _Mood.sad);
      }
    } catch (_) {
      if (mounted && seq == _reqSeq) {
        _say(outcome == 'caught' ? '哇，抓到啦！' : '差一点点，再试一次嘛~',
            mood: outcome == 'caught' ? _Mood.happy : _Mood.sad);
      }
    }
  }

  // ─────────── 操作 ───────────

  void _move(double delta) {
    if (_busy) return;
    setState(() => _clawX = (_clawX + delta).clamp(0.06, 0.94));
    final aligned = _pickTarget() != null;
    if (aligned && !_wasAligned) {
      _say(_aimLines[_rand.nextInt(_aimLines.length)], mood: _Mood.aim);
    } else if (!aligned && _mood == _Mood.aim) {
      setState(() => _mood = _Mood.idle);
    }
    _wasAligned = aligned;
  }

  _StageDoll? _pickTarget() {
    _StageDoll? best;
    double bestDist = ClawConfig.alignThreshold;
    for (final d in _dolls) {
      if (d.taken) continue;
      final dist = (d.x - _clawX).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
      }
    }
    return best;
  }

  Future<void> _dropClaw() async {
    if (_busy) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final userId = storage.getString(PrefKeys.currentUserId) ?? 'default';

    final ok = await storage.spendCoins(userId, ClawConfig.costPerPlay);
    if (!ok) {
      _toast('金币不足，去赚点金币再来吧');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      // 免费模式下 spendCoins 不实际扣费，跳过乐观扣减避免余额显示错误
      if (!_coinFree) _coins -= ClawConfig.costPerPlay;
      _wasAligned = false;
    });

    // 下爪加油（本地台词，亲密度高时是「助攻」语气）
    final cheer = _hasBuff
        ? _dropLinesBuff[_rand.nextInt(_dropLinesBuff.length)]
        : _dropLines[_rand.nextInt(_dropLines.length)];
    _say(cheer, mood: _Mood.drop);

    try {
      await _drop.forward(from: 0).orCancel; // 下降
    } on TickerCanceled {
      return; // 页面已退出，动画被取消
    }
    if (!mounted) return;

    final target = _pickTarget();
    final caught = target != null &&
        _claw.rollCatch(target.doll.rarity,
            multiplier: _hasBuff ? 1.4 : 1.0);
    if (caught) {
      setState(() {
        _grabbed = target;
        target.taken = true;
      });
    }

    try {
      await _drop.reverse().orCancel; // 上升
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;

    if (caught) {
      final doll = target.doll;
      await _claw.addDoll(
        doll,
        characterId: widget.character.id,
        characterName: _charName,
      );
      // 持久化到聊天：这场共同经历在会话里留下痕迹（照送礼的系统消息模式）
      try {
        await storage.saveChatMessage(ChatMessage(
          id: 'claw_${DateTime.now().millisecondsSinceEpoch}',
          chatId: widget.session.id,
          senderId: 'system',
          content: '你们一起玩抓娃娃，抓到了「${doll.name}」${doll.emoji}',
          type: MessageType.system,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
        ));
      } catch (e) {
        debugPrint('抓娃娃系统消息写入失败: $e');
      }
      _missStreak = 0;
      if (mounted) _showCatchResult(doll);
      // fire-and-forget：AI 反应慢时不锁死操作，序列号保证不乱序
      _reactResult('caught',
          dollName: doll.name, rarityLabel: doll.rarity.label);
    } else {
      _missStreak++;
      _reactResult('miss');
    }

    if (!mounted) return;
    setState(() {
      _grabbed = null;
      _busy = false;
    });
    _refillIfNeeded();
    _loadCoins();
  }

  void _showCatchResult(ClawDoll doll) {
    if (!mounted) return;
    if (doll.rarity == DollRarity.common) {
      _toast('获得 ${doll.emoji} ${doll.name}');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(doll.emoji, style: const TextStyle(fontSize: 72)),
            const SizedBox(height: 8),
            Text('${doll.rarity.label} · ${doll.name}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: doll.rarity.color)),
            const SizedBox(height: 4),
            const Text('稀有娃娃到手！'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('太棒了')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)),
    );
  }

  // ─────────── UI ───────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('和 $_charName 抓娃娃'),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (_hasBuff)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('❤️助攻', style: TextStyle(fontSize: 12)),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                const Icon(Icons.monetization_on,
                    color: Color(0xFFFFC107), size: 18),
                const SizedBox(width: 2),
                Text('$_coins',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          IconButton(
            tooltip: '娃娃柜',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DollCabinetScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildAiBubble(cs),
          Expanded(child: _buildStage(cs, isDark)),
          _buildControls(cs),
        ],
      ),
    );
  }

  Widget _buildAiBubble(ColorScheme cs) {
    final avatar = AvatarResolver.imageProvider(widget.character.avatarUrl);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像 + 情绪表情角标
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primaryContainer,
                backgroundImage: avatar,
                child: avatar == null
                    ? Text(_charName.isNotEmpty ? _charName[0] : '?',
                        style: TextStyle(color: cs.onPrimaryContainer))
                    : null,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Text(_mood.emoji, style: const TextStyle(fontSize: 20)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _thinking
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.primary)),
                      const SizedBox(width: 8),
                      Text('$_charName 正在输入…',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ])
                  : Text(_shownLine.isEmpty
                      ? '准备好了吗？移动爪子对准娃娃，下爪！'
                      : _shownLine),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Container(
            height: _stageHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF1A2A3A), const Color(0xFF0D1520)]
                    : [const Color(0xFFB3E5FC), const Color(0xFFE1F5FE)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary.withOpacity(0.3), width: 2),
            ),
            child: AnimatedBuilder(
              animation: _drop,
              builder: (context, _) {
                final clawTop = 6 + _drop.value * _clawTravel;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      top: 4,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    ..._dolls.where((d) => !d.taken).map((d) {
                      return Positioned(
                        bottom: _dollBottom,
                        left: (d.x * w - 22).clamp(0.0, w - 44),
                        child: Text(d.doll.emoji,
                            style: const TextStyle(fontSize: 40)),
                      );
                    }),
                    Positioned(
                      left: (_clawX * w - 20).clamp(0.0, w - 40),
                      top: clawTop,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 3,
                            height: 26,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                          Icon(Icons.pan_tool_alt_outlined,
                              size: 40,
                              color: isDark ? Colors.white : Colors.black87),
                          if (_grabbed != null)
                            Text(_grabbed!.doll.emoji,
                                style: const TextStyle(fontSize: 34)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _dirButton(Icons.chevron_left, () => _move(-0.06)),
              GestureDetector(
                onTap: _busy ? null : _dropClaw,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _busy
                        ? [Colors.grey, Colors.grey.shade600]
                        : [const Color(0xFFFF7043), const Color(0xFFF4511E)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('下爪',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text(_coinFree ? '免费畅玩' : '-${ClawConfig.costPerPlay} 金币',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11)),
                  ]),
                ),
              ),
              _dirButton(Icons.chevron_right, () => _move(0.06)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _hasBuff ? '$_charName 会帮你一把，成功率更高~' : '移动爪子对准娃娃，越稀有越滑手',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _dirButton(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: cs.onSurface),
      ),
    );
  }
}
