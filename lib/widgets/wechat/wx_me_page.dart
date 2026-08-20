import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';
import 'wx_setting_row.dart';

/// 微信"我"页面 — 1:1 还原
///
/// 结构（activity_wx_geren.xml）：
/// [头像大行 58dp] [名字 46dp] [拍一拍] [微信号] [二维码名片] [更多信息]
/// [来电铃声] [微信豆] [我的地址]
class WxMePage extends StatelessWidget {
  final String nickname;
  final String wxId;
  final ImageProvider? avatar;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onNameTap;
  final VoidCallback? onWxIdTap;
  final VoidCallback? onQRCodeTap;
  final VoidCallback? onMoreInfoTap;
  final VoidCallback? onRingtoneTap;
  final VoidCallback? onWxBeansTap;
  final VoidCallback? onAddressTap;

  const WxMePage({
    super.key,
    required this.nickname,
    required this.wxId,
    this.avatar,
    this.onAvatarTap,
    this.onNameTap,
    this.onWxIdTap,
    this.onQRCodeTap,
    this.onMoreInfoTap,
    this.onRingtoneTap,
    this.onWxBeansTap,
    this.onAddressTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.chatBg,
      child: CustomScrollView(
        slivers: [
          // 状态栏间距
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          // 头像行（58dp）
          SliverToBoxAdapter(
            child: _AvatarRow(
              avatar: avatar,
              onTap: onAvatarTap,
            ),
          ),
          // 名字
          SliverToBoxAdapter(
            child: WxSettingRow(
              title: '名字',
              value: nickname,
              onTap: onNameTap,
            ),
          ),
          // 拍一拍
          SliverToBoxAdapter(
            child: WxSettingRow(title: '拍一拍', onTap: () {}),
          ),
          // 微信号
          SliverToBoxAdapter(
            child: WxSettingRow(
              title: '微信号',
              value: wxId,
              onTap: onWxIdTap,
            ),
          ),
          // 二维码名片
          SliverToBoxAdapter(
            child: WxSettingRow(
              title: '二维码名片',
              trailingWidget: const Icon(Icons.qr_code_2,
                  size: 16, color: WxColors.textGray),
              onTap: onQRCodeTap,
            ),
          ),
          // 更多信息
          SliverToBoxAdapter(
            child: WxSettingRow(title: '更多信息', onTap: onMoreInfoTap),
          ),
          // 来电铃声（分组间距 7dp）
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(
                  title: '来电铃声',
                  value: '背景声音',
                  onTap: onRingtoneTap,
                ),
              ],
            ),
          ),
          // 微信豆
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(title: '微信豆', onTap: onWxBeansTap),
              ],
            ),
          ),
          // 我的地址
          SliverToBoxAdapter(
            child: WxSettingGroup(
              topSpacing: 7,
              rows: [
                WxSettingRow(title: '我的地址', onTap: onAddressTap),
              ],
            ),
          ),
          SliverFillRemaining(hasScrollBody: false),
        ],
      ),
    );
  }
}

/// 头像行（58dp，头像 48dp，右侧箭头）
class _AvatarRow extends StatelessWidget {
  final ImageProvider? avatar;
  final VoidCallback? onTap;
  const _AvatarRow({this.avatar, this.onTap});

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
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    const Text('头像',
                        style: TextStyle(
                            fontSize: 15, color: WxColors.textBlack)),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFFDDDEDD),
                        child: avatar != null
                            ? Image(image: avatar!, fit: BoxFit.cover)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right,
                        size: 18, color: WxColors.textHint),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Container(
                  height: WxDimens.divider, color: WxColors.divider),
            ),
          ],
        ),
      ),
    );
  }
}
