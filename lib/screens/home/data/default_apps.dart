import 'package:flutter/material.dart';
import 'package:flutter_remix/flutter_remix.dart';
import '../../../models/app_item.dart';

/// 默认桌面布局：12 个图标 + 4 个 Dock 图标
class DefaultApps {
  DefaultApps._();

  static final List<AppItem> all = [
    // ─── 第 1 页 · Lovemo 粉色系 ───
    const AppItem(
      id: 'chat_list',
      name: '消息',
      iconAsset: 'chat_bubble',
      route: '/chat_list',
      accentColor: 0xFFF472B6, // 粉色
    ),
    const AppItem(
      id: 'contacts',
      name: '通讯录',
      iconAsset: 'people',
      route: '/contacts',
      accentColor: 0xFFEC4899, // 玫粉
    ),
    const AppItem(
      id: 'ai_assistant',
      name: 'AI 助手',
      iconAsset: 'auto_awesome',
      route: '/ai_assistant',
      accentColor: 0xFFD946EF, // 紫粉
    ),
    const AppItem(
      id: 'memory',
      name: '记忆',
      iconAsset: 'psychology',
      route: '/memory',
      accentColor: 0xFFF59E0B, // 琥珀（暖色点缀）
    ),
    const AppItem(
      id: 'moments',
      name: '朋友圈',
      iconAsset: 'photo_library',
      route: '/moments',
      accentColor: 0xFFFB7185, // 珊瑚粉
    ),
    const AppItem(
      id: 'growth',
      name: '成长',
      iconAsset: 'trending_up',
      route: '/growth',
      accentColor: 0xFFA78BFA, // 薰衣草紫
    ),
    const AppItem(
      id: 'map',
      name: '地图',
      iconAsset: 'map',
      route: '/map',
      accentColor: 0xFFF472B6, // 粉色
    ),
    const AppItem(
      id: 'create_character',
      name: '创建角色',
      iconAsset: 'person_add',
      route: '/create_character',
      accentColor: 0xFFC084FC, // 淡紫
    ),
    const AppItem(
      id: 'tarot',
      name: '塔罗牌',
      iconAsset: 'tarot',
      route: '/tarot',
      accentColor: 0xFF8B5CF6, // 紫色
    ),
    const AppItem(
      id: 'story',
      name: '故事书',
      iconAsset: 'story',
      route: '/story',
      accentColor: 0xFFE879A6, // 书香粉
    ),
    // 已隐藏：日记模块前端入口暂不展示（后端代码保留）
    // const AppItem(
    //   id: 'forum',
    //   name: '日记',
    //   iconAsset: 'forum',
    //   route: '/forum',
    //   accentColor: 0xFF60A5FA, // 天蓝
    // ),
    const AppItem(
      id: 'virtual_map',
      name: '双人地图',
      iconAsset: 'explore',
      route: '/virtual_map',
      accentColor: 0xFF34D399, // 薄荷绿
    ),
    const AppItem(
      id: 'lucky_wheel',
      name: '幸运转盘',
      iconAsset: 'casino',
      route: '/lucky_wheel',
      accentColor: 0xFFF472B6, // 粉色
    ),
  ];

  static final List<AppItem> dock = [
    const AppItem(
      id: 'profile',
      name: '我的',
      iconAsset: 'person',
      route: '/profile',
      accentColor: 0xFFF9A8D4, // 浅粉
      isDock: true,
    ),
    const AppItem(
      id: 'settings',
      name: '设置',
      iconAsset: 'settings',
      route: '/settings',
      accentColor: 0xFFE879A8, // 暖粉
      isDock: true,
    ),
    const AppItem(
      id: 'chat_list_dock',
      name: '消息',
      iconAsset: 'chat_bubble',
      route: '/chat_list',
      accentColor: 0xFFF472B6, // 粉色
      isDock: true,
    ),
    const AppItem(
      id: 'contacts_dock',
      name: '通讯录',
      iconAsset: 'people',
      route: '/contacts',
      accentColor: 0xFFEC4899, // 玫粉
      isDock: true,
    ),
  ];

  /// 默认布局
  static HomeLayout get defaultLayout => HomeLayout(
        pages: [all],
        dock: dock,
      );

  /// 图标名称 → IconData 映射（圆润现代风格）
  /// Material 兼容图标映射（保留向后兼容）
  static final Map<String, IconData> iconMap = {
    'chat_bubble': Icons.chat_bubble_rounded,
    'people': Icons.people_alt_rounded,
    'auto_awesome': Icons.auto_awesome_rounded,
    'psychology': Icons.psychology_rounded,
    'photo_library': Icons.photo_library_rounded,
    'trending_up': Icons.trending_up_rounded,
    'map': Icons.map_rounded,
    'person_add': Icons.person_add_rounded,
    'groups': Icons.groups_rounded,
    'person': Icons.person_rounded,
    'settings': Icons.settings_rounded,
    'storefront': Icons.storefront_rounded,
    'grid_view': Icons.grid_view_rounded,
    'flag': Icons.flag_rounded,
    'favorite': Icons.favorite_rounded,
    'notifications': Icons.notifications_rounded,
    'search': Icons.search_rounded,
    'tarot': Icons.auto_fix_high_rounded,
    'story': Icons.auto_stories_rounded,
  };

  /// Remix Icon 专业图标映射（Fill 实心填充风格）
  static final Map<String, IconData> remixIconMap = {
    'chat_bubble': FlutterRemix.chat_3_fill,
    'people': FlutterRemix.contacts_book_fill,
    'auto_awesome': FlutterRemix.magic_fill,
    'psychology': FlutterRemix.psychotherapy_fill,
    'photo_library': FlutterRemix.gallery_fill,
    'trending_up': FlutterRemix.line_chart_fill,
    'map': FlutterRemix.map_pin_2_fill,
    'person_add': FlutterRemix.user_add_fill,
    'groups': FlutterRemix.group_fill,
    'person': FlutterRemix.user_fill,
    'settings': FlutterRemix.settings_3_fill,
    'storefront': FlutterRemix.store_2_fill,
    'grid_view': FlutterRemix.dashboard_fill,
    'flag': FlutterRemix.flag_fill,
    'favorite': FlutterRemix.heart_3_fill,
    'notifications': FlutterRemix.notification_3_fill,
    'search': FlutterRemix.search_eye_fill,
    'tarot': FlutterRemix.magic_fill,
    'story': FlutterRemix.book_open_fill,
  };

  /// 获取图标：优先 Remix，fallback Material
  static IconData getIcon(String name) {
    return remixIconMap[name] ?? iconMap[name] ?? FlutterRemix.apps_fill;
  }

  /// 获取 Material 图标（用于不支持 Remix 的场景）
  static IconData getMaterialIcon(String name) {
    return iconMap[name] ?? Icons.apps;
  }
}
