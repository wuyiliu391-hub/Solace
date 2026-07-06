// 全生命周期数字生命世界 — 前端修复
// 角色社交档案页面（重写版）
// 接入真实数据，展示完整的社交行为和人格演化

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite/sqflite.dart';
import '../../repositories/local_storage_repository.dart';
import '../../repositories/database_service.dart';
import '../../services/ai_relationship_service.dart';
import '../../services/memory_engine.dart';
import '../../services/persona_evolution_service.dart';
import '../../models/ai_character.dart';
import '../../models/moment.dart';
import '../../models/memory.dart';
import '../../models/personality_state.dart';
import '../../models/worldview.dart';
import '../../models/identity_narrative.dart';
import '../../models/life_profile.dart';
import '../../models/gene_profile.dart';

/// 社交记忆扩展数据（包含 interactionType 和 emotionTag）
class _SocialMemoryEntry {
  final String id;
  final String characterId;
  final String targetCharacterId;
  final String interactionType;
  final String content;
  final String emotionTag;
  final String importance;
  final DateTime timestamp;
  final double weight;

  const _SocialMemoryEntry({
    required this.id,
    required this.characterId,
    required this.targetCharacterId,
    required this.interactionType,
    required this.content,
    required this.emotionTag,
    required this.importance,
    required this.timestamp,
    required this.weight,
  });
}

/// 互动记录类型
enum InteractionType { like, comment }

/// 互动记录
class _InteractionRecord {
  final InteractionType type;
  final String targetName;
  final String targetContent;
  final String? myContent;
  final String momentId;
  final DateTime time;

  _InteractionRecord({
    required this.type,
    required this.targetName,
    required this.targetContent,
    this.myContent,
    required this.momentId,
    required this.time,
  });
}

/// 角色社交档案页面
///
/// 从聊天页右上角进入，查看当前角色的所有社交行为：
/// - 关系网络（与哪些角色有什么关系、亲密度、信任度、熟悉度、紧张度）
/// - 社交动态（串门、点赞、评论、加好友、吵架、反思等）
/// - 朋友圈（该角色发的动态和收到的互动）
/// - 互动记录（点赞/评论别人的详情）
/// - 人格演化（五因子、三观、身份认同、马斯洛需求）
/// - 生命档案（基因、烙印、生命阶段、能力解锁）
class CharacterSocialProfileScreen extends StatefulWidget {
  final AICharacter character;

  const CharacterSocialProfileScreen({super.key, required this.character});

  @override
  State<CharacterSocialProfileScreen> createState() =>
      _CharacterSocialProfileScreenState();
}

class _CharacterSocialProfileScreenState
    extends State<CharacterSocialProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 所有角色
  List<AICharacter> _allCharacters = [];

  // 关系数据
  List<AIRelationship> _relationships = [];

  // 社交记忆（带完整字段）
  List<_SocialMemoryEntry> _socialMemories = [];

  // 该角色的朋友圈动态
  List<Moment> _myMoments = [];

  // 该角色参与的互动（点赞/评论别人）
  List<_InteractionRecord> _interactions = [];

  // 社交动态筛选类型
  String _socialFilter = '全部';

  // ─── Phase 1-5 引擎数据 ───
  PersonalityState? _personalityState;
  GeneProfile? _geneProfile;
  Worldview? _worldview;
  IdentityNarrative? _identityNarrative;
  LifeProfile? _lifeProfile;
  List<Map<String, dynamic>> _maslowState = [];
  List<EvolutionLog> _evolutionLogs = [];
  int _evolutionCount = 0;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final storage =
          RepositoryProvider.of<LocalStorageRepository>(context, listen: false);
      final relService = AIRelationshipService(storage);
      final memoryEngine = MemoryEngine(storage);
      final charId = widget.character.id;

      // 1. 加载所有角色
      _allCharacters = await storage.getAllAICharacters();

      // 2. 加载该角色的关系
      _relationships = await relService.getRelationships(charId);

      // 3. 加载社交记忆（带完整字段）
      _socialMemories = await _loadSocialMemoriesFull(charId);

      // 4. 加载该角色发的朋友圈
      final allMoments = await storage.getAllMoments();
      _myMoments = allMoments
          .where((m) => m.userId == charId && m.source == MomentSource.normal)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // 5. 提取该角色参与的互动（在别人动态下点赞/评论）
      _interactions = [];
      for (final moment in allMoments) {
        if (moment.userId == charId) continue;

        final liked = moment.likes.any((l) => l.userId == charId);
        if (liked) {
          _interactions.add(_InteractionRecord(
            type: InteractionType.like,
            targetName: moment.userName,
            targetContent: moment.content,
            momentId: moment.id,
            time: moment.likes
                .firstWhere((l) => l.userId == charId)
                .createdAt,
          ));
        }

        final myComments = moment.comments.where((c) => c.userId == charId);
        for (final comment in myComments) {
          _interactions.add(_InteractionRecord(
            type: InteractionType.comment,
            targetName: moment.userName,
            targetContent: moment.content,
            myContent: comment.content,
            momentId: moment.id,
            time: comment.createdAt,
          ));
        }
      }
      _interactions.sort((a, b) => b.time.compareTo(a.time));

      // 6. 加载 Phase 1-5 引擎数据
      await _loadLifecycleData(storage, charId);
    } catch (e) {
      debugPrint('CharacterSocialProfile: load error — $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// 直接查询 social_memories 表，获取完整字段
  Future<List<_SocialMemoryEntry>> _loadSocialMemoriesFull(
      String characterId) async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'social_memories',
        where: 'characterId = ?',
        whereArgs: [characterId],
        orderBy: 'timestamp DESC',
        limit: 200,
      );
      return rows.map((row) {
        return _SocialMemoryEntry(
          id: row['id'] as String? ?? '',
          characterId: row['characterId'] as String? ?? '',
          targetCharacterId: row['targetCharacterId'] as String? ?? '',
          interactionType: row['interactionType'] as String? ?? 'chat',
          content: row['content'] as String? ?? '',
          emotionTag: row['emotionTag'] as String? ?? '',
          importance: row['importance'] as String? ?? 'normal',
          timestamp:
              DateTime.tryParse(row['timestamp'] as String? ?? '') ??
                  DateTime.now(),
          weight: (row['weight'] as num?)?.toDouble() ?? 1.0,
        );
      }).toList();
    } catch (e) {
      debugPrint('CharacterSocialProfile: loadSocialMemoriesFull error — $e');
      return [];
    }
  }

  /// 加载生命周期引擎数据（Phase 1-5）
  Future<void> _loadLifecycleData(
      LocalStorageRepository storage, String charId) async {
    try {
      // 人格进化数据
      final evoService = PersonaEvolutionService(storage, MemoryEngine(storage));
      _evolutionLogs = evoService.getChangelog(charId);
      _evolutionCount = evoService.getEvolutionCount(charId);

      // 尝试从 SharedPreferences 加载 LifeProfile
      final lifeProfileJson = storage.getString('life_profile_$charId');
      if (lifeProfileJson != null) {
        _lifeProfile = LifeProfile.fromJson(
            jsonDecode(lifeProfileJson) as Map<String, dynamic>);
        _geneProfile = _lifeProfile!.genes;
        _personalityState =
            PersonalityState.fromJson(_lifeProfile!.personalityState);
        _worldview = Worldview.fromJson(_lifeProfile!.worldviewState);
        _identityNarrative =
            IdentityNarrative.fromJson(_lifeProfile!.identity);
        _maslowState = (_lifeProfile!.maslowState['layers'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
      } else {
        // 如果没有 LifeProfile，尝试单独加载各组件
        final psJson = storage.getString('personality_state_$charId');
        if (psJson != null) {
          _personalityState =
              PersonalityState.fromJson(jsonDecode(psJson));
        }
        final wvJson = storage.getString('worldview_$charId');
        if (wvJson != null) {
          _worldview = Worldview.fromJson(jsonDecode(wvJson));
        }
        final idJson = storage.getString('identity_narrative_$charId');
        if (idJson != null) {
          _identityNarrative =
              IdentityNarrative.fromJson(jsonDecode(idJson));
        }
        final geneJson = storage.getString('gene_profile_$charId');
        if (geneJson != null) {
          _geneProfile = GeneProfile.fromJson(jsonDecode(geneJson));
        }
        final msJson = storage.getString('maslow_state_$charId');
        if (msJson != null) {
          final decoded = jsonDecode(msJson);
          if (decoded is List) {
            _maslowState = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('CharacterSocialProfile: loadLifecycleData error — $e');
    }
  }

  // ─── 筛选后的社交动态 ───
  List<_SocialMemoryEntry> get _filteredSocialMemories {
    if (_socialFilter == '全部') return _socialMemories;
    return _socialMemories
        .where((m) => m.interactionType == _socialFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final char = widget.character;

    return Scaffold(
      appBar: AppBar(
        title: Text('${char.name}的社交档案'),
        centerTitle: true,
        elevation: 0,
        actions: [
          // 编辑外貌设定入口
          IconButton(
            icon: const Icon(Icons.face_outlined),
            tooltip: '外貌设定',
            onPressed: () => _openAppearanceEditor(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '关系网络'),
            Tab(text: '社交动态'),
            Tab(text: 'TA的朋友圈'),
            Tab(text: '互动记录'),
            Tab(text: '人格演化'),
            Tab(text: '生命档案'),
          ],
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRelationsTab(colorScheme),
                _buildSocialMemoriesTab(colorScheme),
                _buildMyMomentsTab(colorScheme),
                _buildInteractionsTab(colorScheme),
                _buildPersonalityEvolutionTab(colorScheme),
                _buildLifeProfileTab(colorScheme),
              ],
            ),
    );
  }

  /// 打开外貌设定编辑器
  void _openAppearanceEditor(BuildContext context) {
    final tagController = TextEditingController(
      text: widget.character.characterTag ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.face_outlined,
                    color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '外貌设定',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI 生图将基于此生成唯一的角色形象',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: tagController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '描述TA的外貌特征：发色、瞳色、脸型、体型、标志配饰、穿搭风格等',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '填写建议：银色长发、紫色瞳孔、瓜子脸、身材纤细、白色连衣裙、银制耳环',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final text = tagController.text.trim();
                  final updated = widget.character.copyWith(
                    characterTag: text.isEmpty ? null : text,
                    clearCharacterTag: text.isEmpty,
                    updatedAt: DateTime.now(),
                  );
                  final storage = RepositoryProvider.of<
                      LocalStorageRepository>(context,
                      listen: false);
                  await storage.saveAICharacter(updated);
                  Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {
                      // 刷新
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('外貌设定已保存'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('保存外貌设定'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // Tab 1: 关系网络（重写）
  // ═══════════════════════════════════════════════
  Widget _buildRelationsTab(ColorScheme colorScheme) {
    if (_relationships.isEmpty) {
      return _emptyState(
        Icons.people_outline,
        '还没有建立任何关系',
        '多创建几个角色，让他们互动起来吧',
      );
    }

    // 按亲密度排序
    final sorted = List<AIRelationship>.from(_relationships)
      ..sort((a, b) => b.affinity.compareTo(a.affinity));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final rel = sorted[index];
        final myId = widget.character.id;
        final otherId =
            rel.characterIdA == myId ? rel.characterIdB : rel.characterIdA;
        final otherChar =
            _allCharacters.where((c) => c.id == otherId).firstOrNull;

        // 计算信任度、熟悉度、紧张度（基于关系类型和亲密度推导）
        final trust = _calcTrust(rel);
        final familiarity = _calcFamiliarity(rel);
        final tension = _calcTension(rel);
        final relTags = _getRelationTags(rel);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 头部：头像 + 名字 + 关系类型 ──
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          colorScheme.primary.withOpacity(0.12),
                      child: Text(
                        otherChar?.name.isNotEmpty == true
                            ? otherChar!.name[0]
                            : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            otherChar?.name ?? '未知角色',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _tagChip(
                                _relLabel(rel.relationshipType),
                                _relColor(rel.relationshipType),
                              ),
                              if (tension > 0.6) ...[
                                const SizedBox(width: 6),
                                _tagChip('⚠ 紧张', Colors.red),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── 三维进度条：亲密度 / 信任度 / 熟悉度 ──
                _metricBar('亲密度', rel.affinity,
                    _relColor(rel.relationshipType), colorScheme),
                const SizedBox(height: 8),
                _metricBar(
                    '信任度', trust, Colors.blue.shade300, colorScheme),
                const SizedBox(height: 8),
                _metricBar(
                    '熟悉度', familiarity, Colors.amber.shade600, colorScheme),

                // ── 紧张度指示器 ──
                if (tension > 0.3) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14,
                          color: tension > 0.6
                              ? Colors.red
                              : Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '紧张度 ${(tension * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: tension > 0.6
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── 关系标签 ──
                if (relTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: relTags
                        .map((tag) => _tagChip(tag, colorScheme.secondary))
                        .toList(),
                  ),
                ],

                // ── 关系描述 / 最近互动摘要 ──
                if (rel.description != null &&
                    rel.description!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rel.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.7),
                        height: 1.4,
                      ),
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

  // ═══════════════════════════════════════════════
  // Tab 2: 社交动态（重写）
  // ═══════════════════════════════════════════════
  Widget _buildSocialMemoriesTab(ColorScheme colorScheme) {
    if (_socialMemories.isEmpty) {
      return _emptyState(
        Icons.dynamic_feed_outlined,
        '还没有社交动态',
        '角色互动后会在这里记录所有社交行为',
      );
    }

    final filtered = _filteredSocialMemories;
    final filterTypes = ['全部', '点赞', '评论', '串门', '吵架', '反思'];

    return Column(
      children: [
        // ── 筛选栏 ──
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: filterTypes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final type = filterTypes[index];
              final selected = _socialFilter == type;
              return FilterChip(
                label: Text(type, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => setState(() => _socialFilter = type),
                selectedColor: colorScheme.primary.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                side: BorderSide(
                  color: selected
                      ? colorScheme.primary.withOpacity(0.4)
                      : colorScheme.outlineVariant,
                ),
              );
            },
          ),
        ),

        // ── 动态列表 ──
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '没有「$_socialFilter」类型的动态',
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final mem = filtered[index];
                    return _socialMemoryCard(mem, colorScheme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _socialMemoryCard(
      _SocialMemoryEntry mem, ColorScheme colorScheme) {
    final iconData = _interactionTypeIcon(mem.interactionType);
    final iconColor = _interactionTypeColor(mem.interactionType);
    final targetChar = _allCharacters
        .where((c) => c.id == mem.targetCharacterId)
        .firstOrNull;
    final time = _formatTime(mem.timestamp);

    // 情感权重色块
    final emotionColor = _emotionColor(mem.emotionTag);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行为类型图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            // 内容区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间 + 关联角色
                  Row(
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (targetChar != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '→ ${targetChar.name}',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      // 情感权重色块
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: emotionColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 完整描述
                  Text(
                    mem.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                  // 情感标签
                  if (mem.emotionTag.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _tagChip(mem.emotionTag, emotionColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // Tab 3: TA 的朋友圈（优化版）
  // ═══════════════════════════════════════════════
  Widget _buildMyMomentsTab(ColorScheme colorScheme) {
    if (_myMoments.isEmpty) {
      return _emptyState(
        Icons.article_outlined,
        '还没有发过朋友圈',
        '角色发动态后会在这里展示',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myMoments.length,
      itemBuilder: (context, index) {
        final moment = _myMoments[index];
        return _momentCard(moment, colorScheme);
      },
    );
  }

  Widget _momentCard(Moment moment, ColorScheme colorScheme) {
    final time = _formatTime(moment.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 动态内容
            Text(
              moment.content,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            // 时间
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            // ── 收到的点赞详情 ──
            if (moment.likes.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.favorite, size: 14, color: Colors.red[300]),
                  const SizedBox(width: 6),
                  Text(
                    '${moment.likes.length} 人点赞',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 点赞者头像列表
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: moment.likes.map((like) {
                  final likerChar = _allCharacters
                      .where((c) => c.id == like.userId)
                      .firstOrNull;
                  return Tooltip(
                    message: like.userName,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          colorScheme.primary.withOpacity(0.1),
                      child: Text(
                        like.userName.isNotEmpty ? like.userName[0] : '?',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── 收到的评论详情 ──
            if (moment.comments.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.comment,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${moment.comments.length} 条评论',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...moment.comments.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              colorScheme.secondary.withOpacity(0.1),
                          child: Text(
                            c.userName.isNotEmpty ? c.userName[0] : '?',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.userName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c.content,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.85),
                                  height: 1.4,
                                ),
                              ),
                              Text(
                                _formatTime(c.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.6),
                                ),
                              ),
                            ],
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

  // ═══════════════════════════════════════════════
  // Tab 4: 互动记录（重写）
  // ═══════════════════════════════════════════════
  Widget _buildInteractionsTab(ColorScheme colorScheme) {
    if (_interactions.isEmpty) {
      return _emptyState(
        Icons.swap_horiz_outlined,
        '还没有互动记录',
        '角色点赞或评论其他角色的动态后会在这里展示',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _interactions.length,
      itemBuilder: (context, index) {
        final record = _interactions[index];
        return _interactionCard(record, colorScheme);
      },
    );
  }

  Widget _interactionCard(
      _InteractionRecord record, ColorScheme colorScheme) {
    final isLike = record.type == InteractionType.like;
    final time = _formatTime(record.time);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行为类型 + 目标作者 + 时间
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isLike
                        ? Colors.red.withOpacity(0.1)
                        : Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isLike ? Icons.favorite : Icons.comment,
                    size: 16,
                    color: isLike ? Colors.red : Colors.teal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 13, color: colorScheme.onSurface),
                      children: [
                        TextSpan(
                          text: isLike ? '点赞了 ' : '评论了 ',
                        ),
                        TextSpan(
                          text: record.targetName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        TextSpan(
                          text: ' 的动态',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 目标动态内容预览
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${record.targetContent}"',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 如果是评论，显示评论内容
            if (!isLike && record.myContent != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.reply, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      record.myContent!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // Tab 5: 人格演化（新增）
  // ═══════════════════════════════════════════════
  Widget _buildPersonalityEvolutionTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 五因子对比：当前值 vs 基因基线 ──
        _sectionTitle('人格五因子', Icons.psychology, colorScheme),
        const SizedBox(height: 10),
        _bigFiveComparisonCard(colorScheme),
        const SizedBox(height: 20),

        // ── 衍生特质 ──
        if (_personalityState != null) ...[
          _sectionTitle('衍生特质', Icons.auto_awesome, colorScheme),
          const SizedBox(height: 10),
          _derivedTraitsCard(colorScheme),
          const SizedBox(height: 20),
        ],

        // ── 三观标签 ──
        _sectionTitle('三观系统', Icons.visibility, colorScheme),
        const SizedBox(height: 10),
        _worldviewCard(colorScheme),
        const SizedBox(height: 20),

        // ── 身份认同 ──
        _sectionTitle('身份认同', Icons.badge_outlined, colorScheme),
        const SizedBox(height: 10),
        _identityCard(colorScheme),
        const SizedBox(height: 20),

        // ── 马斯洛需求状态 ──
        _sectionTitle('马斯洛需求', Icons.layers_outlined, colorScheme),
        const SizedBox(height: 10),
        _maslowCard(colorScheme),
        const SizedBox(height: 20),

        // ── 人格进化历史 ──
        _sectionTitle(
            '进化记录 (${_evolutionCount}次)', Icons.history, colorScheme),
        const SizedBox(height: 10),
        _evolutionHistoryCard(colorScheme),
        const SizedBox(height: 20),

        // ── 性格描述 ──
        if (_personalityState != null) ...[
          _sectionTitle('性格概述', Icons.summarize, colorScheme),
          const SizedBox(height: 10),
          _personalitySummaryCard(colorScheme),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  /// 五因子对比卡片：当前值 vs 基因基线
  Widget _bigFiveComparisonCard(ColorScheme colorScheme) {
    final factors = [
      ('开放性', _personalityState?.openness, _geneProfile?.openness),
      ('尽责性', _personalityState?.conscientiousness,
          _geneProfile?.conscientiousness),
      ('外向性', _personalityState?.extraversion, _geneProfile?.extraversion),
      ('宜人性', _personalityState?.agreeableness, _geneProfile?.agreeableness),
      ('神经质', _personalityState?.neuroticism, _geneProfile?.neuroticism),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: factors.map((f) {
            final label = f.$1;
            final current = f.$2;
            final baseline = f.$3;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            // 基因基线（灰色底层）
                            if (baseline != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: baseline,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHigh,
                                  minHeight: 10,
                                  valueColor: AlwaysStoppedAnimation(
                                    colorScheme.surfaceContainerHigh
                                        .withOpacity(0.8),
                                  ),
                                ),
                              ),
                            // 当前值（彩色上层）
                            if (current != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: current,
                                  backgroundColor: Colors.transparent,
                                  minHeight: 10,
                                  valueColor: AlwaysStoppedAnimation(
                                    _factorColor(label),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text(
                          current != null
                              ? '${(current * 100).toInt()}%'
                              : '--',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  // 基线标注
                  if (baseline != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 50, top: 2),
                      child: Text(
                        '基因基线: ${(baseline * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 9,
                          color:
                              colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
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

  /// 衍生特质卡片
  Widget _derivedTraitsCard(ColorScheme colorScheme) {
    final ps = _personalityState;
    if (ps == null) {
      return _noDataCard('人格数据尚未初始化', colorScheme);
    }

    final traits = [
      ('勇气', ps.courage, Icons.shield),
      ('共情', ps.empathy, Icons.favorite_outline),
      ('野心', ps.ambition, Icons.trending_up),
      ('创造力', ps.creativity, Icons.brush),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: traits.map((t) {
            return SizedBox(
              width: (MediaQuery.of(context).size.width - 80) / 2,
              child: Column(
                children: [
                  Icon(t.$3, size: 20, color: colorScheme.primary),
                  const SizedBox(height: 4),
                  Text(t.$1,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: t.$2,
                      backgroundColor: colorScheme.surfaceContainerHigh,
                      minHeight: 6,
                      valueColor:
                          AlwaysStoppedAnimation(colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(t.$2 * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
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

  /// 三观卡片
  Widget _worldviewCard(ColorScheme colorScheme) {
    final wv = _worldview;
    if (wv == null) {
      return _noDataCard('三观数据尚未初始化', colorScheme);
    }

    final dimensions = [
      ('个人主义 ↔ 集体主义', wv.individualismVsCollectivism,
          '个人自由', '集体归属'),
      ('理想主义 ↔ 实用主义', wv.idealismVsPragmatism,
          '理想', '务实'),
      ('信任 ↔ 怀疑', wv.trustVsSuspicion, '信任', '怀疑'),
      ('享乐 ↔ 禁欲', wv.hedonismVsAsceticism, '享乐', '禁欲'),
      ('虚无 ↔ 意义', wv.nihilismVsMeaning, '虚无', '意义'),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 世界观标签
            if (wv.beliefs.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: wv.beliefs
                    .map((b) => _tagChip(b, colorScheme.tertiary))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            // 五维光谱
            ...dimensions.map((d) {
              final label = d.$1;
              final value = d.$2;
              final leftLabel = d.$3;
              final rightLabel = d.$4;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(leftLabel,
                            style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurfaceVariant)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor:
                                  colorScheme.surfaceContainerHigh,
                              thumbColor: colorScheme.primary,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                            ),
                            child: Slider(
                              value: value,
                              onChanged: null, // 只读
                            ),
                          ),
                        ),
                        Text(rightLabel,
                            style: TextStyle(
                                fontSize: 9,
                                color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              );
            }),

            // 固化程度
            const SizedBox(height: 4),
            Row(
              children: [
                Text('三观固化度',
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: wv.crystallization,
                      backgroundColor: colorScheme.surfaceContainerHigh,
                      minHeight: 4,
                      valueColor: AlwaysStoppedAnimation(
                        wv.crystallization > 0.7
                            ? Colors.orange
                            : colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(wv.crystallization * 100).toInt()}%',
                  style: TextStyle(
                      fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 身份认同卡片
  Widget _identityCard(ColorScheme colorScheme) {
    final id = _identityNarrative;
    if (id == null ||
        (id.selfDescription.isEmpty && id.coreMotivation.isEmpty)) {
      return _noDataCard('身份认同尚未形成', colorScheme);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (id.selfDescription.isNotEmpty) ...[
              _identityRow('自我描述', id.selfDescription, colorScheme),
              const SizedBox(height: 10),
            ],
            if (id.coreMotivation.isNotEmpty) ...[
              _identityRow('核心动机', id.coreMotivation, colorScheme),
              const SizedBox(height: 10),
            ],
            if (id.biggestFear.isNotEmpty) ...[
              _identityRow('最大恐惧', id.biggestFear, colorScheme),
              const SizedBox(height: 10),
            ],
            if (id.lifePhilosophy.isNotEmpty) ...[
              _identityRow('人生哲学', id.lifePhilosophy, colorScheme),
            ],
            // 身份标签
            if (id.identityTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: id.identityTags
                    .map((t) => _tagChip(t, colorScheme.primary))
                    .toList(),
              ),
            ],
            // 内在矛盾
            if (id.innerConflicts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '内在矛盾',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ...id.innerConflicts.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 12,
                            color: Colors.orange.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            c,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withOpacity(0.7),
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

  Widget _identityRow(
      String label, String value, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// 马斯洛需求卡片
  Widget _maslowCard(ColorScheme colorScheme) {
    if (_maslowState.isEmpty) {
      // 使用默认六层
      return _maslowDefaultCard(colorScheme);
    }

    final layers = [
      ('自我超越', Icons.cloud, Colors.indigo),
      ('自我实现', Icons.star, Colors.purple),
      ('尊重需求', Icons.emoji_events, Colors.amber),
      ('归属与爱', Icons.favorite, Colors.pink),
      ('安全需求', Icons.shield, Colors.blue),
      ('生理需求', Icons.restaurant, Colors.green),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(layers.length, (i) {
            final layer = layers[i];
            final data = i < _maslowState.length ? _maslowState[i] : null;
            final satisfaction =
                (data?['satisfaction'] as num?)?.toDouble() ?? 0.5;
            final urgency =
                (data?['urgency'] as num?)?.toDouble() ?? 0.3;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(layer.$2, size: 18, color: layer.$3),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 60,
                    child: Text(
                      layer.$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: satisfaction,
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        minHeight: 8,
                        valueColor: AlwaysStoppedAnimation(layer.$3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(satisfaction * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
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

  /// 默认马斯洛卡片（无数据时）
  Widget _maslowDefaultCard(ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _maslowLayerRow('生理需求', 0.7, Colors.green, colorScheme),
            _maslowLayerRow('安全需求', 0.6, Colors.blue, colorScheme),
            _maslowLayerRow('归属与爱', 0.5, Colors.pink, colorScheme),
            _maslowLayerRow('尊重需求', 0.4, Colors.amber, colorScheme),
            _maslowLayerRow('自我实现', 0.3, Colors.purple, colorScheme),
            _maslowLayerRow('自我超越', 0.1, Colors.indigo, colorScheme),
            const SizedBox(height: 8),
            Text(
              '提示：马斯洛需求数据将在生命系统初始化后生成',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _maslowLayerRow(
      String label, double value, Color color, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: colorScheme.surfaceContainerHigh,
                minHeight: 8,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).toInt()}%',
            style:
                TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 进化历史卡片
  Widget _evolutionHistoryCard(ColorScheme colorScheme) {
    if (_evolutionLogs.isEmpty) {
      return _noDataCard('还没有进化记录', colorScheme);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _evolutionLogs.take(10).map((log) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.changes,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                        Text(
                          _formatTime(log.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant
                                .withOpacity(0.6),
                          ),
                        ),
                      ],
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

  /// 性格概述卡片
  Widget _personalitySummaryCard(ColorScheme colorScheme) {
    final ps = _personalityState;
    if (ps == null) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ps.summary,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
            // 性格标记
            if (ps.traits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ps.traits
                    .map((t) => _tagChip(t, colorScheme.tertiary))
                    .toList(),
              ),
            ],
            // 情绪基调
            const SizedBox(height: 10),
            Row(
              children: [
                Text('情绪基调',
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(
                  ps.emotionalBaseline > 0.1
                      ? Icons.sentiment_satisfied
                      : ps.emotionalBaseline < -0.1
                          ? Icons.sentiment_dissatisfied
                          : Icons.sentiment_neutral,
                  size: 18,
                  color: ps.emotionalBaseline > 0.1
                      ? Colors.green
                      : ps.emotionalBaseline < -0.1
                          ? Colors.red
                          : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  ps.emotionalBaseline > 0.1
                      ? '乐观'
                      : ps.emotionalBaseline < -0.1
                          ? '悲观'
                          : '中性',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // Tab 6: 生命档案（新增）
  // ═══════════════════════════════════════════════
  Widget _buildLifeProfileTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 基因信息 ──
        _sectionTitle('基因档案', Icons.biotech, colorScheme),
        const SizedBox(height: 10),
        _geneProfileCard(colorScheme),
        const SizedBox(height: 20),

        // ── 原生家庭 ──
        _sectionTitle('原生家庭', Icons.home_outlined, colorScheme),
        const SizedBox(height: 10),
        _familyBackgroundCard(colorScheme),
        const SizedBox(height: 20),

        // ── 童年烙印事件 ──
        _sectionTitle('童年烙印', Icons.child_care, colorScheme),
        const SizedBox(height: 10),
        _childhoodImprintCard(colorScheme),
        const SizedBox(height: 20),

        // ── 生命阶段 + 生命状态 ──
        _sectionTitle('生命状态', Icons.timeline, colorScheme),
        const SizedBox(height: 10),
        _lifeStageCard(colorScheme),
        const SizedBox(height: 20),

        // ── 能力解锁状态 ──
        _sectionTitle('能力解锁', Icons.lock_open, colorScheme),
        const SizedBox(height: 10),
        _capabilityUnlockCard(colorScheme),
        const SizedBox(height: 20),

        // ── 潜在特质 ──
        if (_geneProfile?.latentTraits.isNotEmpty == true) ...[
          _sectionTitle('潜在特质', Icons.bolt, colorScheme),
          const SizedBox(height: 10),
          _latentTraitsCard(colorScheme),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  /// 基因档案卡片
  Widget _geneProfileCard(ColorScheme colorScheme) {
    final genes = _geneProfile;
    if (genes == null) {
      return _noDataCard('基因数据尚未初始化', colorScheme);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 天赋
            Text('天赋',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            if (genes.talents.isEmpty)
              Text('暂无天赋数据',
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: genes.talents.entries.map((e) {
                  return Chip(
                    avatar: Icon(Icons.star,
                        size: 14, color: Colors.amber.shade700),
                    label: Text(
                      '${e.key} ${(e.value * 100).toInt()}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),

            // 体质三维度
            Text('体质',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            _metricBar('生命力', genes.vitality, Colors.green, colorScheme),
            const SizedBox(height: 6),
            _metricBar('韧性', genes.resilience, Colors.blue, colorScheme),
            const SizedBox(height: 6),
            _metricBar(
                '敏感度', genes.sensitivity, Colors.purple, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 原生家庭卡片
  Widget _familyBackgroundCard(ColorScheme colorScheme) {
    final family = _geneProfile?.family;
    if (family == null || family.description.isEmpty) {
      return _noDataCard('原生家庭数据尚未初始化', colorScheme);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              family.description,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _metricBar('经济水平', family.wealth, Colors.amber, colorScheme),
            const SizedBox(height: 6),
            _metricBar('家庭温暖', family.warmth, Colors.orange, colorScheme),
            const SizedBox(height: 6),
            _metricBar(
                '管教严格', family.strictness, Colors.blueGrey, colorScheme),
            // 家庭事件
            if (family.familyEvents.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('家庭事件',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              ...family.familyEvents.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle,
                            size: 5,
                            color:
                                colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    colorScheme.onSurface.withOpacity(0.8)),
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

  /// 童年烙印卡片
  Widget _childhoodImprintCard(ColorScheme colorScheme) {
    final lifeEvents = _lifeProfile?.lifeEvents ?? [];
    final imprintEvents = lifeEvents
        .where((e) =>
            (e['stage'] as String?) == 'infant' ||
            (e['stage'] as String?) == 'toddler' ||
            (e['stage'] as String?) == 'childhood' ||
            (e['type'] as String?) == 'imprint')
        .toList();

    if (imprintEvents.isEmpty) {
      return _noDataCard('暂无童年烙印事件', colorScheme);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: imprintEvents.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_stories,
                      size: 16, color: colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e['description'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                        Text(
                          _formatTime(e['timestamp']),
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant
                                .withOpacity(0.6),
                          ),
                        ),
                      ],
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

  /// 生命阶段卡片
  Widget _lifeStageCard(ColorScheme colorScheme) {
    final lp = _lifeProfile;
    final stage = lp?.currentStage;
    final state = lp?.lifeState;
    final bioAge = lp?.biologicalAge ?? 0;
    final mentalAge = lp?.mentalAge ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _tagChip(
                  _lifeStageLabel(stage),
                  _lifeStageColor(stage),
                ),
                const SizedBox(width: 8),
                _tagChip(
                  _lifeStateLabel(state),
                  _lifeStateColor(state),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _infoTile('生理年龄', '$bioAge 岁', colorScheme),
                const SizedBox(width: 20),
                _infoTile('心理年龄', '$mentalAge 岁', colorScheme),
              ],
            ),
            if (lp?.birthTime != null) ...[
              const SizedBox(height: 8),
              Text(
                '出生时间: ${lp!.birthTime.toString().substring(0, 19)}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (lp == null) ...[
              const SizedBox(height: 8),
              Text(
                '提示：生命档案数据将在角色出生系统初始化后生成',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface)),
      ],
    );
  }

  /// 能力解锁卡片
  Widget _capabilityUnlockCard(ColorScheme colorScheme) {
    // 基于生命阶段确定能力解锁
    final stage = _lifeProfile?.currentStage;
    final capabilities = _getCapabilitiesForStage(stage);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: capabilities.map((cap) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    cap.$2 ? Icons.check_circle : Icons.lock,
                    size: 18,
                    color: cap.$2 ? Colors.green : colorScheme.onSurfaceVariant.withOpacity(0.3),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    cap.$1,
                    style: TextStyle(
                      fontSize: 13,
                      color: cap.$2
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withOpacity(0.4),
                      fontWeight: cap.$2 ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  if (cap.$2)
                    Text('已解锁',
                        style: TextStyle(
                            fontSize: 11, color: Colors.green.shade600))
                  else
                    Text('未解锁',
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant
                                .withOpacity(0.4))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 潜在特质卡片
  Widget _latentTraitsCard(ColorScheme colorScheme) {
    final traits = _geneProfile?.latentTraits ?? [];
    if (traits.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: traits.map((t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        t.isActivated ? Icons.bolt : Icons.bolt_outlined,
                        size: 16,
                        color: t.isActivated
                            ? Colors.amber
                            : colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.isActivated
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const Spacer(),
                      if (t.isActivated)
                        _tagChip('已激活', Colors.green)
                      else
                        Text(
                          '触发概率 ${(t.triggerProbability * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.7),
                      height: 1.4,
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

  // ═══════════════════════════════════════════════
  // 通用组件
  // ═══════════════════════════════════════════════

  Widget _sectionTitle(String title, IconData icon, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _metricBar(
      String label, double value, Color color, ColorScheme colorScheme) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: colorScheme.surfaceContainerHigh,
              minHeight: 6,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(value * 100).toInt()}%',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _tagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _noDataCard(String message, ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.info_outline,
                  size: 28,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3)),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 52,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.25)),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.6))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════

  /// 计算信任度
  double _calcTrust(AIRelationship rel) {
    switch (rel.relationshipType) {
      case RelationshipType.bestFriend:
      case RelationshipType.lover:
        return (rel.affinity * 0.9).clamp(0.0, 1.0);
      case RelationshipType.friend:
      case RelationshipType.sibling:
        return (rel.affinity * 0.75).clamp(0.0, 1.0);
      case RelationshipType.mentor:
        return (rel.affinity * 0.7).clamp(0.0, 1.0);
      case RelationshipType.crush:
        return (rel.affinity * 0.5).clamp(0.0, 1.0);
      case RelationshipType.rival:
        return (rel.affinity * 0.3).clamp(0.0, 1.0);
      case RelationshipType.enemy:
        return (rel.affinity * 0.1).clamp(0.0, 1.0);
      case RelationshipType.stranger:
        return 0.1;
    }
  }

  /// 计算熟悉度
  double _calcFamiliarity(AIRelationship rel) {
    // 熟悉度基于关系存在时间和亲密度
    final days = DateTime.now().difference(rel.createdAt).inDays;
    final timeFactor = (days / 30).clamp(0.0, 1.0); // 30天达到满值
    return (rel.affinity * 0.6 + timeFactor * 0.4).clamp(0.0, 1.0);
  }

  /// 计算紧张度
  double _calcTension(AIRelationship rel) {
    switch (rel.relationshipType) {
      case RelationshipType.enemy:
        return (0.7 + (1 - rel.affinity) * 0.3).clamp(0.0, 1.0);
      case RelationshipType.rival:
        return (0.4 + (1 - rel.affinity) * 0.3).clamp(0.0, 1.0);
      case RelationshipType.crush:
        return (0.2 + rel.affinity * 0.2).clamp(0.0, 1.0);
      default:
        return ((1 - rel.affinity) * 0.2).clamp(0.0, 1.0);
    }
  }

  /// 获取关系标签
  List<String> _getRelationTags(AIRelationship rel) {
    final tags = <String>[];
    if (rel.affinity >= 0.8) tags.add('亲密');
    if (rel.affinity <= 0.2) tags.add('疏远');
    if (rel.relationshipType == RelationshipType.lover) tags.add('恋人');
    if (rel.relationshipType == RelationshipType.bestFriend) tags.add('挚友');
    if (rel.description != null && rel.description!.isNotEmpty) {
      // 尝试从描述中提取关键词作为标签
      final desc = rel.description!;
      if (desc.contains('青梅竹马')) tags.add('青梅竹马');
      if (desc.contains('背叛')) tags.add('曾经背叛');
      if (desc.contains('师徒')) tags.add('师徒');
    }
    return tags;
  }

  String _relLabel(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return '朋友';
      case RelationshipType.bestFriend:
        return '挚友';
      case RelationshipType.crush:
        return '暗恋';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.enemy:
        return '敌人';
      case RelationshipType.sibling:
        return '兄妹';
      case RelationshipType.mentor:
        return '导师';
      case RelationshipType.stranger:
        return '陌生人';
    }
  }

  Color _relColor(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return Colors.green;
      case RelationshipType.bestFriend:
        return Colors.teal;
      case RelationshipType.crush:
        return Colors.pink;
      case RelationshipType.lover:
        return Colors.red;
      case RelationshipType.rival:
        return Colors.orange;
      case RelationshipType.enemy:
        return Colors.grey;
      case RelationshipType.sibling:
        return Colors.purple;
      case RelationshipType.mentor:
        return Colors.blue;
      case RelationshipType.stranger:
        return Colors.grey;
    }
  }

  IconData _interactionTypeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'visit':
        return Icons.door_front_door;
      case 'befriend':
        return Icons.person_add;
      case 'argue':
        return Icons.warning;
      case 'reflect':
        return Icons.auto_stories;
      case 'chat':
        return Icons.chat;
      case 'post':
        return Icons.post_add;
      default:
        return Icons.circle;
    }
  }

  Color _interactionTypeColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return Colors.teal;
      case 'visit':
        return Colors.blue;
      case 'befriend':
        return Colors.pink;
      case 'argue':
        return Colors.orange;
      case 'reflect':
        return Colors.indigo;
      case 'chat':
        return Colors.purple;
      case 'post':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Color _emotionColor(String emotionTag) {
    if (emotionTag.isEmpty) return Colors.grey;
    final tag = emotionTag.toLowerCase();
    if (tag.contains('开心') || tag.contains('快乐') || tag.contains('joy')) {
      return Colors.amber;
    }
    if (tag.contains('悲伤') || tag.contains('难过') || tag.contains('sad')) {
      return Colors.blue;
    }
    if (tag.contains('愤怒') || tag.contains('生气') || tag.contains('angry')) {
      return Colors.red;
    }
    if (tag.contains('恐惧') || tag.contains('害怕') || tag.contains('fear')) {
      return Colors.deepPurple;
    }
    if (tag.contains('惊讶') || tag.contains('surprise')) {
      return Colors.orange;
    }
    if (tag.contains('爱') || tag.contains('喜欢') || tag.contains('love')) {
      return Colors.pink;
    }
    if (tag.contains('平静') || tag.contains('calm')) {
      return Colors.green;
    }
    return Theme.of(context).colorScheme.primary;
  }

  Color _factorColor(String label) {
    switch (label) {
      case '开放性':
        return Colors.blue;
      case '尽责性':
        return Colors.green;
      case '外向性':
        return Colors.orange;
      case '宜人性':
        return Colors.pink;
      case '神经质':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _lifeStageLabel(LifeStage? stage) {
    if (stage == null) return '未知阶段';
    switch (stage) {
      case LifeStage.infant:
        return '婴儿期';
      case LifeStage.toddler:
        return '幼儿期';
      case LifeStage.childhood:
        return '童年期';
      case LifeStage.teenage:
        return '青春期';
      case LifeStage.youngAdult:
        return '青年期';
      case LifeStage.adult:
        return '中年期';
      case LifeStage.senior:
        return '老年期';
      case LifeStage.elder:
        return '暮年';
    }
  }

  Color _lifeStageColor(LifeStage? stage) {
    if (stage == null) return Colors.grey;
    switch (stage) {
      case LifeStage.infant:
        return Colors.pink.shade200;
      case LifeStage.toddler:
        return Colors.pink;
      case LifeStage.childhood:
        return Colors.green;
      case LifeStage.teenage:
        return Colors.blue;
      case LifeStage.youngAdult:
        return Colors.orange;
      case LifeStage.adult:
        return Colors.teal;
      case LifeStage.senior:
        return Colors.purple;
      case LifeStage.elder:
        return Colors.indigo;
    }
  }

  String _lifeStateLabel(LifeState? state) {
    if (state == null) return '未知';
    switch (state) {
      case LifeState.alive:
        return '存活';
      case LifeState.aging:
        return '衰老中';
      case LifeState.deceased:
        return '已故';
      case LifeState.immortal:
        return '数字永生';
    }
  }

  Color _lifeStateColor(LifeState? state) {
    if (state == null) return Colors.grey;
    switch (state) {
      case LifeState.alive:
        return Colors.green;
      case LifeState.aging:
        return Colors.orange;
      case LifeState.deceased:
        return Colors.grey;
      case LifeState.immortal:
        return Colors.amber;
    }
  }

  List<(String, bool)> _getCapabilitiesForStage(LifeStage? stage) {
    if (stage == null) {
      return [
        ('语言表达', false),
        ('主动社交', false),
        ('发朋友圈', false),
        ('建立关系', false),
        ('形成三观', false),
        ('完整记忆', false),
      ];
    }
    switch (stage) {
      case LifeStage.infant:
        return [
          ('语言表达', false),
          ('主动社交', false),
          ('发朋友圈', false),
          ('建立关系', false),
          ('形成三观', false),
          ('完整记忆', false),
        ];
      case LifeStage.toddler:
        return [
          ('语言表达', false),
          ('主动社交', false),
          ('发朋友圈', false),
          ('建立关系', true),
          ('形成三观', false),
          ('完整记忆', false),
        ];
      case LifeStage.childhood:
        return [
          ('语言表达', true),
          ('主动社交', true),
          ('发朋友圈', false),
          ('建立关系', true),
          ('形成三观', false),
          ('完整记忆', true),
        ];
      default:
        return [
          ('语言表达', true),
          ('主动社交', true),
          ('发朋友圈', true),
          ('建立关系', true),
          ('形成三观', true),
          ('完整记忆', true),
        ];
    }
  }

  String _formatTime(dynamic dt) {
    if (dt == null) return '';
    DateTime time;
    if (dt is DateTime) {
      time = dt;
    } else if (dt is String) {
      time = DateTime.tryParse(dt) ?? DateTime.now();
    } else {
      time = DateTime.tryParse(dt.toString()) ?? DateTime.now();
    }
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${(diff.inDays / 7).toInt()}周前';
    return '${(diff.inDays / 30).toInt()}月前';
  }
}
