import 'package:flutter/material.dart';

/// 深色沉浸式主题调色板（18.3.0 Shine 风格改版）。
///
/// 设计语言：深夜蓝黑底色 + 酒粉暖强调，弱化界面框架、突出角色氛围。
/// 渐变色与语音通话页（voice_call_screen.dart）同源，保持全 App 氛围一致。
class ImmersiveColors {
  // ── 底色梯度（与通话页渐变同源） ──
  static const background = Color(0xFF0A0C16); // 最深底色（scaffold）
  static const backgroundMid = Color(0xFF0B0E1A);
  static const backgroundUp = Color(0xFF101528); // 次底/渐变亮端

  // ── 卡片与描边（白色低透明度叠层） ──
  static const card = Color(0x0DFFFFFF); // 白 5%
  static const cardHigh = Color(0x14FFFFFF); // 白 8%
  static const border = Color(0x1AFFFFFF); // 白 10%
  static const divider = Color(0x0FFFFFFF); // 白 6%

  // ── 强调色 ──
  static const accent = Color(0xFFC88383); // 酒粉（主强调，延续用户气泡色系）
  static const accentDeep = Color(0xFFB86F76); // 酒粉深（渐变/按压态）
  static const accentSoft = Color(0xFF6C8CFF); // 蓝紫（次强调，通话态同源）

  // ── 文字（暖白梯度） ──
  static const textPrimary = Color(0xEBF5F0EA); // 暖白 92%
  static const textSecondary = Color(0x99F5F0EA); // 暖白 60%
  static const textTertiary = Color(0x66F5F0EA); // 暖白 40%

  // ── 导航 ──
  static const navBackground = Color(0xF20A0C16); // 深底 95% 不透明
}

/// 微信风格调色板（18.3.0 第三视觉风格）。
///
/// 来源：逆向提取自第三方仿微信应用「刷圈兔 9.6.0」（apktool 解包
/// res/values/colors.xml 的 wx_* 段 + drawable-night 深色段 + 气泡
/// 9-patch 采样），并与微信官方 WeUI 规范交叉核对。
/// 关键值与官方一致：品牌绿 #07C160、自己气泡 #95EC69、对方气泡白、
/// 深色气泡 #2C2C2C。
class WeChatColors {
  // ══ 浅色 ══
  static const chatBackground = Color(0xFFEAEAEA); // 聊天页背景
  static const pageBackground = Color(0xFFF6F6F6); // 页面/导航/Tab 背景
  static const listItem = Color(0xFFFFFFFF); // 列表项白底
  static const chatBottomBar = Color(0xFFF5F5F5); // 聊天底部输入区
  static const inputBox = Color(0xFFFFFFFF); // 输入框

  static const bubbleMine = Color(0xFF95EC69); // 自己的气泡（官方绿）
  static const bubbleMineText = Color(0xFF0E2206);
  static const bubbleOther = Color(0xFFFFFFFF); // 对方的气泡
  static const bubbleOtherText = Color(0xFF333333);
  static const bubblePressed = Color(0xFFDFDFDF);

  static const brandGreen = Color(0xFF07C160); // 品牌绿（发送钮/选中）
  static const brandGreenPressed = Color(0xFF0C9253);

  static const textPrimary = Color(0xFF191919);
  static const textSecondary = Color(0xFF7F7F7F);
  static const textPreview = Color(0xFFACACAC); // 会话列表摘要
  static const divider = Color(0xFFE1E1E1);
  static const dividerLight = Color(0xFFD9D9D9);
  static const linkBlue = Color(0xFF576A8B); // 朋友圈链接蓝
  static const badgeRed = Color(0xFFFA5151); // 未读角标红

  // ══ 深色（values-night 提取） ══
  static const darkPageBackground = Color(0xFF111111);
  static const darkListItem = Color(0xFF181818);
  static const darkCard = Color(0xFF2C2C2C);
  static const darkChatBottomBar = Color(0xFF1E1E1E);
  static const darkInputBox = Color(0xFF292929);

  static const darkBubbleOther = Color(0xFF2C2C2C); // 深色对方气泡
  static const darkBubbleOtherText = Color(0xFFD2D2D2);
  static const darkBubbleMineText = Color(0xFF000000); // 深色下绿气泡黑字

  static const darkTextPrimary = Color(0xFFCDCDCD);
  static const darkTextSecondary = Color(0xFF8C8C8C);
  static const darkTextPreview = Color(0xFF5F5F5F);
  static const darkDivider = Color(0xFF262626);
}

/// 微信几何规格（逆向自仿微信应用实测值，勿凭感觉改）。
///
/// 会话列表：行高 60-66，头像 40-48 圆角方形，标题 16-17sp，
/// 摘要 12-13sp 单行，时间 12sp，分割线 0.5 自头像右侧缩进 (~64)。
/// 聊天页：气泡圆角 6，内边距 H11 V9，正文 15.5sp 行距 2，
/// 头像 40，气泡最大宽 65%，消息间距 14；输入栏高 ~50 输入框圆角 6；
/// 时间戳 12sp 居中上下间距 12；底 Tab 高 ~54。
class WeChatDimens {
  WeChatDimens._();

  // ── 会话列表 ──
  static const double sessionRowHeight = 64;
  static const double sessionAvatarSize = 44;
  static const double sessionPaddingH = 14;
  static const double sessionTitleSize = 16;
  static const double sessionPreviewSize = 12.5;
  static const double sessionTimeSize = 11;
  static const double dividerHeight = 0.5;
  static const double dividerIndent = 70;

  // ── 聊天页 ──
  static const double chatAvatarSize = 40;
  static const double bubbleRadius = 6;
  static const double bubblePadH = 11;
  static const double bubblePadV = 9;
  static const double bubbleTextSize = 15.5;
  static const double bubbleLineSpacing = 2;
  static const double bubbleMaxWidthRatio = 0.65;
  static const double messageSpacing = 14;
  static const double timestampSize = 12;
  static const double timestampMarginV = 12;

  // ── 输入栏 ──
  static const double inputBarHeight = 50;
  static const double inputBoxRadius = 6;
  static const double inputBarIconSize = 27;

  // ── 底部 Tab ──
  static const double tabBarHeight = 54;
  static const double tabIconSize = 26;
  static const double tabTextSize = 10.5;
}

/// Classic (douyin) theme color constants
class ClassicColors {
  // Memory graph type colors - vibrant pink/purple palette
  static const graphTypeColors = [
    Color(0xFF64B5F6), // conversation - blue
    Color(0xFF9C5A9A), // reflection - purple
    Color(0xFFFF9ECB), // milestone - pink
    Color(0xFFE879A8), // emotion - deep pink
    Color(0xFFF472B6), // preference - rose
    Color(0xFF7AA382), // state - green
    Color(0xFFBA68C8), // rollingSummary - light purple
  ];
}
