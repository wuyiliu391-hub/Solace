import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_character.dart';
import '../models/pet/pet_character_config.dart';

/// 崽崽角色仓库
///
/// 负责持久化"当前悬浮窗崽崽对应哪个 AI 角色"，以及把 [AICharacter]
/// 转换成 [PetCharacterConfig]。
///
/// 注意：项目里实际使用的角色是 [AICharacter]（存于 ai_characters 表），
/// 通过 [LocalStorageRepository.getAllAICharacters] 读取。
/// 旧版 SillyTavern 风格的 CharacterCardV2（characters 表）已不再使用。
class PetCharacterRepository {
  PetCharacterRepository._();
  static final PetCharacterRepository _instance = PetCharacterRepository._();
  static PetCharacterRepository get instance => _instance;

  static const _keyCurrentPet = 'solace_pet_character_config_v1';

  /// 从 SharedPreferences 读取当前崽崽配置
  Future<PetCharacterConfig> getCurrentPet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCurrentPet);
    if (raw == null || raw.isEmpty) return PetCharacterConfig.empty();
    return PetCharacterConfig.fromRawJson(raw);
  }

  /// 保存当前崽崽配置
  Future<void> setCurrentPet(PetCharacterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentPet, config.toRawJson());
  }

  /// 清空当前崽崽
  Future<void> clearCurrentPet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentPet);
  }

  /// 根据 AICharacter 生成 PetCharacterConfig
  PetCharacterConfig configFromAiCharacter(AICharacter character) {
    final lines = _extractBubbleLines(
      character.openingLine,
      character.catchphrases,
      character.currentStatus,
    );
    return PetCharacterConfig(
      characterId: character.id,
      name: character.name,
      avatarUrl: character.avatarUrl ?? '',
      bubbleLines: lines,
    );
  }

  /// 聚合角色台词池
  List<String> _extractBubbleLines(String? first, String? second,
      [String? third]) {
    final lines = <String>[];
    for (final text in [first, second, third]) {
      if (text == null || text.trim().isEmpty) continue;
      // 支持多行口癖，按换行/逗号分句
      final parts = text
          .split(RegExp(r'[，,。！!?？\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length <= 32)
          .toList();
      lines.addAll(parts);
    }
    if (lines.isEmpty) {
      return ['我在这里哦～'];
    }
    return lines.toSet().toList();
  }
}
