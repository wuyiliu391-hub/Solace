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
    final isWeChat = context.read<ThemeBloc>().state.isWeChat;
    if (isWeChat) {
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? WeChatColors.darkPageBackground
            : const Color(0xFFEDEDED),
        appBar: AppBar(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? WeChatColors.darkPageBackground
              : const Color(0xFFEDEDED),
          elevation: 0,
          title: const Text(
            '发现',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(WeChatDimens.dividerHeight),
            child: Divider(
              height: WeChatDimens.dividerHeight,
              thickness: WeChatDimens.dividerHeight,
              color: Color(0xFFD9D9D9),
            ),
          ),
        ),
        body: _buildWeChatFeaturesTab(),
      );
    }
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

  /// 微信发现页：圆角方形彩色图标 + 16sp 标题，分组白卡，组间间隔灰底。
  Widget _buildWeChatFeaturesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cellColor =
        isDark ? WeChatColors.darkListItem : WeChatColors.listItem;
    final titleColor = isDark
        ? WeChatColors.darkTextPrimary
        : WeChatColors.textPrimary;

    Widget cell(
      IconData icon,
      Color iconBg,
      String title,
      String route, {
      bool showDivider = false,
      Widget? trailing,
    }) {
      return InkWell(
        onTap: () => widget.onNavigate?.call(route),
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(icon, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style:
                            TextStyle(fontSize: 16, color: titleColor),
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
              ),
            ),
            if (showDivider)
              Divider(
                height: WeChatDimens.dividerHeight,
                thickness: WeChatDimens.dividerHeight,
                indent: 54,
                color: isDark
                    ? WeChatColors.darkDivider
                    : WeChatColors.dividerLight,
              ),
          ],
        ),
      );
    }

    Widget group(List<Widget> children) {
      return Container(
        color: cellColor,
        child: Column(children: children),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        group([
          cell(Icons.photo_library, const Color(0xFFFA9D3B), '朋友圈',
              '/moments'),
        ]),
        const SizedBox(height: 8),
        group([
          cell(Icons.psychology, const Color(0xFF5A6CF0), '记忆库', '/memory',
              showDivider: true),
          cell(Icons.mark_email_unread_outlined, const Color(0xFFE06A4E),
              '信箱', '/mailbox', showDivider: true),
          cell(Icons.book_rounded, const Color(0xFF8D6E63), '角色日记',
              '/diary'),
        ]),
        const SizedBox(height: 8),
        group([
          cell(Icons.photo_camera, WeChatColors.brandGreen, '发动态',
              '/create_moment', showDivider: true),
          cell(Icons.casino, const Color(0xFFE6A23C), '幸运转盘',
              '/lucky_wheel', showDivider: true),
          cell(Icons.auto_fix_high, const Color(0xFF9B59B6), '塔罗牌',
              '/tarot'),
        ]),
        const SizedBox(height: 8),
        group([
          cell(Icons.trending_up, const Color(0xFF67C23A), '成长轨迹',
              '/growth', showDivider: true),
          cell(Icons.thermostat, const Color(0xFFE6735A), '关系温度',
              '/relationship', showDivider: true),
          cell(Icons.psychology_alt, const Color(0xFF5DA9E9), '角色心理',
              '/psychology', showDivider: true),
          cell(Icons.auto_awesome, const Color(0xFFB58AF5), 'AI 动态',
              '/ai_activity'),
        ]),
      ],
    );
  }
}
