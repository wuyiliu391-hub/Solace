import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_relationship_service.dart';
import '../../services/memory_engine.dart';
import '../../models/ai_character.dart';

/// 社交关系二级页面
///
/// 展示：好友关系网络、好友申请记录、角色间聊天记录
class SocialRelationsPage extends StatefulWidget {
  final String? initialCharacterId; // 可选：指定角色，只显示该角色的关系

  const SocialRelationsPage({super.key, this.initialCharacterId});

  @override
  State<SocialRelationsPage> createState() => _SocialRelationsPageState();
}

class _SocialRelationsPageState extends State<SocialRelationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AICharacter> _characters = [];
  List<AIRelationship> _allRelationships = [];
  List<dynamic> _socialMemories = []; // 社交记忆列表
  String? _selectedCharId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedCharId = widget.initialCharacterId;
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

      // 加载所有角色
      _characters = await storage.getAllAICharacters();

      // 加载关系
      if (_selectedCharId != null) {
        _allRelationships =
            await relService.getRelationships(_selectedCharId!);
      } else {
        // 加载所有关系（遍历角色）
        final allRels = <AIRelationship>[];
        final seen = <String>{};
        for (final char in _characters) {
          final rels = await relService.getRelationships(char.id);
          for (final rel in rels) {
            if (!seen.contains(rel.id)) {
              seen.add(rel.id);
              allRels.add(rel);
            }
          }
        }
        _allRelationships = allRels;
      }

      // 加载社交记忆
      if (_selectedCharId != null) {
        _socialMemories =
            await memoryEngine.loadSocialMemories(_selectedCharId!);
      } else {
        // 汇总所有角色的社交记忆
        final allMems = <dynamic>[];
        final seenMem = <String>{};
        for (final char in _characters) {
          try {
            final mems = await memoryEngine.loadSocialMemories(char.id);
            for (final m in mems) {
              final key = '${m.createdAt}_${m.content}';
              if (!seenMem.contains(key)) {
                seenMem.add(key);
                allMems.add(m);
              }
            }
          } catch (_) {}
        }
        // 按时间排序
        allMems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _socialMemories = allMems.take(100).toList();
      }
    } catch (e) {
      debugPrint('SocialRelations: load error — $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCharId != null ? '角色社交关系' : '社交网络'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '关系网络'),
            Tab(text: '好友申请'),
            Tab(text: '社交动态'),
          ],
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 角色筛选条
                if (_selectedCharId == null && _characters.isNotEmpty)
                  _buildCharacterFilter(colorScheme),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRelationsTab(colorScheme),
                      _buildFriendRequestsTab(colorScheme),
                      _buildSocialMemoriesTab(colorScheme),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ─── 角色筛选条 ───
  Widget _buildCharacterFilter(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(null, '全部', colorScheme),
            const SizedBox(width: 6),
            ..._characters.map((c) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildFilterChip(c.id, c.name, colorScheme),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String? charId, String label, ColorScheme colorScheme) {
    final selected = _selectedCharId == charId;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCharId = charId);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withOpacity(0.15)
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withOpacity(0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ─── Tab 1: 关系网络 ───
  Widget _buildRelationsTab(ColorScheme colorScheme) {
    if (_allRelationships.isEmpty) {
      return Center(
        child: Text(
          '暂无角色关系',
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allRelationships.length,
      itemBuilder: (context, index) {
        final rel = _allRelationships[index];
        final charA =
            _characters.where((c) => c.id == rel.characterIdA).firstOrNull;
        final charB =
            _characters.where((c) => c.id == rel.characterIdB).firstOrNull;
        final label = _relLabel(rel.relationshipType);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 关系对
                Row(
                  children: [
                    _charAvatar(charA, colorScheme),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.favorite,
                          size: 16, color: Colors.pink),
                    ),
                    _charAvatar(charB, colorScheme),
                  ],
                ),
                const SizedBox(height: 12),
                // 关系类型 + 亲密度
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _relColor(rel.relationshipType)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _relColor(rel.relationshipType),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '亲密度 ${(rel.affinity * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (rel.description != null &&
                    rel.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    rel.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.7),
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

  Widget _charAvatar(AICharacter? char, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primary.withOpacity(0.15),
          child: Text(
            char?.name.isNotEmpty == true ? char!.name[0] : '?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          char?.name ?? '未知角色',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
        ),
      ],
    );
  }

  // ─── Tab 2: 好友申请 ───
  Widget _buildFriendRequestsTab(ColorScheme colorScheme) {
    // 从社交记忆中提取好友申请记录
    final friendRequests = _socialMemories.where((m) {
      final content = m.content is String ? m.content as String : '';
      return content.contains('好友') ||
          content.contains('friend') ||
          content.contains('friend_request');
    }).toList();

    if (friendRequests.isEmpty) {
      return Center(
        child: Text(
          '暂无好友申请记录',
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: friendRequests.length,
      itemBuilder: (context, index) {
        final mem = friendRequests[index];
        final content = mem.content ?? '';
        final isAccepted =
            content.contains('成为了好友') || content.contains('are now friends');
        final isPending =
            content.contains('申请') || content.contains('request');
        final isExisting = content.contains('已经是好友');

        IconData icon;
        Color iconColor;
        String status;

        if (isAccepted) {
          icon = Icons.check_circle;
          iconColor = Colors.green;
          status = '已接受';
        } else if (isExisting) {
          icon = Icons.link;
          iconColor = Colors.blue;
          status = '已是好友';
        } else if (isPending) {
          icon = Icons.schedule;
          iconColor = Colors.orange;
          status = '申请中';
        } else {
          icon = Icons.info;
          iconColor = Colors.grey;
          status = '记录';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Icon(icon, color: iconColor, size: 22),
            title: Text(
              content.length > 60
                  ? '${content.substring(0, 60)}...'
                  : content,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              _formatTime(mem.createdAt),
              style: TextStyle(
                  fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
            trailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Tab 3: 社交动态 (聊天记录) ───
  Widget _buildSocialMemoriesTab(ColorScheme colorScheme) {
    if (_socialMemories.isEmpty) {
      return Center(
        child: Text(
          '暂无社交动态',
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _socialMemories.length,
      itemBuilder: (context, index) {
        final mem = _socialMemories[index];
        final content = mem.content ?? '';
        final time = _formatTime(mem.createdAt);

        // 识别互动类型
        IconData icon;
        Color iconColor;
        if (content.contains('串门') || content.contains('visit')) {
          icon = Icons.door_front_door;
          iconColor = Colors.blue;
        } else if (content.contains('私聊') ||
            content.contains('说:')) {
          icon = Icons.chat;
          iconColor = Colors.purple;
        } else if (content.contains('好友') ||
            content.contains('friend')) {
          icon = Icons.person_add;
          iconColor = Colors.pink;
        } else if (content.contains('动态') ||
            content.contains('发了一条')) {
          icon = Icons.post_add;
          iconColor = Colors.amber;
        } else if (content.contains('评论')) {
          icon = Icons.comment;
          iconColor = Colors.teal;
        } else if (content.contains('点赞')) {
          icon = Icons.thumb_up;
          iconColor = Colors.red;
        } else {
          icon = Icons.circle;
          iconColor = Colors.grey;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: iconColor.withOpacity(0.15),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            title: Text(
              content.length > 80
                  ? '${content.substring(0, 80)}...'
                  : content,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              time,
              style: TextStyle(
                  fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ),
        );
      },
    );
  }

  // ─── 工具方法 ───

  String _relLabel(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return '朋友';
      case RelationshipType.bestFriend:
        return '好友';
      case RelationshipType.crush:
        return '暗恋';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.enemy:
        return '敌人';
      case RelationshipType.sibling:
        return '兄弟姐妹';
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

  String _formatTime(dynamic dt) {
    if (dt == null) return '';
    DateTime time;
    if (dt is DateTime) {
      time = dt;
    } else {
      time = DateTime.tryParse(dt.toString()) ?? DateTime.now();
    }
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}
