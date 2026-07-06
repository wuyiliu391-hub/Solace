import 'package:flutter/foundation.dart';
import '../models/ai_character.dart';
import '../models/chat_session.dart';
import '../repositories/local_storage_repository.dart';

class AIStatusService {
  final LocalStorageRepository _storage;

  AIStatusService(this._storage);

  static const _statusPattern = r'\[STATUS\](.*?)\[/STATUS\]';

  String? parseStatusFromResponse(String response) {
    try {
      final regex = RegExp(_statusPattern, dotAll: true);
      final match = regex.firstMatch(response);
      if (match != null) {
        return match.group(1)?.trim();
      }
    } catch (e) {
      debugPrint('解析状态标记失败: $e');
    }
    return null;
  }

  String removeStatusMarkers(String response) {
    return response.replaceAll(RegExp(_statusPattern, dotAll: true), '').trim();
  }

  Future<void> updateCharacterStatus({
    required String characterId,
    bool? isOnline,
    String? currentStatus,
  }) async {
    try {
      final character = await _storage.getAICharacter(characterId);
      if (character == null) return;

      final now = DateTime.now();
      final updated = character.copyWith(
        isOnline: isOnline ?? character.isOnline,
        currentStatus: currentStatus ?? character.currentStatus,
        lastOnlineAt: now,
        updatedAt: now,
      );
      await _storage.saveAICharacter(updated);

      final sessions = await _storage.getChatSessionsByCharacterId(characterId);
      for (final session in sessions) {
        final updatedSession = session.copyWith(
          aiIsOnline: updated.isOnline,
          aiCurrentStatus: updated.currentStatus,
          updatedAt: now,
        );
        await _storage.saveChatSession(updatedSession);
      }

      debugPrint('[OK] [AI状态] 更新成功: ${updated.name} → ${isOnline == true ? "在线" : "离线"} ${currentStatus ?? ""}');
    } catch (e) {
      debugPrint('[ERR] [AI状态] 更新失败: $e');
    }
  }

  Future<void> syncSessionStatus(ChatSession session) async {
    try {
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) return;

      if (character.isOnline != session.aiIsOnline ||
          character.currentStatus != session.aiCurrentStatus) {
        final updated = session.copyWith(
          aiIsOnline: character.isOnline,
          aiCurrentStatus: character.currentStatus,
        );
        await _storage.saveChatSession(updated);
      }
    } catch (e) {
      debugPrint('[ERR] [AI状态] 同步会话状态失败: $e');
    }
  }

  static String getDisplayStatus(AICharacter character) {
    final status = character.currentStatus;
    if (!character.isOnline) {
      if ((status?.isNotEmpty) == true) {
        return status!;
      }
      return '离线';
    }
    if ((status?.isNotEmpty) == true) {
      return status!;
    }
    return '在呢';
  }

  static String getDisplayStatusFromSession(ChatSession session) {
    final s = session.aiCurrentStatus;
    if (!session.aiIsOnline) {
      if ((s?.isNotEmpty) == true) {
        return s!;
      }
      return '离线';
    }
    if ((s?.isNotEmpty) == true) {
      return s!;
    }
    return '在呢';
  }

  static bool isOnlineFromSession(ChatSession session) {
    return session.aiIsOnline;
  }
}