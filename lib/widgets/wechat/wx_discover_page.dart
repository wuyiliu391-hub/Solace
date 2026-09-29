import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';
import 'wx_setting_row.dart';

/// 微信发现页 — 1:1 还原
///
/// 结构（fragment_find.xml）：
/// 朋友圈 | 视频号 直播 | 扫一扫 听一听 看一看 搜一搜 | 附近 | 购物 游戏 小程序
/// 每行 46dp，图标 18dp，左 14dp，分组间距 7dp
class WxDiscoverPage extends StatelessWidget {
  final int? momentsUnread;          // 朋友圈未读
  final ImageProvider? momentsThumb; // 朋友圈头像缩略图
  final VoidCallback? onMoments;
  final VoidCallback? onChannels;     // 视频号
  final VoidCallback? onLive;         // 直播
  final VoidCallback? onScan;         // 扫一扫
  final VoidCallback? onListen;      // 听一听
  final VoidCallback? onRead;         // 看一看
  final VoidCallback? onSearch;      // 搜一搜
  final VoidCallback? onNearby;      // 附近
  final VoidCallback? onShopping;    // 购物
  final VoidCallback? onGame;        // 游戏
  final VoidCallback? onMiniProgram; // 小程序

  const WxDiscoverPage({
    super.key,
    this.momentsUnread,
    this.momentsThumb,
    this.onMoments,
    this.onChannels,
    this.onLive,
    this.onScan,
    this.onListen,
    this.onRead,
    this.onSearch,
    this.onNearby,
    this.onShopping,
    this.onGame,
    this.onMiniProgram,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.chatBg,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          // 标题
          const SliverToBoxAdapter(
            child: _PageHeader(title: '发现'),
          ),
          // 朋友圈（带未读/缩略图）
          SliverToBoxAdapter(
            child: _MomentsRow(
              unread: momentsUnread,
              thumb: momentsThumb,
              onTap: onMoments,
            ),
          ),
          // 视频号 + 直播
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(
                  icon: Icons.play_circle_outline,
                  iconColor: const Color(0xFFFA5151),
                  title: '视频号',
                  onTap: onChannels,
                ),
                WxSettingRow(
                  icon: Icons.live_tv,
                  iconColor: const Color(0xFFFA5151),
                  title: '直播',
                  onTap: onLive,
                ),
              ],
            ),
          ),
          // 扫一扫 + 听一听 + 看一看 + 搜一搜
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(
                  icon: Icons.qr_code_scanner,
                  iconColor: const Color(0xFF07C160),
                  title: '扫一扫',
                  onTap: onScan,
                ),
                WxSettingRow(
                  icon: Icons.headphones,
                  iconColor: const Color(0xFF07C160),
                  title: '听一听',
                  onTap: onListen,
                ),
                WxSettingRow(
                  icon: Icons.visibility_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '看一看',
                  onTap: onRead,
                ),
                WxSettingRow(
                  icon: Icons.search,
                  iconColor: const Color(0xFF07C160),
                  title: '搜一搜',
                  onTap: onSearch,
                ),
              ],
            ),
          ),
          // 附近
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(
                  icon: Icons.location_on_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '附近',
                  onTap: onNearby,
                ),
              ],
            ),
          ),
          // 购物 + 游戏 + 小程序
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(
                  icon: Icons.shopping_bag_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '购物',
                  onTap: onShopping,
                ),
                WxSettingRow(
                  icon: Icons.sports_esports_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '游戏',
                  onTap: onGame,
                ),
                WxSettingRow(
                  icon: Icons.apps_outlined,
                  iconColor: const Color(0xFF07C160),
                  title: '小程序',
                  onTap: onMiniProgram,
                ),
              ],
            ),
          ),
          SliverFillRemaining(hasScrollBody: false),
        ],
      ),
    );
  }
}

/// 朋友圈行（带未读数和缩略图）
class _MomentsRow extends StatelessWidget {
  final int? unread;
  final ImageProvider? thumb;
  final VoidCallback? onTap;
  const _MomentsRow({this.unread, this.thumb, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WxColors.listBg,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt_outlined,
                        size: 22, color: Color(0xFFFA5151)),
                    const SizedBox(width: 13),
                    const Text('朋友圈',
                        style: TextStyle(
                            fontSize: 15, color: WxColors.textBlack)),
                    const Spacer(),
                    if (unread != null && unread! > 0) ...[
                      Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: WxColors.badge,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text('${unread! > 99 ? 99 : unread!}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, height: 1)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (thumb != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image(
                            image: thumb!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover),
                      ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 16, color: WxColors.textHint),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Container(
                  height: WxDimens.divider, color: WxColors.divider),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面标题栏（微信 Tab 页的标题，无返回按钮）
class _PageHeader extends StatelessWidget {
  final String title;
  const _PageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(height: WxDimens.divider, color: WxColors.divider),
        SizedBox(
          height: 48,
          child: Center(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    color: WxColors.textBlack,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}
