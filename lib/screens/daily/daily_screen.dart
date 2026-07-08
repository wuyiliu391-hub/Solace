import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/emotion_engine.dart';
import '../../utils/avatar_resolver.dart';

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // ── 任务状态 ──
  bool _morningDone = false;
  bool _chatDone = false;
  bool _momentDone = false;
  bool _nightDone = false;

  // ── 今日数据 ──
  int _todayMsgCount = 0;
  int _todayIntimacyDelta = 0;

  // ── AI 角色情绪 ──
  AICharacter? _primaryCharacter;
  CharacterEmotion? _emotion;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    // 并行加载所有数据
    final results = await Future.wait([
      storage.getTodayUserMessageCount(),
      storage.hasSentMorningMessage(),
      storage.hasSentNightMessage(),
      storage.getTodayIntimacyDelta(),
      storage.hasPostedMomentToday(),
      storage.getAllAICharacters(),
    ]);

    final msgCount = results[0] as int;
    final morning = results[1] as bool;
    final night = results[2] as bool;
    final delta = results[3] as int;
    final posted = results[4] as bool;
    final characters = results[5] as List<AICharacter>;

    AICharacter? primary;
    CharacterEmotion? emotion;
    if (characters.isNotEmpty) {
      primary = characters.first;
      final engine = EmotionEngine(storage);
      emotion = await engine.getCurrentEmotion(
        character: primary,
        userId: userId,
      );
    }

    if (!mounted) return;
    setState(() {
      _todayMsgCount = msgCount;
      _morningDone = morning;
      _nightDone = night;
      _todayIntimacyDelta = delta;
      _momentDone = posted;
      _chatDone = msgCount > 0;
      _primaryCharacter = primary;
      _emotion = emotion;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(cs),
            _buildTabBar(cs),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDailyView(cs),
                  _buildLocationView(cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(color: cs.surface),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.wb_sunny_rounded, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('日常',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                Text('实时了解TA的动态',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          _buildLiveIndicator(),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
          SizedBox(width: 6),
          Text('实时',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: '每日动态'),
          Tab(text: '虚拟位置'),
        ],
      ),
    );
  }

  // ── 今日概览卡片 ──
  Widget _buildSummaryCard(ColorScheme cs) {
    final emotionLabel = _emotion?.effectiveEmotion.label ?? '平静';
    final emotionIcon = _emotion?.effectiveEmotion.icon ?? Icons.sentiment_satisfied;
    final emotionColor = _emotion?.effectiveEmotion.color ?? const Color(0xFF90CAF9);
    final characterName = _primaryCharacter?.name ?? 'AI';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.tertiary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: cs.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // AI 头像
              if (_primaryCharacter != null)
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: (_primaryCharacter!.avatarUrl ?? '').isNotEmpty
                        ? (AvatarResolver.imageWidget(
                            _primaryCharacter!.avatarUrl,
                            fit: BoxFit.cover,
                            onError: () => _defaultAvatar(cs)) ??
                            _defaultAvatar(cs))
                        : _defaultAvatar(cs),
                  ),
                )
              else
                _defaultAvatar(cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$characterName 今天$emotionLabel',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimary),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(emotionIcon, size: 14, color: emotionColor),
                        const SizedBox(width: 4),
                        Text(
                          _getEmotionDesc(emotionLabel),
                          style: TextStyle(
                              fontSize: 13, color: cs.onPrimary.withOpacity(0.8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 数据行
          Row(
            children: [
              _buildStatItem(cs, '$_todayMsgCount', '消息'),
              Container(
                  width: 1, height: 28, color: cs.onPrimary.withOpacity(0.2)),
              _buildStatItem(
                  cs,
                  _todayIntimacyDelta >= 0
                      ? '+$_todayIntimacyDelta'
                      : '$_todayIntimacyDelta',
                  '亲密度'),
              Container(
                  width: 1, height: 28, color: cs.onPrimary.withOpacity(0.2)),
              _buildStatItem(cs, '${_completedCount()}/4', '已完成'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar(ColorScheme cs) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.onPrimary.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, color: cs.onPrimary, size: 22),
    );
  }

  Widget _buildStatItem(ColorScheme cs, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: cs.onPrimary.withOpacity(0.7))),
        ],
      ),
    );
  }

  int _completedCount() {
    int count = 0;
    if (_morningDone) count++;
    if (_chatDone) count++;
    if (_momentDone) count++;
    if (_nightDone) count++;
    return count;
  }

  String _getEmotionDesc(String label) {
    switch (label) {
      case '开心':
        return '今天和你聊天很开心';
      case '兴奋':
        return '对今天的互动充满期待';
      case '平静':
        return '心情不错，在等你来聊天';
      case '担忧':
        return '有点担心你，快来聊聊吧';
      case '难过':
        return '想你了，快来安慰一下';
      case '生气':
        return '哼，怎么还不来找我';
      case '害羞':
        return '想到你就会脸红...';
      case '感动':
        return '你的话让TA很温暖';
      case '想你':
        return '一直在等你的消息';
      case '焦虑':
        return '你是不是忘记我了';
      case '困了':
        return '有点困，但还在等你';
      case '调皮':
        return '今天心情很好，想找你玩';
      default:
        return '在等你来聊天';
    }
  }

  // ── 每日任务列表 ──
  Widget _buildDailyView(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildSummaryCard(cs),
        _buildTaskCard(
          cs,
          icon: Icons.favorite_border,
          title: '说早安',
          desc: _morningDone ? '今天已经说过早安了' : '10点前向TA发送早安问候',
          color: const Color(0xFFEC4899),
          done: _morningDone,
        ),
        _buildTaskCard(
          cs,
          icon: Icons.chat_bubble_outline,
          title: '聊聊天',
          desc: _chatDone ? '今天已聊 $_todayMsgCount 条消息' : '今天还没聊过天哦',
          color: const Color(0xFF3B82F6),
          done: _chatDone,
        ),
        _buildTaskCard(
          cs,
          icon: Icons.photo_camera_outlined,
          title: '分享日常',
          desc: _momentDone ? '今天已经分享了动态' : '拍张照片分享给TA',
          color: const Color(0xFF06B6D4),
          done: _momentDone,
        ),
        _buildTaskCard(
          cs,
          icon: Icons.nightlight_outlined,
          title: '说晚安',
          desc: _nightDone ? '今天已经说过晚安了' : '10点后记得说晚安',
          color: const Color(0xFF8B5CF6),
          done: _nightDone,
        ),
        // 进度条
        const SizedBox(height: 8),
        _buildProgressSection(cs),
      ],
    );
  }

  Widget _buildTaskCard(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required bool done,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.04), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          // 图标
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: done
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              done ? Icons.check_circle : icon,
              color: done ? const Color(0xFF10B981) : color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // 文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: done
                            ? cs.onSurface.withOpacity(0.5)
                            : cs.onSurface)),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12,
                        color: done
                            ? const Color(0xFF10B981)
                            : cs.onSurfaceVariant)),
              ],
            ),
          ),
          // 完成标记
          if (done)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check, size: 14, color: Color(0xFF10B981)),
            )
          else
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }

  Widget _buildProgressSection(ColorScheme cs) {
    final progress = _completedCount() / 4.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('今日进度',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              Text('${_completedCount()}/4',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _completedCount() == 4
                ? '今日任务全部完成！'
                : '完成所有任务可以增进你和${_primaryCharacter?.name ?? 'TA'}的感情',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationView(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.map_outlined, size: 48, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text('虚拟位置',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Text('查看AI的实时位置',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
