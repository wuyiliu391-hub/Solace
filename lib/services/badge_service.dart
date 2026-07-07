import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/local_storage_repository.dart';

/// 统一未读角标服务
///
/// 管理所有功能的未读数量，支持监听变化
/// 数据来源：DB 查询 + SharedPreferences 手动设置
class BadgeService {
  final LocalStorageRepository _storage;
  final _controller = StreamController<void>.broadcast();
  final Map<String, int> _badges = {};

  BadgeService(this._storage);

  Stream<void> get onBadgeChanged => _controller.stream;

  int getBadge(String appId) => _badges[appId] ?? 0;

  void setBadge(String appId, int count) {
    _badges[appId] = count.clamp(0, 99);
    _controller.add(null);
  }

  void clearBadge(String appId) {
    _badges.remove(appId);
    _controller.add(null);
  }

  /// 手动增加角标（用于推送通知等场景）
  void incrementBadge(String appId, [int delta = 1]) {
    _badges[appId] = ((getBadge(appId) + delta)).clamp(0, 99);
    _controller.add(null);
  }

  // ─── 从 DB 加载 ───

  /// 聊天未读数
  Future<void> loadChatBadges(String userId) async {
    try {
      final sessions = await _storage.getChatSessions(userId);
      int totalUnread = 0;
      for (final session in sessions) {
        totalUnread += session.unreadCount;
      }
      setBadge('chat_list', totalUnread);
      setBadge('chat_list_dock', totalUnread);
    } catch (e) {
      debugPrint('BadgeService: loadChatBadges failed: $e');
    }
  }

  /// 商店活跃订单数
  Future<void> loadShopBadges() async {
    try {
      final activeOrders = await _storage.getActiveOrders();
      setBadge('shop', activeOrders.length);
    } catch (e) {
      debugPrint('BadgeService: loadShopBadges failed: $e');
    }
  }

  /// 设置页：是否有可用更新
  Future<void> loadSettingsBadges() async {
    try {
      final availableBuild = _storage.getUpdateAvailableBuild();
      if (availableBuild != null && availableBuild > 0) {
        setBadge('settings', 1);
      }
    } catch (e) {
      debugPrint('BadgeService: loadSettingsBadges failed: $e');
    }
  }

  // ─── 手动设置（基于 SharedPreferences） ───

  /// 标记功能有新内容（如朋友圈有新动态）
  Future<void> markHasNew(String appId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('badge_new_$appId', true);
      setBadge(appId, getBadge(appId) + 1);
    } catch (e) {
      debugPrint('BadgeService: markHasNew failed: $e');
    }
  }

  /// 清除功能的新内容标记
  Future<void> clearHasNew(String appId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('badge_new_$appId');
      clearBadge(appId);
    } catch (e) {
      debugPrint('BadgeService: clearHasNew failed: $e');
    }
  }

  /// 从 SharedPreferences 恢复手动设置的角标
  Future<void> _loadManualBadges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final manualApps = [
        'contacts', 'ai_assistant', 'memory', 'moments',
        'growth', 'daily', 'map',
      ];
      for (final appId in manualApps) {
        if (prefs.getBool('badge_new_$appId') == true) {
          // 保留已有角标值，不覆盖
          _badges[appId] = _badges[appId] ?? 1;
        }
      }
    } catch (e) {
      debugPrint('BadgeService: _loadManualBadges failed: $e');
    }
  }

  /// 加载全部角标
  Future<void> loadAll(String userId) async {
    await Future.wait([
      loadChatBadges(userId),
      loadShopBadges(),
      loadSettingsBadges(),
      _loadManualBadges(),
    ]);
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}
