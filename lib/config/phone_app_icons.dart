import 'package:flutter/material.dart';

/// 虚拟手机桌面图标目录。
///
/// 主路径：代码玻璃软图标（[fallbackColor] + [fallbackIcon]）。
/// 可选：若存在 `assets/phone_icons/generated/{id}.webp|png` 且 preferAsset=true 可增强。
class PhoneAppIconDef {
  final String id;
  final String label;
  final String subject;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final PhoneIconPriority priority;
  final String? routeHint;

  const PhoneAppIconDef({
    required this.id,
    required this.label,
    required this.subject,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.priority = PhoneIconPriority.p1,
    this.routeHint,
  });

  /// 可选贴图路径（非主路径）
  String get assetWebp => 'assets/phone_icons/generated/$id.webp';
  String get assetPng => 'assets/phone_icons/generated/$id.png';
}

enum PhoneIconPriority { p0, p1, p2 }

/// 全量图标清单（桌面网格 + Dock 共用）
class PhoneAppIconCatalog {
  PhoneAppIconCatalog._();

  static const List<PhoneAppIconDef> all = [
    // ── Dock / 核心 ──
    PhoneAppIconDef(
      id: 'phone',
      label: '电话',
      subject: 'glossy green handset, soft 3D',
      fallbackIcon: Icons.phone_rounded,
      fallbackColor: Color(0xFF34C759),
      priority: PhoneIconPriority.p0,
      routeHint: 'voice_call',
    ),
    PhoneAppIconDef(
      id: 'chat',
      label: '消息',
      subject: 'pastel green speech bubbles, soft rounded',
      fallbackIcon: Icons.chat_bubble_rounded,
      fallbackColor: Color(0xFF34C759),
      priority: PhoneIconPriority.p0,
      routeHint: 'chat_list',
    ),
    PhoneAppIconDef(
      id: 'contacts',
      label: '通讯录',
      subject: 'soft blue address book with two people silhouettes',
      fallbackIcon: Icons.contacts_rounded,
      fallbackColor: Color(0xFF007AFF),
      priority: PhoneIconPriority.p0,
      routeHint: 'contacts',
    ),
    PhoneAppIconDef(
      id: 'settings',
      label: '设置',
      subject: 'silver frosted gear',
      fallbackIcon: Icons.settings_rounded,
      fallbackColor: Color(0xFF8E8E93),
      priority: PhoneIconPriority.p0,
      routeHint: 'settings',
    ),

    // ── 桌面 P0 ──
    PhoneAppIconDef(
      id: 'memory',
      label: '纪念回忆',
      subject: 'pink calendar with heart',
      fallbackIcon: Icons.favorite_rounded,
      fallbackColor: Color(0xFFFF6B8A),
      priority: PhoneIconPriority.p0,
      routeHint: 'memory',
    ),
    PhoneAppIconDef(
      id: 'wallet',
      label: '钱包',
      subject: 'green money bag soft dollar shape no text',
      fallbackIcon: Icons.account_balance_wallet_rounded,
      fallbackColor: Color(0xFF34C759),
      priority: PhoneIconPriority.p0,
      routeHint: 'wallet',
    ),
    PhoneAppIconDef(
      id: 'shop',
      label: '拾光购物',
      subject: 'pink shopping bag with heart',
      fallbackIcon: Icons.shopping_bag_rounded,
      fallbackColor: Color(0xFFFF8FB8),
      priority: PhoneIconPriority.p0,
      routeHint: 'shop',
    ),
    PhoneAppIconDef(
      id: 'diary',
      label: '秘密日记本',
      subject: 'pastel illustrated diary with flower garden',
      fallbackIcon: Icons.menu_book_rounded,
      fallbackColor: Color(0xFFFFB7C5),
      priority: PhoneIconPriority.p0,
      routeHint: 'ai_diary',
    ),
    PhoneAppIconDef(
      id: 'moments',
      label: '动态',
      subject: 'pink camera social feed card',
      fallbackIcon: Icons.dynamic_feed_rounded,
      fallbackColor: Color(0xFFFF2D55),
      priority: PhoneIconPriority.p0,
      routeHint: 'moments',
    ),
    PhoneAppIconDef(
      id: 'notes',
      label: '备忘录',
      subject: 'yellow sticky notes stack',
      fallbackIcon: Icons.sticky_note_2_rounded,
      fallbackColor: Color(0xFFFFC300),
      priority: PhoneIconPriority.p0,
      routeHint: 'notes',
    ),

    // ── 桌面 P1 ──
    PhoneAppIconDef(
      id: 'forum',
      label: '论坛',
      subject: 'blue community people bubbles',
      fallbackIcon: Icons.forum_rounded,
      fallbackColor: Color(0xFF5AC8FA),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'inspiration',
      label: '灵感',
      subject: 'glowing lightbulb warm yellow',
      fallbackIcon: Icons.lightbulb_rounded,
      fallbackColor: Color(0xFFFF9F0A),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'guide',
      label: 'Shine指南',
      subject: 'pink book with sparkle no brand text',
      fallbackIcon: Icons.auto_stories_rounded,
      fallbackColor: Color(0xFFFF2D55),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'store',
      label: '应用商店',
      subject: 'gradient circle with three soft dots',
      fallbackIcon: Icons.apps_rounded,
      fallbackColor: Color(0xFFAF52DE),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'calendar',
      label: '小月历',
      subject: 'peach calendar with flower',
      fallbackIcon: Icons.calendar_month_rounded,
      fallbackColor: Color(0xFFFFD60A),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'oracle',
      label: '求签',
      subject: 'cute oriental fortune tube soft 3D',
      fallbackIcon: Icons.temple_buddhist_rounded,
      fallbackColor: Color(0xFFE8D5B7),
      priority: PhoneIconPriority.p1,
      routeHint: 'tarot',
    ),
    PhoneAppIconDef(
      id: 'coins',
      label: '有钱花',
      subject: 'teal coins stack upward arrow',
      fallbackIcon: Icons.savings_rounded,
      fallbackColor: Color(0xFF00C7BE),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'destiny',
      label: '命运之书',
      subject: 'dark blue magical open book stardust',
      fallbackIcon: Icons.auto_awesome_rounded,
      fallbackColor: Color(0xFF5856D6),
      priority: PhoneIconPriority.p1,
      routeHint: 'story',
    ),
    PhoneAppIconDef(
      id: 'reading',
      label: '灵犀共读',
      subject: 'pink open book with two hearts',
      fallbackIcon: Icons.menu_book_outlined,
      fallbackColor: Color(0xFFFF9ECB),
      priority: PhoneIconPriority.p1,
      routeHint: 'novel',
    ),
    PhoneAppIconDef(
      id: 'love_sign',
      label: '每日恋爱签',
      subject: 'pink cup with fortune sticks and hearts',
      fallbackIcon: Icons.local_cafe_rounded,
      fallbackColor: Color(0xFFFFB6C1),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'love_lab',
      label: '恋爱人格研',
      subject: 'pink chemistry flask with heart liquid',
      fallbackIcon: Icons.science_rounded,
      fallbackColor: Color(0xFFFF7A9C),
      priority: PhoneIconPriority.p1,
    ),
    PhoneAppIconDef(
      id: 'power',
      label: '关闭手机',
      subject: 'soft red power button',
      fallbackIcon: Icons.power_settings_new_rounded,
      fallbackColor: Color(0xFFFF3B30),
      priority: PhoneIconPriority.p1,
      routeHint: 'exit_shell',
    ),
    PhoneAppIconDef(
      id: 'tarot',
      label: '塔罗',
      subject: 'mystical tarot card soft 3D',
      fallbackIcon: Icons.style_rounded,
      fallbackColor: Color(0xFF9B59B6),
      priority: PhoneIconPriority.p1,
      routeHint: 'tarot',
    ),
    PhoneAppIconDef(
      id: 'music',
      label: '音乐陪伴',
      subject: 'pastel headphones music note jelly',
      fallbackIcon: Icons.headphones_rounded,
      fallbackColor: Color(0xFF64D2FF),
      priority: PhoneIconPriority.p1,
      routeHint: 'music',
    ),
    PhoneAppIconDef(
      id: 'story',
      label: '故事',
      subject: 'storybook with starry cover',
      fallbackIcon: Icons.book_rounded,
      fallbackColor: Color(0xFF7D5FFF),
      priority: PhoneIconPriority.p1,
      routeHint: 'story',
    ),
    PhoneAppIconDef(
      id: 'mailbox',
      label: '信箱',
      subject: 'pink envelope with heart seal',
      fallbackIcon: Icons.mail_rounded,
      fallbackColor: Color(0xFFFF8FAB),
      priority: PhoneIconPriority.p1,
      routeHint: 'mailbox',
    ),

    // ── P2 ──
    PhoneAppIconDef(
      id: 'map',
      label: '地图',
      subject: 'soft folded map pin',
      fallbackIcon: Icons.map_rounded,
      fallbackColor: Color(0xFF30B0C7),
      priority: PhoneIconPriority.p2,
    ),
  ];

  static PhoneAppIconDef? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }

  static List<PhoneAppIconDef> byPriority(PhoneIconPriority p) =>
      all.where((e) => e.priority == p).toList();

  /// 桌面网格：仅放真实可进功能，弱入口不占首屏
  static const List<String> homePage1Ids = [
    'memory',
    'diary',
    'wallet',
    'shop',
    'moments',
    'mailbox',
    'oracle',
    'music',
    'destiny',
    'reading',
    'calendar',
    'inspiration',
  ];

  /// 第二页：扩展 + 系统
  static const List<String> homePage2Ids = [
    'story',
    'tarot',
    'coins',
    'guide',
    'store',
    'forum',
    'love_sign',
    'love_lab',
    'notes',
    'power',
  ];

  /// 兼容旧引用
  static const List<String> defaultHomeGridIds = homePage1Ids;

  static List<List<String>> get homePages => [homePage1Ids, homePage2Ids];

  /// 底部 Dock
  static const List<String> defaultDockIds = [
    'phone',
    'contacts',
    'chat',
    'settings',
  ];

  /// 首屏 NEW 标签
  static const Set<String> newBadgeIds = {
    'diary',
    'destiny',
    'music',
  };

  /// 生成可直接粘贴给 AI 的完整 prompt
  static String buildAiPrompt(PhoneAppIconDef def) {
    return '''
App icon asset, single centered 3D soft clay / glassmorphism object: ${def.subject}.
Pastel candy colors, glossy plastic and frosted glass materials, cute but premium.
Soft studio lighting from top-left, gentle ambient occlusion, subtle drop shadow under object.
Centered composition, large clear silhouette, no text, no letters, no numbers, no logo watermark.
Transparent background, PNG, 1024x1024, mobile UI icon, high detail, clean edges.
Style reference: iOS 3D soft UI icons, macaron palette, sky-blue friendly mood.

File name must be: ${def.id}.png
''';
  }
}
