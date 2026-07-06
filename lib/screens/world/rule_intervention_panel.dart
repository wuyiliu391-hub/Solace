// ============================================================
// 全生命周期数字生命世界 — Phase 6
// 规则干预面板：创世者控制世界的上帝面板
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/life_profile.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/heartbeat_service.dart';
import '../../services/world_engine.dart';
import '../../services/global_time_clock.dart';

/// 世界事件类型
enum WorldEventType {
  disaster('灾难', Icons.warning_amber_rounded, Color(0xFFD32F2F)),
  festival('节日', Icons.celebration, Color(0xFFFFB74D)),
  eraChange('时代变革', Icons.change_history, Color(0xFF7E57C2)),
  plague('瘟疫', Icons.coronavirus, Color(0xFF795548)),
  war('战争', Icons.gavel, Color(0xFF455A64)),
  goldenAge('盛世', Icons.auto_awesome, Color(0xFFFFD700)),
  naturalDisaster('天灾', Icons.thunderstorm, Color(0xFF1565C0)),
  socialUpheaval('社会动荡', Icons.groups, Color(0xFFEF5350)),
  ;

  final String label;
  final IconData icon;
  final Color color;
  const WorldEventType(this.label, this.icon, this.color);
}

/// 角色干预事件类型
enum CharacterInterventionType {
  achievement('成就', Icons.emoji_events, Color(0xFF4CAF50)),
  trauma('创伤', Icons.heart_broken, Color(0xFFD32F2F)),
  encounter('相遇', Icons.people, Color(0xFF2196F3)),
  betrayal('背叛', Icons.back_hand, Color(0xFF9C27B0)),
  revelation('顿悟', Icons.lightbulb, Color(0xFFFFC107)),
  loss('失去', Icons.remove_circle_outline, Color(0xFF607D8B)),
  recovery('治愈', Icons.healing, Color(0xFF66BB6A)),
  temptation('诱惑', Icons.whatshot, Color(0xFFFF5722)),
  ;

  final String label;
  final IconData icon;
  final Color color;
  const CharacterInterventionType(this.label, this.icon, this.color);
}

/// 世界日志条目
class WorldLogEntry {
  final DateTime timestamp;
  final String category;
  final String description;
  final IconData icon;
  final Color color;

  const WorldLogEntry({
    required this.timestamp,
    required this.category,
    required this.description,
    this.icon = Icons.circle,
    this.color = Colors.grey,
  });
}

/// 规则干预面板 — 创世者控制世界的上帝面板
class RuleInterventionPanelScreen extends StatefulWidget {
  const RuleInterventionPanelScreen({super.key});

  @override
  State<RuleInterventionPanelScreen> createState() =>
      _RuleInterventionPanelScreenState();
}

class _RuleInterventionPanelScreenState
    extends State<RuleInterventionPanelScreen> {
  // ── 时间控制状态 ──
  bool _isWorldPaused = false;
  double _timeSpeed = 1.0;
  DateTime _worldTime = DateTime.now();

  // ── 事件注入状态 ──
  WorldEventType _selectedWorldEvent = WorldEventType.disaster;
  final TextEditingController _eventParamController = TextEditingController();

  // ── 角色干预状态 ──
  String? _selectedCharacterId;
  CharacterInterventionType _selectedCharEvent =
      CharacterInterventionType.achievement;
  final TextEditingController _eventDescController = TextEditingController();
  double _emotionalWeight = 0.5;

  // ── 世界参数状态 ──
  double _personalityDriftRate = 0.5;
  double _forgettingRate = 0.5;
  double _conflictProbability = 0.3;
  double _selfProtectionThreshold = 0.5;

  // ── 世界日志 ──
  final List<WorldLogEntry> _worldLogs = [];
  String _logFilterCategory = '全部';

  // ── 角色列表 ──
  List<Map<String, String>> _characters = [];
  WorldEngine? _engine;
  GlobalTimeClock? _clock;

  @override
  void initState() {
    super.initState();
    _loadData();
    _addLog('系统', '创世者打开了规则干预面板', Icons.shield, Colors.teal);
  }

  Future<void> _loadData() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;
      final userId = authState.user.id;

      final heartbeat = RepositoryProvider.of<HeartbeatService>(context);
      final engine = heartbeat.worldEngine;

      final sessions = await storage.getChatSessions(userId);
      final chars = <Map<String, String>>[];
      for (final session in sessions) {
        final char = await storage.getAICharacter(session.aiCharacterId);
        if (char != null) {
          chars.add({'id': char.id, 'name': char.name});
        }
      }

      if (mounted) {
        setState(() {
          _characters = chars;
          _engine = engine;
          _clock = engine?.clock;
          if (_clock != null) {
            _worldTime = _clock!.worldTime;
            _isWorldPaused = _clock!.isPaused;
            _timeSpeed = _clock!.speedMultiplier;
          }
        });
      }
    } catch (e) {
      debugPrint('RuleIntervention: 加载数据失败 $e');
    }
  }

  @override
  void dispose() {
    _eventParamController.dispose();
    _eventDescController.dispose();
    super.dispose();
  }

  void _addLog(String category, String description, IconData icon, Color color) {
    setState(() {
      _worldLogs.insert(
        0,
        WorldLogEntry(
          timestamp: DateTime.now(),
          category: category,
          description: description,
          icon: icon,
          color: color,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('规则干预'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTimeControlCard(cs),
          const SizedBox(height: 12),
          _buildEventInjectionCard(cs),
          const SizedBox(height: 12),
          _buildCharacterInterventionCard(cs),
          const SizedBox(height: 12),
          _buildWorldParameterCard(cs),
          const SizedBox(height: 12),
          _buildWorldLogCard(cs),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // 时间控制卡片
  // ════════════════════════════════════════════════

  Widget _buildTimeControlCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('时间控制', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            // 世界时间显示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('世界时间', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 4),
                  Text(
                    _formatWorldTime(_worldTime),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: cs.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isWorldPaused ? '⏸ 已暂停' : '▶ 运行中 · ${_timeSpeed.toStringAsFixed(1)}x',
                    style: TextStyle(fontSize: 13, color: _isWorldPaused ? cs.error : cs.primary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 暂停/恢复按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _toggleWorldPause,
                icon: Icon(_isWorldPaused ? Icons.play_arrow : Icons.pause),
                label: Text(_isWorldPaused ? '恢复世界' : '暂停世界'),
              ),
            ),
            const SizedBox(height: 16),
            // 流速调节
            Row(
              children: [
                Text('流速', style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7))),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _timeSpeed,
                    min: 0.5,
                    max: 10.0,
                    divisions: 19,
                    label: '${_timeSpeed.toStringAsFixed(1)}x',
                    onChanged: _isWorldPaused ? null : (v) => setState(() => _timeSpeed = v),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${_timeSpeed.toStringAsFixed(1)}x',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
              ],
            ),
            // 速度预设
            Wrap(
              spacing: 8,
              children: [0.5, 1.0, 2.0, 5.0, 10.0].map((speed) {
                final selected = (_timeSpeed - speed).abs() < 0.01;
                return ChoiceChip(
                  label: Text('${speed}x'),
                  selected: selected,
                  onSelected: _isWorldPaused ? null : (_) => setState(() => _timeSpeed = speed),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleWorldPause() {
    setState(() {
      _isWorldPaused = !_isWorldPaused;
    });
    _addLog(
      '系统',
      _isWorldPaused ? '世界已暂停' : '世界已恢复，流速 ${_timeSpeed.toStringAsFixed(1)}x',
      _isWorldPaused ? Icons.pause : Icons.play_arrow,
      _isWorldPaused ? Colors.orange : Colors.green,
    );
  }

  String _formatWorldTime(DateTime t) {
    return '${t.year}-${_pad(t.month)}-${_pad(t.day)} '
        '${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  // ════════════════════════════════════════════════
  // 事件注入卡片
  // ════════════════════════════════════════════════

  Widget _buildEventInjectionCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('事件注入', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            // 事件类型选择
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WorldEventType.values.map((type) {
                final selected = _selectedWorldEvent == type;
                return FilterChip(
                  avatar: Icon(type.icon, size: 16, color: selected ? cs.onSurface : type.color),
                  label: Text(type.label),
                  selected: selected,
                  selectedColor: type.color,
                  onSelected: (_) => setState(() => _selectedWorldEvent = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 事件描述输入
            TextField(
              controller: _eventParamController,
              maxLines: 3,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: '事件参数 / 描述',
                hintText: '例：一场席卷全城的瘟疫，致死率30%...',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 投放按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _injectWorldEvent,
                icon: const Icon(Icons.send),
                label: const Text('投放事件'),
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedWorldEvent.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _injectWorldEvent() {
    final desc = _eventParamController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入事件描述')),
      );
      return;
    }
    _addLog(
      '世界事件',
      '[${_selectedWorldEvent.label}] $desc',
      _selectedWorldEvent.icon,
      _selectedWorldEvent.color,
    );
    _eventParamController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已投放「${_selectedWorldEvent.label}」事件'),
        backgroundColor: _selectedWorldEvent.color,
      ),
    );
  }

  // ════════════════════════════════════════════════
  // 角色干预卡片
  // ════════════════════════════════════════════════

  Widget _buildCharacterInterventionCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('角色干预', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            // 选择角色
            DropdownButtonFormField<String>(
              value: _selectedCharacterId,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: '选择角色',
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _characters.map((c) {
                return DropdownMenuItem(value: c['id'], child: Text(c['name']!));
              }).toList(),
              onChanged: (v) => setState(() => _selectedCharacterId = v),
            ),
            const SizedBox(height: 16),
            // 事件类型
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CharacterInterventionType.values.map((type) {
                final selected = _selectedCharEvent == type;
                return FilterChip(
                  avatar: Icon(type.icon, size: 16, color: selected ? cs.onSurface : type.color),
                  label: Text(type.label),
                  selected: selected,
                  selectedColor: type.color,
                  onSelected: (_) => setState(() => _selectedCharEvent = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // 事件描述
            TextField(
              controller: _eventDescController,
              maxLines: 3,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: '事件描述',
                hintText: '描述这个生命事件...',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 情感权重
            Row(
              children: [
                Text('情感权重', style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7))),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _emotionalWeight,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: _emotionalWeight.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _emotionalWeight = v),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    _emotionalWeight.toStringAsFixed(1),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
              ],
            ),
            Text(
              _emotionalWeightDesc(_emotionalWeight),
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5), fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            // 注入按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _injectCharacterEvent,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('注入生命事件'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emotionalWeightDesc(double w) {
    if (w < 0.2) return '微风拂面 — 几乎无感';
    if (w < 0.4) return '涟漪泛起 — 轻微触动';
    if (w < 0.6) return '波澜起伏 — 明显影响';
    if (w < 0.8) return '惊涛骇浪 — 深刻改变';
    return '刻骨铭心 — 重塑人生';
  }

  void _injectCharacterEvent() {
    if (_selectedCharacterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择角色')),
      );
      return;
    }
    final desc = _eventDescController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入事件描述')),
      );
      return;
    }
    final charName = _characters
        .firstWhere((c) => c['id'] == _selectedCharacterId)['name'];
    _addLog(
      '角色干预',
      '[$charName] ${_selectedCharEvent.label}: $desc (情感权重: ${_emotionalWeight.toStringAsFixed(1)})',
      _selectedCharEvent.icon,
      _selectedCharEvent.color,
    );
    _eventDescController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已向 $charName 注入「${_selectedCharEvent.label}」事件'),
        backgroundColor: _selectedCharEvent.color,
      ),
    );
  }

  // ════════════════════════════════════════════════
  // 世界参数卡片
  // ════════════════════════════════════════════════

  Widget _buildWorldParameterCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('世界参数', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            _parameterSlider(cs, '人格漂移率', '经历对人格的影响幅度', _personalityDriftRate, Icons.psychology, (v) => setState(() => _personalityDriftRate = v)),
            _parameterSlider(cs, '遗忘速率', '记忆自然衰减的速度', _forgettingRate, Icons.visibility_off, (v) => setState(() => _forgettingRate = v)),
            _parameterSlider(cs, '冲突概率', '角色间自发冲突的几率', _conflictProbability, Icons.local_fire_department, (v) => setState(() => _conflictProbability = v)),
            _parameterSlider(cs, '自我保护阈值', '触发防御机制的敏感度', _selfProtectionThreshold, Icons.shield, (v) => setState(() => _selfProtectionThreshold = v)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _applyWorldParameters,
                icon: const Icon(Icons.save),
                label: const Text('应用参数变更'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parameterSlider(
    ColorScheme cs,
    String label,
    String description,
    double value,
    IconData icon,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
              const Spacer(),
              Text(value.toStringAsFixed(2), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
            ],
          ),
          Text(description, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
          Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _applyWorldParameters() {
    _addLog(
      '参数变更',
      '人格漂移率=${_personalityDriftRate.toStringAsFixed(2)}, '
          '遗忘速率=${_forgettingRate.toStringAsFixed(2)}, '
          '冲突概率=${_conflictProbability.toStringAsFixed(2)}, '
          '自我保护阈值=${_selfProtectionThreshold.toStringAsFixed(2)}',
      Icons.tune,
      Colors.indigo,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('世界参数已更新')),
    );
  }

  // ════════════════════════════════════════════════
  // 世界日志卡片
  // ════════════════════════════════════════════════

  Widget _buildWorldLogCard(ColorScheme cs) {
    final filtered = _worldLogs.where((log) {
      if (_logFilterCategory != '全部' && log.category != _logFilterCategory) {
        return false;
      }
      return true;
    }).toList();

    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('世界日志', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            // 筛选栏
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final label in ['全部', '系统', '世界事件', '角色干预', '参数变更']) ...[
                    _buildLogFilterChip(label, cs),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 日志列表
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无日志', style: TextStyle(color: cs.onSurface.withOpacity(0.3))),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length.clamp(0, 50),
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.onSurface.withOpacity(0.06)),
                itemBuilder: (context, index) {
                  final log = filtered[index];
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: log.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(log.icon, size: 18, color: log.color),
                    ),
                    title: Text(log.description, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    subtitle: Text(
                      '${_pad(log.timestamp.hour)}:${_pad(log.timestamp.minute)}:${_pad(log.timestamp.second)} · ${log.category}',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4)),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogFilterChip(String label, ColorScheme cs) {
    final selected = _logFilterCategory == label;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _logFilterCategory = label),
      visualDensity: VisualDensity.compact,
    );
  }
}
