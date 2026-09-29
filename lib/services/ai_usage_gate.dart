import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';

/// AI Token 消耗功能位（设置页与调用点共用）
class AiUsageFeature {
  const AiUsageFeature._();

  static const letter = 'letter';
  static const momentPost = 'momentPost';
  static const commentReply = 'commentReply';
  static const momentInteract = 'momentInteract';
  static const wechatPoll = 'wechatPoll';
  static const proactiveChat = 'proactiveChat';
  static const memoryExtract = 'memoryExtract';
  static const rollingSummary = 'rollingSummary';
  static const diary = 'diary';
  static const reflection = 'reflection';
  static const personaEvolution = 'personaEvolution';
  static const proactiveDecision = 'proactiveDecision';
  static const games = 'games';
  static const virtualPhone = 'virtualPhone';
  static const memoryRebuild = 'memoryRebuild';
}

const Map<String, String> _featurePrefKey = {
  AiUsageFeature.letter: PrefKeys.aiUsageLetter,
  AiUsageFeature.momentPost: PrefKeys.aiUsageMomentPost,
  AiUsageFeature.commentReply: PrefKeys.aiUsageCommentReply,
  AiUsageFeature.momentInteract: PrefKeys.aiUsageMomentInteract,
  AiUsageFeature.wechatPoll: PrefKeys.aiUsageWechatPoll,
  AiUsageFeature.proactiveChat: PrefKeys.aiUsageProactiveChat,
  AiUsageFeature.memoryExtract: PrefKeys.aiUsageMemoryExtract,
  AiUsageFeature.rollingSummary: PrefKeys.aiUsageRollingSummary,
  AiUsageFeature.diary: PrefKeys.aiUsageDiary,
  AiUsageFeature.reflection: PrefKeys.aiUsageReflection,
  AiUsageFeature.personaEvolution: PrefKeys.aiUsagePersonaEvolution,
  AiUsageFeature.proactiveDecision: PrefKeys.aiUsageProactiveDecision,
  AiUsageFeature.games: PrefKeys.aiUsageGames,
  AiUsageFeature.virtualPhone: PrefKeys.aiUsageVirtualPhone,
  AiUsageFeature.memoryRebuild: PrefKeys.aiUsageMemoryRebuild,
};

/// 全局 AI 消耗闸门。默认全开，保持旧行为；用户可在设置里关掉。
class AiUsageGate {
  const AiUsageGate._();

  static bool masterEnabled(LocalStorageRepository storage) {
    return storage.getBool(PrefKeys.aiUsageMaster) ?? true;
  }

  static Future<void> setMaster(
      LocalStorageRepository storage, bool value) async {
    await storage.setBool(PrefKeys.aiUsageMaster, value);
    storage.notifyAiUsageChanged();
  }

  static bool featureEnabled(
      LocalStorageRepository storage, String feature) {
    final key = _featurePrefKey[feature];
    if (key == null) return false;
    return storage.getBool(key) ?? true;
  }

  static Future<void> setFeature(
    LocalStorageRepository storage,
    String feature,
    bool value,
  ) async {
    final key = _featurePrefKey[feature];
    if (key == null) return;
    await storage.setBool(key, value);
    storage.notifyAiUsageChanged();
  }

  /// 是否允许该功能发起 LLM 调用
  static bool allow(
      LocalStorageRepository storage, String feature) {
    if (!masterEnabled(storage)) return false;
    return featureEnabled(storage, feature);
  }
}
