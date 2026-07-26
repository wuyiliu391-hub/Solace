import 'package:flutter/material.dart';

/// 抓娃娃机 —— 娃娃池与规则配置。
///
/// 娃娃用 emoji 呈现（与商店同一套风格，免美术素材）。
/// 稀有度决定出现权重与「对准后」的抓取成功率。

enum DollRarity { common, rare, hidden }

extension DollRarityX on DollRarity {
  String get label {
    switch (this) {
      case DollRarity.common:
        return '普通';
      case DollRarity.rare:
        return '稀有';
      case DollRarity.hidden:
        return '隐藏';
    }
  }

  Color get color {
    switch (this) {
      case DollRarity.common:
        return const Color(0xFF9AA0A6);
      case DollRarity.rare:
        return const Color(0xFF1A73E8);
      case DollRarity.hidden:
        return const Color(0xFFF9A825);
    }
  }

  /// 爪子对准娃娃后，真正抓起来的成功率（越稀有越滑手）
  double get catchRate {
    switch (this) {
      case DollRarity.common:
        return 0.62;
      case DollRarity.rare:
        return 0.36;
      case DollRarity.hidden:
        return 0.16;
    }
  }

  /// 出现在机台里的相对权重
  int get spawnWeight {
    switch (this) {
      case DollRarity.common:
        return 60;
      case DollRarity.rare:
        return 30;
      case DollRarity.hidden:
        return 10;
    }
  }
}

/// 一款娃娃的静态定义
@immutable
class ClawDoll {
  final String id;
  final String name;
  final String emoji;
  final DollRarity rarity;

  const ClawDoll(this.id, this.name, this.emoji, this.rarity);
}

class ClawConfig {
  ClawConfig._();

  /// 每次下爪消耗金币
  static const int costPerPlay = 20;

  /// 爪子中心与娃娃中心的水平距离小于此值（0~1 归一化）才算「对准」
  static const double alignThreshold = 0.085;

  /// 机台里同时摆放的娃娃数量
  static const int dollsOnStage = 8;

  /// 娃娃池
  static const List<ClawDoll> pool = [
    // ── 普通 ──
    ClawDoll('bear', '小熊', '🧸', DollRarity.common),
    ClawDoll('rabbit', '兔子', '🐰', DollRarity.common),
    ClawDoll('cat', '猫咪', '🐱', DollRarity.common),
    ClawDoll('dog', '小狗', '🐶', DollRarity.common),
    ClawDoll('hamster', '仓鼠', '🐹', DollRarity.common),
    ClawDoll('chick', '小鸡', '🐤', DollRarity.common),
    ClawDoll('frog', '青蛙', '🐸', DollRarity.common),
    // ── 稀有 ──
    ClawDoll('fox', '狐狸', '🦊', DollRarity.rare),
    ClawDoll('panda', '熊猫', '🐼', DollRarity.rare),
    ClawDoll('koala', '考拉', '🐨', DollRarity.rare),
    ClawDoll('lion', '狮子', '🦁', DollRarity.rare),
    ClawDoll('tiger', '老虎', '🐯', DollRarity.rare),
    ClawDoll('penguin', '企鹅', '🐧', DollRarity.rare),
    // ── 隐藏 ──
    ClawDoll('unicorn', '独角兽', '🦄', DollRarity.hidden),
    ClawDoll('dragon', '龙', '🐉', DollRarity.hidden),
    ClawDoll('alien', '外星宝宝', '👾', DollRarity.hidden),
  ];

  static ClawDoll byId(String id) =>
      pool.firstWhere((d) => d.id == id, orElse: () => pool.first);
}
