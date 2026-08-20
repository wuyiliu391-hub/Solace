import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';
import 'wx_bubble.dart';

/// 微信通讯录页 — 1:1 还原
///
/// 结构（fragment_contacts.xml）：
/// 标题"通讯录" + 顶部搜索图标/添加图标
/// [新的朋友] [群聊] [标签] [公众号] 四个功能行
/// 联系人列表（按字母索引分组）
class WxContactsPage extends StatelessWidget {
  final List<WxContact> contacts;
  final int? newFriendsUnread;
  final VoidCallback? onNewFriends;
  final VoidCallback? onGroupChats;
  final VoidCallback? onTags;
  final VoidCallback? onOfficialAccounts;
  final VoidCallback? onSearch;
  final VoidCallback? onAdd;

  const WxContactsPage({
    super.key,
    required this.contacts,
    this.newFriendsUnread,
    this.onNewFriends,
    this.onGroupChats,
    this.onTags,
    this.onOfficialAccounts,
    this.onSearch,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    // 按拼音首字母分组
    final groups = _groupByInitial(contacts);

    return Container(
      color: WxColors.listBg,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          // 标题栏
          SliverToBoxAdapter(
            child: _ContactsHeader(onSearch: onSearch, onAdd: onAdd),
          ),
          // 功能行
          SliverToBoxAdapter(
            child: Column(
              children: [
                _FunctionRow(
                  icon: Icons.person_add_outlined,
                  iconColor: const Color(0xFFFA5151),
                  title: '新的朋友',
                  badge: newFriendsUnread,
                  onTap: onNewFriends,
                ),
                _FunctionRow(
                  icon: Icons.group_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '群聊',
                  onTap: onGroupChats,
                ),
                _FunctionRow(
                  icon: Icons.label_outline,
                  iconColor: const Color(0xFF07C160),
                  title: '标签',
                  onTap: onTags,
                ),
                _FunctionRow(
                  icon: Icons.notifications_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '公众号',
                  onTap: onOfficialAccounts,
                ),
                Container(
                    height: 7, color: WxColors.chatBg),
              ],
            ),
          ),
          // 联系人分组
          ...groups.entries.expand((e) => _buildGroup(e.key, e.value)),
          SliverFillRemaining(hasScrollBody: false),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(String letter, List<WxContact> items) {
    return [
      SliverToBoxAdapter(
        child: Container(
          height: 24,
          color: WxColors.listBg,
          padding: const EdgeInsets.only(left: 13, top: 4),
          alignment: Alignment.centerLeft,
          child: Text(letter,
              style: const TextStyle(
                  fontSize: 12, color: WxColors.textGray)),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _ContactTile(contact: items[i]),
          childCount: items.length,
        ),
      ),
    ];
  }

  Map<String, List<WxContact>> _groupByInitial(List<WxContact> list) {
    final map = <String, List<WxContact>>{};
    for (final c in list) {
      final k = (c.initial ?? '#').toUpperCase();
      map.putIfAbsent(k, () => []).add(c);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }
}

/// 联系人数据
class WxContact {
  final String name;
  final ImageProvider? avatar;
  final String? initial; // 拼音首字母

  const WxContact({required this.name, this.avatar, this.initial});
}

class _ContactsHeader extends StatelessWidget {
  final VoidCallback? onSearch;
  final VoidCallback? onAdd;
  const _ContactsHeader({this.onSearch, this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(height: WxDimens.divider, color: WxColors.divider),
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Text('通讯录',
                  style: TextStyle(
                      fontSize: 17,
                      color: WxColors.textBlack,
                      fontWeight: FontWeight.w500)),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search,
                        size: 20, color: WxColors.textBlack),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add,
                        size: 22, color: WxColors.textBlack),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(height: WxDimens.divider, color: WxColors.divider),
      ],
    );
  }
}

class _FunctionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final int? badge;
  final VoidCallback? onTap;
  const _FunctionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WxColors.listBg,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 13),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, color: WxColors.textBlack)),
                    const Spacer(),
                    if (badge != null && badge! > 0) ...[
                      Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: WxColors.badge,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text('${badge! > 99 ? 99 : badge!}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, height: 1)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.chevron_right,
                        size: 16, color: WxColors.textHint),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Container(
                  height: WxDimens.divider, color: WxColors.divider),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final WxContact contact;
  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WxColors.listBg,
      child: InkWell(
        onTap: () {},
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    WxAvatar(
                        image: contact.avatar,
                        text: contact.name,
                        size: 40),
                    const SizedBox(width: 13),
                    Text(contact.name,
                        style: const TextStyle(
                            fontSize: 15, color: WxColors.textBlack)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 66),
              child: Container(
                  height: WxDimens.divider, color: WxColors.divider),
            ),
          ],
        ),
      ),
    );
  }
}
