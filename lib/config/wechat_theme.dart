/// 微信官方设计规范 — 1:1 还原
///
/// 数据来源：刷圈兔 9.6.0 逆向（res/values/colors.xml + dimens.xml + layout）
/// 所有色值/尺寸均为微信真实资源，非目测。
library;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// 配色（wx_* 实锤值）
// ─────────────────────────────────────────────────────────────
class WxColors {
  WxColors._();

  // 品牌色
  static const Color brand = Color(0xFF07C160);        // 微信绿（发送/选中）
  static const Color brandDark = Color(0xFF06AD56);    // 按下态绿
  static const Color guideSelect = Color(0xFF08C261);  // Tab 选中绿

  // 背景
  static const Color chatBg = Color(0xFFEAEAEA);       // 聊天页背景
  static const Color navBg = Color(0xFFF6F6F6);        // 顶部导航栏
  static const Color bottomTab = Color(0xFFF6F6F6);    // 底部 Tab
  static const Color inputBar = Color(0xFFF5F5F5);     // 输入栏
  static const Color listBg = Color(0xFFFFFFFF);       // 列表/会话页
  static const Color cellPressed = Color(0xFFECECEC);  // 列表项按下

  // 气泡
  static const Color bubbleMe = Color(0xFF95EC69);     // 我的气泡绿
  static const Color bubbleMePressed = Color(0xFF89D961);
  static const Color bubbleOther = Color(0xFFFFFFFF);  // 对方气泡白
  static const Color bubbleOtherPressed = Color(0xFFE6E6E6);

  // 文字
  static const Color textMe = Color(0xFF0E2206);       // 我的气泡文字
  static const Color textPrimary = Color(0xFF333333);  // 主文字
  static const Color textBlack = Color(0xFF000000);
  static const Color textGray = Color(0xFF7F7F7F);     // 次要
  static const Color textTime = Color(0xFF999999);     // 时间戳
  static const Color textHint = Color(0xFFB2B2B2);     // 占位/搜索
  static const Color lastMessage = Color(0xFFACACAC);  // 会话列表摘要

  // 分割/描边
  static const Color divider = Color(0xFFE1E1E1);      // 聊天区顶部分割
  static const Color hairline = Color(0xFFD9D9D9);     // 通用 hairline
  static const Color inputBorder = Color(0xFFCCCCCC);

  // 状态/提醒
  static const Color badge = Color(0xFFFA5151);        // 红点/角标
  static const Color link = Color(0xFF576B95);         // 链接蓝

  // 红包/转账
  static const Color redPacketLine = Color(0xFFF4AB5D);
  static const Color redPacketBg = Color(0xFFFEFEFE);
  static const Color transferBg = Color(0xFFFDF2DF);
}

// ─────────────────────────────────────────────────────────────
// 尺寸（dimens 实锤值）
// ─────────────────────────────────────────────────────────────
class WxDimens {
  WxDimens._();

  static const double avatar = 35.0;        // 聊天头像
  static const double avatarRadius = 4.0;   // 头像圆角
  static const double avatarList = 48.0;    // 会话列表头像
  static const double msgSideMargin = 13.0; // 消息距屏边
  static const double bubblePadH = 12.0;    // 气泡水平内边距
  static const double bubblePadV = 10.0;    // 气泡垂直内边距
  static const double bubbleRadius = 6.0;   // 气泡圆角
  static const double bubbleMaxRatio = 0.66;// 气泡最大宽占屏比
  static const double divider = 0.5;        // 分割线
  static const double navHeight = 46.0;     // 顶部导航
  static const double tabHeight = 56.0;     // 底部 Tab
  static const double sendBtnRadius = 4.0;  // 发送按钮
  static const double inputRadius = 5.0;    // 输入框
}

// ─────────────────────────────────────────────────────────────
// 文字样式
// ─────────────────────────────────────────────────────────────
class WxText {
  WxText._();

  static const TextStyle message = TextStyle(
      fontSize: 16, color: WxColors.textPrimary, height: 1.35);
  static const TextStyle messageMe = TextStyle(
      fontSize: 16, color: WxColors.textMe, height: 1.35);
  static const TextStyle time = TextStyle(
      fontSize: 12, color: WxColors.textTime);
  static const TextStyle nickname = TextStyle(
      fontSize: 13, color: WxColors.textGray);
  static const TextStyle convTitle = TextStyle(
      fontSize: 16, color: WxColors.textBlack);
  static const TextStyle convSummary = TextStyle(
      fontSize: 14, color: WxColors.lastMessage);
  static const TextStyle navTitle = TextStyle(
      fontSize: 17, color: WxColors.textBlack, fontWeight: FontWeight.w500);
}

// ─────────────────────────────────────────────────────────────
// 主题
// ─────────────────────────────────────────────────────────────
class WxTheme {
  WxTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: WxColors.listBg,
      primaryColor: WxColors.brand,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      dividerColor: WxColors.hairline,
      appBarTheme: const AppBarTheme(
        backgroundColor: WxColors.navBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: WxText.navTitle,
        iconTheme: IconThemeData(color: WxColors.textBlack),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: WxColors.brand,
        primary: WxColors.brand,
        surface: WxColors.listBg,
      ),
    );
  }
}
