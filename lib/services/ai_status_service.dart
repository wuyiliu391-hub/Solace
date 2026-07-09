import '../models/chat_session.dart';
import '../repositories/local_storage_repository.dart';

class AIStatusService {
  final LocalStorageRepository _storage;

  AIStatusService(this._storage);

  static bool isOnlineFromSession(ChatSession session) {
    return true;
  }

  Future<void> updateCharacterStatus({
    required String characterId,
    required bool isOnline,
    String? currentStatus,
  }) async {
    // stub — 原模块已删除
  }
}