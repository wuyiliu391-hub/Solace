// ============================================================
// 全生命周期数字生命世界 — Phase 6
// 角色详情页：展示单个角色的完整生命画像（简洁版）
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/life_profile.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/heartbeat_service.dart';
/// 角色详情页 — 展示单个角色的完整生命画像
class CharacterDetailScreen extends StatefulWidget {
  final String characterId;

  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── 世界引擎数据 ──
  Map<String, dynamic> _character = {};
  bool _loading = true;
  AICharacter? _aiCharacter; // 保存角色引用用于更新


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRealData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRealData() async {
    try {
      final heartbeat = RepositoryProvider.of<HeartbeatService>(context);
      final engine = heartbeat.worldEngine;
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      final aiChar = await storage.getAICharacter(widget.characterId);
      _aiCharacter = aiChar; // 保存角色引用


      LifeProfile? profile;
      if (engine != null && engine.isInitialized) {
        profile = engine.getProfile(widget.characterId);
      }

      if (profile == null) {
        _character = _buildFallbackCharacter(aiChar);
      } else {
        _character = _buildFromLifeProfile(profile, aiChar);
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('CharacterDetailScreen: 加载失败 $e');
      if (mounted) {
        setState(() {
          _character = _buildFallbackCharacter(null);
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildFromLifeProfile(LifeProfile profile, AICharacter? aiChar) {
    final genes = profile.genes;
    final stageLabel = _stageLabel(profile.currentStage);
    final stateLabel = _stateLabel(profile.lifeState);

    return {
      'name': aiChar?.name ?? profile.name,
      'age': profile.biologicalAge,
      'stage': stageLabel,
      'lifeState': stateLabel,
      'genes': {
        'openness': genes.openness,
        'conscientiousness': genes.conscientiousness,
        'extraversion': genes.extraversion,
        'agreeableness': genes.agreeableness,
        'neuroticism': genes.neuroticism,
        'talents': {for (final t in genes.talents.entries) t.key: t.value},
        'vitality': genes.vitality,
        'resilience': genes.resilience,
        'sensitivity': genes.sensitivity,
      },
      'personality': _toMap(profile.personalityState),
      'worldview': _toMap(profile.worldviewState),
      'identity': _toMap(profile.identity),
      'emotions': _toMap(profile.emotionalState),
      'maslow': _toMap(profile.maslowState),
      'lifeEvents': profile.lifeEvents,
      'memories': [],
      'relationships': [],
      'family': _buildFamilyFallback(),
    };
  }

  Map<String, dynamic> _buildFallbackCharacter(AICharacter? aiChar) {
    if (aiChar == null) return _buildEmptyCharacter();
    final age = DateTime.now().difference(aiChar.createdAt).inDays ~/ 365;
    final stage = LifeProfile.stageForAge(age);
    return {
      'name': aiChar.name,
      'age': age,
      'stage': _stageLabel(stage),
      'lifeState': '存活',
      'genes': {
        'openness': 0.5, 'conscientiousness': 0.5,
        'extraversion': 0.5, 'agreeableness': 0.5, 'neuroticism': 0.5,
        'talents': {}, 'vitality': 0.5, 'resilience': 0.5, 'sensitivity': 0.5,
      },
      'personality': {},
      'worldview': {},
      'identity': {
        'selfDescription': '',
        'coreMotivation': aiChar.coreDesire,
        'biggestFear': '',
        'innerConflicts': [],
      },
      'emotions': {},
      'maslow': {},
      'lifeEvents': [],
      'memories': [],
      'relationships': [],
      'family': _buildFamilyFallback(),
    };
  }

  Map<String, dynamic> _buildEmptyCharacter() {
    return {
      'name': '未知角色', 'age': 0, 'stage': '未知', 'lifeState': '存活',
      'genes': {}, 'personality': {}, 'worldview': {}, 'identity': {},
      'emotions': {}, 'maslow': {}, 'lifeEvents': [],
      'memories': [], 'relationships': [], 'family': _buildFamilyFallback(),
    };
  }

  Map<String, dynamic> _buildFamilyFallback() => {
    'description': '信息暂缺',
    'wealth': 0.5, 'warmth': 0.5, 'strictness': 0.5,
  };

  Map<String, dynamic> _toMap(Map<String, dynamic>? map) => map ?? {};

  String _stageLabel(LifeStage stage) {
    const labels = {
      LifeStage.infant: '婴儿期', LifeStage.toddler: '幼儿期',
      LifeStage.childhood: '童年期', LifeStage.teenage: '青春期',
      LifeStage.youngAdult: '青年期', LifeStage.adult: '中年期',
      LifeStage.senior: '老年期', LifeStage.elder: '暮年',
    };
    return labels[stage] ?? '未知';
  }

  String _stateLabel(LifeState state) {
    const labels = {
      LifeState.alive: '存活', LifeState.aging: '衰老中',
      LifeState.deceased: '已故', LifeState.immortal: '数字永生',
    };
    return labels[state] ?? '未知';
  }

  // ══════════════════════════════════════════
  // 编辑年龄方法
  // ══════════════════════════════════════════

  void _editAge() {
    final currentAge = _character['age'] as int? ?? 0;
    final TextEditingController ageController = TextEditingController(
      text: currentAge.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '修改年龄',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: ageController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '年龄',
            hintText: '请输入年龄',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A73E8)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAge = int.tryParse(ageController.text);
              if (newAge != null && newAge >= 0 && newAge <= 200) {
                Navigator.pop(context);
                await _saveAge(newAge);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '保存',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAge(int newAge) async {
    if (_aiCharacter == null) return;

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final updatedCharacter = _aiCharacter!.copyWith(age: newAge);
      await storage.saveAICharacter(updatedCharacter);
      _aiCharacter = updatedCharacter;

      // 更新本地状态
      setState(() {
        _character['age'] = newAge;
        final stage = LifeProfile.stageForAge(newAge);
        _character['stage'] = _stageLabel(stage);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('年龄已更新为 $newAge 岁'),
            backgroundColor: const Color(0xFF1A73E8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('保存年龄失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _character['name'] as String? ?? '未知';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F9FA),
              Color(0xFFE8F0FE),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: Column(
          children: [
            // 自定义 AppBar
            _buildCustomAppBar(name),
            // Tab 栏
            _buildTabBar(),
            // Tab 内容
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1A73E8),
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(context),
                        _buildInnerTab(context),
                        _buildSocialTab(context),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 48, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A73E8).withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Color(0xFF1A73E8),
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '✨ $name ✨',
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A73E8), Color(0xFF1A73E8)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A73E8).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF5F6368),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: '概况'),
          Tab(text: '内心'),
          Tab(text: '社交'),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // Tab 1: 概况（基本信息 + 基因 + 家庭 + 人生关键时刻）- 梦幻风格
  // ════════════════════════════════════════════════

  Widget _buildOverviewTab(BuildContext context) {
    final name = _character['name'] as String? ?? '';
    final age = _character['age'] as int? ?? 0;
    final stage = _character['stage'] as String? ?? '';
    final lifeState = _character['lifeState'] as String? ?? '存活';
    final genes = _character['genes'] as Map<String, dynamic>? ?? {};
    final family = _character['family'] as Map<String, dynamic>? ?? {};
    final lifeEvents = (_character['lifeEvents'] as List<dynamic>?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 基本信息卡片
        _buildProfileCard(name, age, stage, lifeState),
        const SizedBox(height: 20),
        // 人格五因子（进度条）
        _buildSectionHeader(Icons.psychology, '人格五因子'),
        const SizedBox(height: 12),
        _buildBigFiveCard(genes),
        const SizedBox(height: 20),
        // 体质
        _buildSectionHeader(Icons.favorite, '体质'),
        const SizedBox(height: 12),
        _buildPhysicalCard(genes),
        const SizedBox(height: 20),
        // 原生家庭
        _buildSectionHeader(Icons.home, '原生家庭'),
        const SizedBox(height: 12),
        _buildFamilyCard(family),
        const SizedBox(height: 20),
        // 人生关键时刻
        _buildSectionHeader(Icons.auto_awesome, '人生关键时刻'),
        const SizedBox(height: 12),
        _buildKeyEventsCard(lifeEvents),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildProfileCard(String name, int age, String stage, String lifeState) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A73E8),
            Color(0xFF1A73E8),
            Color(0xFF4285F4),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.person, size: 36, color: Colors.white),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _editAge,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$age 岁 · $stage',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLifeStateChip(lifeState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifeStateChip(String state) {
    Color color;
    IconData icon;
    switch (state) {
      case '存活':
        color = const Color(0xFF1A73E8);
        icon = Icons.favorite;
        break;
      case '衰老中':
        color = const Color(0xFFFFB74D);
        icon = Icons.hourglass_bottom;
        break;
      case '已故':
        color = Colors.grey;
        icon = Icons.remove_circle_outline;
        break;
      default:
        color = const Color(0xFF1A73E8);
        icon = Icons.auto_awesome;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            state,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 人格五因子（进度条版）- 梦幻风格
  Widget _buildBigFiveCard(Map<String, dynamic> genes) {
    const dims = ['openness', 'conscientiousness', 'extraversion', 'agreeableness', 'neuroticism'];
    const labels = ['开放性', '尽责性', '外向性', '宜人性', '神经质'];
    const colors = [
      Color(0xFF1A73E8),
      Color(0xFF1A73E8),
      Color(0xFF4285F4),
      Color(0xFF5E97F6),
      Color(0xFF8AB4F8),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(dims.length, (i) {
            final value = (genes[dims[i]] as num?)?.toDouble() ?? 0.5;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildProgressBar(labels[i], value, colors[i]),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPhysicalCard(Map<String, dynamic> genes) {
    final vitality = (genes['vitality'] as num?)?.toDouble() ?? 0.5;
    final resilience = (genes['resilience'] as num?)?.toDouble() ?? 0.5;
    final sensitivity = (genes['sensitivity'] as num?)?.toDouble() ?? 0.5;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProgressBar('生命力', vitality, const Color(0xFF1A73E8)),
            const SizedBox(height: 14),
            _buildProgressBar('韧性', resilience, const Color(0xFF1A73E8)),
            const SizedBox(height: 14),
            _buildProgressBar('敏感度', sensitivity, const Color(0xFF4285F4)),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCard(Map<String, dynamic> family) {
    final desc = family['description'] as String? ?? '未知';
    final wealth = (family['wealth'] as num?)?.toDouble() ?? 0.5;
    final warmth = (family['warmth'] as num?)?.toDouble() ?? 0.5;
    final strictness = (family['strictness'] as num?)?.toDouble() ?? 0.5;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              desc,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5F6368),
              ),
            ),
            const SizedBox(height: 16),
            _buildProgressBar('经济水平', wealth, const Color(0xFF1A73E8)),
            const SizedBox(height: 12),
            _buildProgressBar('家庭温暖', warmth, const Color(0xFF1A73E8)),
            const SizedBox(height: 12),
            _buildProgressBar('管教严格', strictness, const Color(0xFF4285F4)),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyEventsCard(List<dynamic> events) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            '暂无关键时刻',
            style: TextStyle(
              color: const Color(0xFF5F6368).withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: events.take(10).length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: const Color(0xFF1A73E8).withOpacity(0.1),
        ),
        itemBuilder: (context, index) {
          final e = events[index] as Map<String, dynamic>;
          final type = e['type'] as String? ?? '';
          final desc = e['description'] as String? ?? '';
          final time = e['timestamp'] as String? ?? '';

          IconData icon;
          Color color;
          switch (type) {
            case 'birth':
              icon = Icons.cake;
              color = const Color(0xFF1A73E8);
              break;
            case 'first_love':
              icon = Icons.favorite;
              color = const Color(0xFF1A73E8);
              break;
            case 'heartbreak':
              icon = Icons.heart_broken;
              color = const Color(0xFF4285F4);
              break;
            case 'achievement':
              icon = Icons.emoji_events;
              color = const Color(0xFFFFB74D);
              break;
            case 'trauma':
              icon = Icons.bolt;
              color = const Color(0xFF5E97F6);
              break;
            default:
              icon = Icons.event;
              color = const Color(0xFF1A73E8);
          }

          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            title: Text(
              desc,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A1A),
              ),
            ),
            subtitle: time.isNotEmpty
                ? Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFF5F6368).withOpacity(0.6),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════
  // Tab 2: 内心（马斯洛 + 动态人格 + 三观 + 身份 + 情绪）- 梦幻风格
  // ════════════════════════════════════════════════

  Widget _buildInnerTab(BuildContext context) {
    final personality = _character['personality'] as Map<String, dynamic>? ?? {};
    final worldview = _character['worldview'] as Map<String, dynamic>? ?? {};
    final identity = _character['identity'] as Map<String, dynamic>? ?? {};
    final emotions = _character['emotions'] as Map<String, dynamic>? ?? {};
    final maslow = _character['maslow'] as Map<String, dynamic>? ?? {};
    final genes = _character['genes'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 马斯洛需求
        _buildSectionHeader(Icons.layers, '马斯洛需求'),
        const SizedBox(height: 12),
        _buildMaslowCard(maslow),
        const SizedBox(height: 20),
        // 动态人格（当前 vs 基线）
        _buildSectionHeader(Icons.psychology, '动态人格'),
        const SizedBox(height: 12),
        _buildPersonalityCard(personality, genes),
        const SizedBox(height: 20),
        // 三观标签
        _buildSectionHeader(Icons.visibility, '三观标签'),
        const SizedBox(height: 12),
        _buildWorldviewCard(worldview),
        const SizedBox(height: 20),
        // 身份认同
        _buildSectionHeader(Icons.face, '身份认同'),
        const SizedBox(height: 12),
        _buildIdentityCard(identity),
        const SizedBox(height: 20),
        // 情绪状态
        _buildSectionHeader(Icons.emoji_emotions, '情绪状态'),
        const SizedBox(height: 12),
        _buildEmotionCard(emotions),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMaslowCard(Map<String, dynamic> maslow) {
    const layers = [
      ('physiological', '生理需求', Icons.restaurant, Color(0xFF1A73E8)),
      ('safety', '安全需求', Icons.shield, Color(0xFF1A73E8)),
      ('belonging', '归属与爱', Icons.favorite, Color(0xFF4285F4)),
      ('esteem', '尊重需求', Icons.star, Color(0xFF5E97F6)),
      ('selfActualization', '自我实现', Icons.auto_awesome, Color(0xFF8AB4F8)),
      ('transcendence', '精神超越', Icons.cloud, Color(0xFF1A73E8)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: layers.map((layer) {
            final value = (maslow[layer.$1] as num?)?.toDouble() ?? 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: layer.$4.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(layer.$3, size: 18, color: layer.$4),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 72,
                    child: Text(
                      layer.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: value.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: layer.$4.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(layer.$4.withOpacity(0.8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(value * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: layer.$4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPersonalityCard(Map<String, dynamic> personality, Map<String, dynamic> genes) {
    const dims = ['openness', 'conscientiousness', 'extraversion', 'agreeableness', 'neuroticism'];
    const labels = ['开放性', '尽责性', '外向性', '宜人性', '神经质'];
    const colors = [
      Color(0xFF1A73E8),
      Color(0xFF1A73E8),
      Color(0xFF4285F4),
      Color(0xFF5E97F6),
      Color(0xFF8AB4F8),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(dims.length, (i) {
            final current = (personality[dims[i]] as num?)?.toDouble() ?? 0.5;
            final baseline = (genes[dims[i]] as num?)?.toDouble() ?? 0.5;
            final delta = current - baseline;
            final deltaStr = delta.abs() < 0.01 ? '—' : '${delta > 0 ? '+' : ''}${(delta * 100).toInt()}%';
            final deltaColor = delta >= 0 ? const Color(0xFF1A73E8) : const Color(0xFF4285F4);

            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          labels[i],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            // 基线（灰色底）
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: baseline,
                                minHeight: 16,
                                backgroundColor: const Color(0xFFE8F0FE),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFFE0D0F0)),
                              ),
                            ),
                            // 当前值
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: current,
                                minHeight: 16,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation(colors[i].withOpacity(0.7)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(current * 100).toInt()}%',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors[i],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Row(
                      children: [
                        Text(
                          '基线 ${(baseline * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: const Color(0xFF5F6368).withOpacity(0.5),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          deltaStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: deltaColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildWorldviewCard(Map<String, dynamic> worldview) {
    final beliefs = (worldview['beliefs'] as List<dynamic>?)?.cast<String>() ?? [];
    final crystallization = (worldview['crystallization'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (beliefs.isEmpty)
              Text(
                '三观尚未成型',
                style: TextStyle(
                  color: const Color(0xFF5F6368).withOpacity(0.5),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: beliefs.map((b) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A73E8).withOpacity(0.1),
                        const Color(0xFF1A73E8).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF1A73E8).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF1A73E8)),
                      const SizedBox(width: 6),
                      Text(
                        b,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  '固化程度',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5F6368),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: crystallization,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE8F0FE),
                      valueColor: AlwaysStoppedAnimation(
                        Color.lerp(const Color(0xFF1A73E8), const Color(0xFF4285F4), crystallization)!,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(crystallization * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1A73E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard(Map<String, dynamic> identity) {
    final selfDesc = identity['selfDescription'] as String? ?? '';
    final coreMotivation = identity['coreMotivation'] as String? ?? '';
    final biggestFear = identity['biggestFear'] as String? ?? '';
    final innerConflicts = (identity['innerConflicts'] as List<dynamic>?)?.cast<String>() ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selfDesc.isNotEmpty) _buildIdentityRow('自我描述', selfDesc, Icons.person_outline),
            if (coreMotivation.isNotEmpty) _buildIdentityRow('核心动机', coreMotivation, Icons.track_changes),
            if (biggestFear.isNotEmpty) _buildIdentityRow('最大恐惧', biggestFear, Icons.warning_amber),
            if (innerConflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '内在矛盾',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              ...innerConflicts.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz,
                      size: 16,
                      color: Color(0xFF4285F4),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF5F6368).withOpacity(0.8),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1A73E8)),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF5F6368),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionCard(Map<String, dynamic> emotions) {
    const emotionMap = [
      ('joy', '喜悦', Color(0xFF1A73E8)),
      ('trust', '信任', Color(0xFF1A73E8)),
      ('fear', '恐惧', Color(0xFF4285F4)),
      ('surprise', '惊讶', Color(0xFFFFB74D)),
      ('sadness', '悲伤', Color(0xFF5E97F6)),
      ('disgust', '厌恶', Color(0xFF8AB4F8)),
      ('anger', '愤怒', Color(0xFFE53935)),
      ('anticipation', '期待', Color(0xFF1A73E8)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: emotionMap.map((e) {
            final value = (emotions[e.$1] as num?)?.toDouble() ?? 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        e.$3.withOpacity(value.clamp(0.1, 1.0)),
                        e.$3.withOpacity(value.clamp(0.05, 0.8)),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: e.$3.withOpacity(0.3),
                      width: value > 0.5 ? 2 : 1,
                    ),
                    boxShadow: value > 0.3
                        ? [
                            BoxShadow(
                              color: e.$3.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${(value * 100).toInt()}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: value > 0.5 ? Colors.white : e.$3.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  e.$2,
                  style: TextStyle(
                    fontSize: 12,
                    color: e.$3.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════
  // Tab 3: 社交（关系列表）- 梦幻风格
  // ════════════════════════════════════════════════

  Widget _buildSocialTab(BuildContext context) {
    final relationships = (_character['relationships'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    if (relationships.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 72,
              color: const Color(0xFF1A73E8).withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            const Text(
              '暂无社交关系',
              style: TextStyle(
                fontSize: 18,
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '与其他角色互动将建立关系',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF5F6368).withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: relationships.length,
      itemBuilder: (context, index) {
        final rel = relationships[index];
        final name = rel['name'] as String? ?? '';
        final type = rel['type'] as String? ?? '';
        final intimacy = (rel['intimacy'] as num?)?.toDouble() ?? 0.0;
        final trust = (rel['trust'] as num?)?.toDouble() ?? 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A73E8).withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A73E8), Color(0xFF1A73E8)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A73E8).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF1A73E8).withOpacity(0.1),
                                  const Color(0xFF1A73E8).withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF1A73E8).withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF1A73E8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildMiniBar('亲密度', intimacy, const Color(0xFF1A73E8)),
                          const SizedBox(width: 20),
                          _buildMiniBar('信任度', trust, const Color(0xFF4285F4)),
                        ],
                      ),
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

  // ════════════════════════════════════════════════
  // 通用组件 - 梦幻风格
  // ════════════════════════════════════════════════

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF1A73E8), size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF5F6368),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          child: Text(
            '${(value * 100).toInt()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniBar(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
