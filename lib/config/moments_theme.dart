import 'package:flutter/material.dart';

/// X 推特风格主题配置
/// 适配深浅色模式，与朋友圈风格完全独立
class MomentsTheme {
  MomentsTheme._();

  // ─── 推特图标字体 ───
  static const _kFontFam = 'TwitterIcon';

  // 操作栏图标
  static const IconData reply = IconData(0xf151, fontFamily: _kFontFam);
  static const IconData retweet = IconData(0xf152, fontFamily: _kFontFam);
  static const IconData heartEmpty = IconData(0xf148, fontFamily: _kFontFam);
  static const IconData heartFill = IconData(0xf015, fontFamily: _kFontFam);
  static const IconData bookmark = IconData(0xf155, fontFamily: _kFontFam);
  static const IconData bookmarkFill = IconData(0xf155, fontFamily: _kFontFam);

  // 功能图标
  static const IconData arrowDown = IconData(0xf196, fontFamily: _kFontFam);
  static const IconData blueTick = IconData(0xf099, fontFamily: _kFontFam);
  static const IconData link = IconData(0xf098, fontFamily: _kFontFam);
  static const IconData edit = IconData(0xf112, fontFamily: _kFontFam);
  static const IconData delete = IconData(0xf154, fontFamily: _kFontFam);
  static const IconData pin = IconData(0xf088, fontFamily: _kFontFam);
  static const IconData mute = IconData(0xf101, fontFamily: _kFontFam);
  static const IconData block = IconData(0xe609, fontFamily: _kFontFam);
  static const IconData report = IconData(0xf038, fontFamily: _kFontFam);
  static const IconData image = IconData(0xf109, fontFamily: _kFontFam);
  static const IconData camera = IconData(0xf110, fontFamily: _kFontFam);
  static const IconData settings = IconData(0xf059, fontFamily: _kFontFam);
  static const IconData notification = IconData(0xf055, fontFamily: _kFontFam);
  static const IconData notificationFill =
      IconData(0xf019, fontFamily: _kFontFam);
  static const IconData search = IconData(0xf058, fontFamily: _kFontFam);
  static const IconData profile = IconData(0xf056, fontFamily: _kFontFam);

  // ─── 浅色主题色彩（原版 X 浅色风格）───
  static const Color lightPrimary = Color(0xFF1D9BF0);      // X 蓝
  static const Color lightLike = Color(0xFFF91880);          // X 粉红
  static const Color lightRetweet = Color(0xFF00BA7C);       // X 绿
  static const Color lightReply = Color(0xFF1D9BF0);         // X 蓝
  static const Color lightDivider = Color(0xFFEFF3F4);       // X 分割线
  static const Color lightBackground = Color(0xFFFFFFFF);    // X 纯白
  static const Color lightCardBackground = Color(0xFFFFFFFF); // X 纯白卡片
  static const Color lightTextPrimary = Color(0xFF0F1419);   // X 黑文字
  static const Color lightTextSecondary = Color(0xFF536471); // X 灰文字
  static const Color lightMention = Color(0xFF1D9BF0);       // X 蓝提及
  static const Color lightHashtag = Color(0xFF1D9BF0);       // X 蓝话题
  static const Color lightUrl = Color(0xFF1D9BF0);           // X 蓝链接
  static const Color lightIconDefault = Color(0xFF536471);   // X 灰图标
  static const Color lightSurface = Color(0xFFF7F9FA);       // X 次表面

  // ─── 深色主题色彩（原版 X 纯黑风格）───
  static const Color darkPrimary = Color(0xFF1D9BF0);      // X 蓝
  static const Color darkLike = Color(0xFFF91880);          // X 粉红
  static const Color darkRetweet = Color(0xFF00BA7C);       // X 绿
  static const Color darkReply = Color(0xFF1D9BF0);         // X 蓝
  static const Color darkDivider = Color(0xFF2F3336);       // X 分割线
  static const Color darkBackground = Color(0xFF000000);    // X 纯黑
  static const Color darkCardBackground = Color(0xFF000000); // X 纯黑卡片
  static const Color darkTextPrimary = Color(0xFFE7E9EA);   // X 白文字
  static const Color darkTextSecondary = Color(0xFF71767B); // X 灰文字
  static const Color darkMention = Color(0xFF1D9BF0);       // X 蓝提及
  static const Color darkHashtag = Color(0xFF1D9BF0);       // X 蓝话题
  static const Color darkUrl = Color(0xFF1D9BF0);           // X 蓝链接
  static const Color darkIconDefault = Color(0xFF71767B);   // X 灰图标
  static const Color darkSurface = Color(0xFF16181C);       // X 次表面

  /// 根据当前主题获取颜色
  static Color primary(BuildContext context) =>
      isDark(context) ? darkPrimary : lightPrimary;
  static Color like(BuildContext context) =>
      isDark(context) ? darkLike : lightLike;
  static Color retweetColor(BuildContext context) =>
      isDark(context) ? darkRetweet : lightRetweet;
  static Color replyColor(BuildContext context) =>
      isDark(context) ? darkReply : lightReply;
  static Color divider(BuildContext context) =>
      isDark(context) ? darkDivider : lightDivider;
  static Color background(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;
  static Color cardBackground(BuildContext context) =>
      isDark(context) ? darkCardBackground : lightCardBackground;
  static Color textPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;
  static Color textSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;
  static Color mention(BuildContext context) =>
      isDark(context) ? darkMention : lightMention;
  static Color hashtag(BuildContext context) =>
      isDark(context) ? darkHashtag : lightHashtag;
  static Color urlColor(BuildContext context) =>
      isDark(context) ? darkUrl : lightUrl;
  static Color iconDefault(BuildContext context) =>
      isDark(context) ? darkIconDefault : lightIconDefault;
  static Color surface(BuildContext context) =>
      isDark(context) ? darkSurface : lightSurface;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
