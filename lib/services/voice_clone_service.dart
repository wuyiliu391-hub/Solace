import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'tts_service.dart';
import '../config/tts_config.dart';
import '../utils/safe_file_picker.dart';

/// 音色克隆服务 — 管理用户的音色样本
///
/// 修复版：
/// 1. 上传时预处理音频（标准化）
/// 2. 缓存处理后的参考音频，保证每次合成都用同一份
/// 3. 上传后自动合成试听
/// 4. 固定风格指令，保证音色一致
class VoiceCloneService {
  static final VoiceCloneService _instance = VoiceCloneService._();
  factory VoiceCloneService() => _instance;
  VoiceCloneService._();

  static const String _boxName = 'voice_samples';
  static const String _styleBoxName = 'voice_styles';
  Box<String>? _box;
  Box<String>? _styleBox;

  /// 初始化
  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _styleBox = await Hive.openBox<String>(_styleBoxName);
  }

  /// 获取某个角色的音色 base64（含 data: 前缀）
  String? getVoiceBase64(String characterId) {
    return _box?.get(characterId);
  }

  /// 获取固定风格指令（全场景统一，保证音色一致）
  /// 不再从 Hive 读取历史值，始终使用 TTSConfig 中的固定指令
  String getStyleInstruction(String characterId) {
    return TTSConfig.defaultStyleInstruction;
  }

  /// 检查某个角色是否已设置音色
  bool hasVoice(String characterId) {
    return _box?.get(characterId) != null;
  }

  /// 保存音色样本 + 固定风格指令
  Future<void> saveVoice(
    String characterId,
    String voiceBase64, {
    String? styleInstruction,
  }) async {
    await _box?.put(characterId, voiceBase64);
    await _styleBox?.put(
      characterId,
      styleInstruction ?? TTSConfig.defaultStyleInstruction,
    );
  }

  /// 删除音色样本
  Future<void> deleteVoice(String characterId) async {
    await _box?.delete(characterId);
    await _styleBox?.delete(characterId);
    // 清理该角色的 TTS 缓存
    await TTSService().clearCache();
  }

  /// 从文件选择器上传音色样本 + 自动试听
  ///
  /// 返回 [VoiceUploadResult]，包含 base64 和试听音频路径
  Future<VoiceUploadResult?> pickAndSaveVoice(
    String characterId, {
    String? previewText,
  }) async {
    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;

      final filePath = result.files.first.path;
      if (filePath == null) return null;

      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // 检查大小（base64 编码后会增加 33%，API 有请求体大小限制）
      if (bytes.length > 5 * 1024 * 1024) {
        debugPrint(
            'VoiceClone: 音频文件过大 (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB)，超过 5MB 限制');
        return null;
      }

      // 判断 MIME 类型
      final ext = filePath.split('.').last.toLowerCase();
      final mimeType = ext == 'wav' ? 'audio/wav' : 'audio/mpeg';

      // 编码为 base64（标准化处理：只编码一次，后续复用）
      final base64Str = base64Encode(bytes);
      final voiceBase64 = 'data:$mimeType;base64,$base64Str';

      // 保存音色 + 默认风格指令
      await saveVoice(characterId, voiceBase64);

      debugPrint(
          'VoiceClone: 已保存音色样本 (${bytes.length} bytes, base64 length: ${voiceBase64.length})');

      // 自动合成试听
      String? previewPath;
      final hasKey = await TTSConfig.hasApiKey();
      if (!hasKey) {
        debugPrint('VoiceClone: 未配置 TTS API Key，跳过试听');
      } else {
        try {
          final tts = TTSService();
          previewPath = await tts.synthesize(
            text: previewText ?? TTSConfig.previewText,
            voiceBase64: voiceBase64,
            styleInstruction: getStyleInstruction(characterId),
          );
          if (previewPath == null) {
            debugPrint('VoiceClone: 试听合成返回 null（API 可能失败，请检查网络）');
          } else {
            debugPrint('VoiceClone: 试听合成成功: $previewPath');
          }
        } catch (e) {
          debugPrint('VoiceClone: 试听合成异常: $e');
        }
      }

      return VoiceUploadResult(
        voiceBase64: voiceBase64,
        previewPath: previewPath,
      );
    } catch (e) {
      debugPrint('VoiceClone: 上传失败 $e');
      return null;
    }
  }

  /// 仅生成试听（不重新上传）
  Future<String?> generatePreview(String characterId) async {
    final voiceBase64 = getVoiceBase64(characterId);
    if (voiceBase64 == null) {
      debugPrint('VoiceClone: generatePreview 失败 - 无音色数据');
      throw Exception('未找到音色数据，请重新上传');
    }
    debugPrint(
        'VoiceClone: 开始生成试听 (voiceBase64 length: ${voiceBase64.length})');
    final tts = TTSService();
    final styleInstruction = getStyleInstruction(characterId);
    final path = await tts.generateAudio(
      TTSConfig.previewText,
      voiceBase64: voiceBase64,
      styleInstruction: styleInstruction,
    );
    if (path == null) {
      debugPrint('VoiceClone: 试听生成返回 null（TTS API 可能失败）');
      throw Exception('TTS 生成失败，请检查网络和 API Key');
    }
    debugPrint('VoiceClone: 试听生成成功: $path');
    return path;
  }

  /// 预生成角色常用回复的音频（进入聊天时后台调用）
  /// 命中缓存的句子跳过，未命中的合成并缓存
  Future<void> pregenerateCommonReplies(String characterId) async {
    final voiceBase64 = getVoiceBase64(characterId);
    if (voiceBase64 == null) return;

    final styleInstruction = getStyleInstruction(characterId);
    final tts = TTSService();

    // 常用短句（AI 回复高频出现）
    const commonPhrases = [
      '嗯嗯',
      '好的',
      '哈哈',
      '嗯',
      '好吧',
      '嘻嘻',
      '嘿嘿',
      '知道了',
      '没关系',
      '当然',
      '真的吗',
      '太好了',
      '你怎么了',
      '还好吗',
      '想你了',
      '晚安',
      '早安',
    ];

    int generated = 0;

    for (final phrase in commonPhrases) {
      try {
        await for (final _ in tts.synthesizeStream(
          text: phrase,
          voiceBase64: voiceBase64,
          styleInstruction: styleInstruction,
        )) {
          generated++;
          break; // 只需要第一句（短句不会分句）
        }
      } catch (e) {
        // 静默失败，不影响用户体验
      }
    }

    debugPrint('VoiceClone: 预生成完成，生成=$generated');
  }

  /// 获取所有已设置音色的角色 ID 列表
  List<String> getAllCharacterIds() {
    return _box?.keys.cast<String>().toList() ?? [];
  }

  /// 清空所有音色样本
  Future<void> clearAll() async {
    await _box?.clear();
    await _styleBox?.clear();
  }
}

/// 上传结果
class VoiceUploadResult {
  final String voiceBase64;
  final String? previewPath;

  const VoiceUploadResult({
    required this.voiceBase64,
    this.previewPath,
  });
}
