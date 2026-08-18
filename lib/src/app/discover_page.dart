// 发现页：功能 / 娱乐互动双 Tab。
// 本文件是 main.dart 的 part，仅与其共同构成一个库，不可单独 import。

part of '../../main.dart';

class _DiscoverPage extends StatefulWidget {
  final Function(String)? onNavigate;
  const _DiscoverPage({this.onNavigate});

  @override
  State<_DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<_DiscoverPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.jumpToPage(_tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 16),
          dividerHeight: 0,
          tabs: const [
            Tab(text: '功能'),
            Tab(text: '娱乐互动'),
          ],
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          _tabController.animateTo(index);
        },
        children: [
          _buildFeaturesTab(cs),
          EntertainmentScreen(onNavigate: widget.onNavigate),
        ],
      ),
    );
  }

  Widget _buildFeaturesTab(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    return ListView(children: [
      _tile(
          context, Icons.photo_library, '朋友圈', '查看 AI 的动态', '/moments', cs, tt),
      _tile(context, Icons.psychology, '记忆库', '回顾你们的回忆', '/memory', cs, tt),
      _tile(context, Icons.mark_email_unread_outlined, '信箱', '查看 AI 写给你的来信',
          '/mailbox', cs, tt),
      _tile(context, Icons.book_rounded, '角色日记', 'TA 的内心独白', '/diary', cs, tt),
      _tile(context, Icons.bookmark_rounded, '收藏消息', '回顾收藏的聊天记录', '/bookmarks',
          cs, tt),
      _tile(context, Icons.casino, '幸运转盘', '试试手气', '/lucky_wheel', cs, tt),
      _tile(context, Icons.auto_fix_high, '塔罗牌', '每日占卜', '/tarot', cs, tt),
      _tile(context, Icons.trending_up, '成长轨迹', '查看成长记录', '/growth', cs, tt),
      _tile(context, Icons.auto_awesome, 'AI 动态', '查看 AI 的活动', '/ai_activity',
          cs, tt),
      _tile(context, Icons.thermostat, '关系温度', '查看关系仪表盘', '/relationship', cs,
          tt),
      _tile(context, Icons.psychology_alt, '角色心理', '看看 TA 现在在想什么',
          '/psychology', cs, tt),
    ]);
  }

  Widget _tile(BuildContext ctx, IconData icon, String title, String subtitle,
      String route, ColorScheme cs, TextTheme tt) {
    return ListTile(
      leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: cs.primary, size: 22)),
      title: Text(title,
          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
      onTap: () => widget.onNavigate?.call(route),
    );
  }
}
