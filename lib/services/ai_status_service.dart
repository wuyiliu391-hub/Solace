import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/chat_session.dart';
import '../repositories/local_storage_repository.dart';

/// AI 在线状态服务 — 管理角色在线/离线状态与最后活跃时间
class AIStatusService {
  final LocalStorageRepository _storage;

  AIStatusService(this._storage);

  /// 获取当前用户 ID
  Future<String> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(PrefKeys.currentUserId) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 判断会话是否在线：当前在线且最近 30 分钟内有活动
  static bool isOnlineFromSession(ChatSession session) {
    if (!session.aiIsOnline) return false;
    final lastOnline = session.lastOnlineAt;
    if (lastOnline == null) return true; // 无记录默认在线
    return DateTime.now().difference(lastOnline).inMinutes < 30;
  }

  /// 设置页同款展示文案：在线 · 自定义状态 / 离线 · 自定义状态
  static String displayStatusFromSession(ChatSession session) {
    final custom = session.aiCurrentStatus?.trim();
    final hasCustom = custom != null && custom.isNotEmpty;
    if (isOnlineFromSession(session)) {
      return hasCustom ? '在线 · $custom' : '在线';
    }
    return hasCustom ? '离线 · $custom' : '离线';
  }

  /// 更新角色在线状态（持久化到所有相关会话）
  Future<void> updateCharacterStatus({
    required String characterId,
    required bool isOnline,
    String? currentStatus,
  }) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId.isEmpty) return;

      final sessions = await _storage.getChatSessions(userId);
      final matchingSessions = sessions
          .where((s) => s.aiCharacterId == characterId)
          .toList();

      for (final session in matchingSessions) {
        final updated = session.copyWith(
          aiIsOnline: isOnline,
          aiCurrentStatus: currentStatus ?? session.aiCurrentStatus,
          lastOnlineAt: isOnline ? DateTime.now() : session.lastOnlineAt,
        );
        await _storage.saveChatSession(updated);
      }
    } catch (e) {
      // 静默失败，不影响主流程
    }
  }

  /// 标记会话为活跃（用户发送消息或收到 AI 回复时调用）
  Future<void> markSessionActive(String chatId) async {
    try {
      final session = await _storage.getChatSession(chatId);
      if (session == null) return;
      final updated = session.copyWith(
        aiIsOnline: true,
        lastOnlineAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _storage.saveChatSession(updated);
    } catch (e) {
      // 静默失败
    }
  }
}
