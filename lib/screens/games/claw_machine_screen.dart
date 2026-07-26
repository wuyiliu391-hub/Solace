import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/claw_dolls.dart';
import '../../config/constants.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../services/claw_service.dart';
import '../../services/game_service.dart';
import '../../repositories/local_storage_repository.dart';
import 'doll_cabinet_screen.dart';

/// 机台上的一只娃娃（带水平位置与是否已被抓走）
class _StageDoll {
  final ClawDoll doll;
  double x; // 0~1 归一化水平位置
  bool taken;
  _StageDoll(this.doll, this.x, {this.taken = false});
}

/// 抓娃娃机 —— 移动爪子对位 + 下爪，AI 角色实时陪玩。
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

  double _clawX = 0.5;
  final List<_StageDoll> _dolls = [];
  _StageDoll? _grabbed;
  int _coins = 0;
  int _missStreak = 0;
  bool _busy = false;
  String? _aiLine;
  bool _aiThinking = false;

  static const double _stageHeight = 380;
  static const double _dollBottom = 14;
  static const double _clawTravel = 210; // 爪子最大下降距离

  String get _charName =>
      widget.character.userAlias ?? widget.character.name;

  @override
  void initState() {
    super.initState();
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    _claw = ClawService(storage);
    _game = GameService(storage);
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
      // 均匀分布 + 轻微错位
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

  Future<void> _greet() async {
    setState(() => _aiThinking = true);
    try {
      final line = await _game.clawGreeting(character: widget.character);
      if (mounted) setState(() => _aiLine = line.trim());
    } catch (_) {
      if (mounted) setState(() => _aiLine = '来吧，我陪你抓娃娃～');
    } finally {
      if (mounted) setState(() => _aiThinking = false);
    }
  }

  void _move(double delta) {
    if (_busy) return;
    setState(() => _clawX = (_clawX + delta).clamp(0.06, 0.94));
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
    setState(() {
      _busy = true;
      _coins -= ClawConfig.costPerPlay;
      _aiLine = null;
    });

    await _drop.forward(from: 0); // 爪子下降

    final target = _pickTarget();
    final caught = target != null && _claw.rollCatch(target.doll.rarity);
    if (caught) {
      setState(() {
        _grabbed = target;
        target.taken = true;
      });
    }

    await _drop.reverse(); // 爪子上升

    if (caught) {
      final doll = target.doll;
      await _claw.addDoll(
        doll,
        characterId: widget.character.id,
        characterName: _charName,
      );
      _missStreak = 0;
      _showCatchResult(doll);
      _react('caught', dollName: doll.name, rarityLabel: doll.rarity.label);
    } else {
      _missStreak++;
      _react('miss', missStreak: _missStreak);
    }

    setState(() {
      _grabbed = null;
      _busy = false;
    });
    _refillIfNeeded();
  }

  Future<void> _react(String outcome,
      {String? dollName, String? rarityLabel, int missStreak = 0}) async {
    setState(() => _aiThinking = true);
    try {
      final line = await _game.reactToClawResult(
        character: widget.character,
        outcome: outcome,
        dollName: dollName,
        rarityLabel: rarityLabel,
        missStreak: missStreak,
      );
      if (mounted) setState(() => _aiLine = line.trim());
    } catch (_) {
      if (mounted) {
        setState(() => _aiLine =
            outcome == 'caught' ? '哇，抓到啦！' : '差一点点，再试一次嘛～');
      }
    } finally {
      if (mounted) setState(() => _aiThinking = false);
    }
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cs.primaryContainer,
            child: Text(_charName.isNotEmpty ? _charName[0] : '?',
                style: TextStyle(color: cs.onPrimaryContainer)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _aiThinking
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.primary)),
                      const SizedBox(width: 8),
                      Text('$_charName 正在说话…',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ])
                  : Text(_aiLine ?? '准备好了吗？移动爪子，对准娃娃下爪！'),
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
                    // 顶部横杆
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
                    // 机台里的娃娃
                    ..._dolls.where((d) => !d.taken).map((d) {
                      return Positioned(
                        bottom: _dollBottom,
                        left: (d.x * w - 22).clamp(0.0, w - 44),
                        child: Text(d.doll.emoji,
                            style: const TextStyle(fontSize: 40)),
                      );
                    }),
                    // 爪子（含抓中的娃娃）
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
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
                    Text('-${ClawConfig.costPerPlay} 金币',
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
          Text('移动爪子对准娃娃，越稀有越滑手',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
