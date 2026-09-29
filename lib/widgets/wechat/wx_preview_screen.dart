/// 微信主题组件预览页
///
/// 把所有微信风格组件拼在一页，用于直观验收还原效果。
/// 聊天、红包、转账、设置行、朋友圈等全部展示。
library;

import 'package:flutter/material.dart';

import '../../config/wechat_theme.dart';
import 'wx_bubble.dart';
import 'wx_money_card.dart';
import 'wx_setting_row.dart';

class WxPreviewScreen extends StatelessWidget {
  const WxPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: WxTheme.light(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: WxColors.chatBg,
          appBar: AppBar(
            backgroundColor: WxColors.navBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: const Text('微信主题预览', style: WxText.navTitle),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ── 聊天气泡 ──
              _sectionLabel('聊天气泡'),
              Container(
                color: WxColors.chatBg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    WxMessageRow(
                      isMe: false,
                      text: '你好，这是一条对方发来的消息',
                      avatarText: '张',
                    ),
                    const SizedBox(height: 8),
                    WxMessageRow(
                      isMe: true,
                      text: '收到，这是一条我发出的消息',
                      avatarText: '我',
                    ),
                    const SizedBox(height: 8),
                    WxMessageRow(
                      isMe: false,
                      text: '气泡尾巴和圆角都还原了吗？',
                      avatarText: '张',
                    ),
                    const SizedBox(height: 8),
                    WxMessageRow(
                      isMe: true,
                      text: '还原了，4dp 方角头像 + 6dp 圆角气泡 + 三角尾巴',
                      avatarText: '我',
                    ),
                  ],
                ),
              ),

              // ── 红包/转账 ──
              _sectionLabel('红包 / 转账'),
              Container(
                color: WxColors.chatBg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    WxMoneyRow(
                      kind: WxMoneyKind.redPacket,
                      isMe: false,
                      avatarText: '李',
                      title: '恭喜发财，大吉大利',
                    ),
                    const SizedBox(height: 8),
                    WxMoneyRow(
                      kind: WxMoneyKind.redPacket,
                      isMe: true,
                      avatarText: '我',
                      title: '新年快乐',
                    ),
                    const SizedBox(height: 8),
                    WxMoneyRow(
                      kind: WxMoneyKind.transfer,
                      isMe: false,
                      avatarText: '王',
                      amount: '¥200.00',
                      title: '你发起了一笔转账',
                    ),
                    const SizedBox(height: 8),
                    WxMoneyRow(
                      kind: WxMoneyKind.transfer,
                      isMe: true,
                      avatarText: '我',
                      amount: '¥88.88',
                      title: '请收款',
                    ),
                  ],
                ),
              ),

              // ── 设置行 ──
              _sectionLabel('设置行'),
              WxSettingGroup(
                title: '通用',
                rows: [
                  WxSettingRow(
                    icon: Icons.person_outline,
                    iconColor: WxColors.brand,
                    title: '账号与安全',
                  ),
                  WxSettingRow(
                    icon: Icons.notifications_none,
                    iconColor: WxColors.brand,
                    title: '新消息通知',
                  ),
                  WxSettingRow(
                    icon: Icons.lock_outline,
                    iconColor: WxColors.brand,
                    title: '隐私',
                    showArrow: true,
                  ),
                ],
              ),
              WxSettingGroup(
                title: '我的',
                rows: [
                  WxSettingRow(
                    icon: Icons.payments_outlined,
                    iconColor: WxColors.brand,
                    title: '服务',
                  ),
                  WxSettingRow(
                    icon: Icons.favorite_border,
                    iconColor: WxColors.brand,
                    title: '收藏',
                  ),
                  WxSettingRow(
                    icon: Icons.photo_size_select_actual_outlined,
                    iconColor: WxColors.brand,
                    title: '朋友圈',
                    dividerFromIcon: false,
                  ),
                ],
              ),

              // ── 色板 ──
              _sectionLabel('色板'),
              _colorPalette(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WxColors.textGray,
        ),
      ),
    );
  }

  Widget _colorPalette() {
    final colors = <(String, Color)>[
      ('brand #07C160', WxColors.brand),
      ('bubbleMe #95EC69', WxColors.bubbleMe),
      ('chatBg #EAEAEA', WxColors.chatBg),
      ('navBg #F6F6F6', WxColors.navBg),
      ('textPrimary #333333', WxColors.textPrimary),
      ('textGray #7F7F7F', WxColors.textGray),
      ('badge #FA5151', WxColors.badge),
      ('link #576B95', WxColors.link),
      ('redPacketLine #F4AB5D', WxColors.redPacketLine),
      ('transferBg #FDF2DF', WxColors.transferBg),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: colors.map((e) {
          return Container(
            width: 160,
            height: 44,
            decoration: BoxDecoration(
              color: e.$2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: WxColors.hairline),
            ),
            alignment: Alignment.center,
            child: Text(
              e.$1,
              style: TextStyle(
                fontSize: 11,
                color: e.$2.computeLuminance() > 0.5
                    ? WxColors.textPrimary
                    : Colors.white,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
