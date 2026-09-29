import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信主框架 — 1:1 还原
///
/// 底部 4 Tab：微信 / 通讯录 / 发现 / 我
/// 结构（activity_wchat.xml）：TabLayout 56dp，选中绿，未选中黑
class WxMainShell extends StatefulWidget {
  final Widget chatPage;
  final Widget contactsPage;
  final Widget discoverPage;
  final Widget mePage;

  const WxMainShell({
    super.key,
    required this.chatPage,
    required this.contactsPage,
    required this.discoverPage,
    required this.mePage,
  });

  @override
  State<WxMainShell> createState() => _WxMainShellState();
}

class _WxMainShellState extends State<WxMainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WxColors.chatBg,
      body: IndexedStack(
        index: _index,
        children: [
          widget.chatPage,
          widget.contactsPage,
          widget.discoverPage,
          widget.mePage,
        ],
      ),
      bottomNavigationBar: _WxBotTabBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 微信底部 Tab Bar
class _WxBotTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _WxBotTabBar({required this.index, required this.onChanged});

  static const _items = [
    _TabItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat, label: '微信'),
    _TabItem(icon: Icons.people_outline, activeIcon: Icons.people, label: '通讯录'),
    _TabItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: '发现'),
    _TabItem(icon: Icons.person_outline, activeIcon: Icons.person, label: '我'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: WxDimens.tabHeight + MediaQuery.of(context).padding.bottom,
      decoration: const BoxDecoration(
        color: WxColors.bottomTab,
        border: Border(
            top: BorderSide(width: WxDimens.divider, color: WxColors.divider)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: List.generate(4, (i) {
          final item = _items[i];
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 24,
                    color: selected ? WxColors.brand : WxColors.textBlack,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? WxColors.brand : WxColors.textBlack,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem(
      {required this.icon, required this.activeIcon, required this.label});
}
