import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/character_image.dart';
import '../repositories/local_storage_repository.dart';
import 'agnes_image_service.dart';
import 'character_image_prompt_engine.dart';
import 'prompt_sanitizer.dart';
/// 角色一致性生图全链路编排器
///
/// 职责：读取角色信息 → 读取聊天记录 → 生成精准 prompt →
///       锚定人物形象 → 调用模型出图 → 返回本地路径 → 归档到画廊
///
/// 对标 CandyAI 核心图像方案：角色身份锚定 + 对话记忆驱动场景生成 + 固定画风渲染
class CharacterImagePipeline {
  static final CharacterImagePipeline _instance = CharacterImagePipeline._();
  factory CharacterImagePipeline() => _instance;
  CharacterImagePipeline._();

  final _uuid = const Uuid();
  final _agnesService = AgnesImageService();
  CharacterImagePromptEngine? _promptEngine;

  /// 注入 LLM 服务以启用智能 Prompt 翻译
  void setLlmService(dynamic llmService) {
    _promptEngine = CharacterImagePromptEngine(llmService: llmService);
  }

  /// 检测 API 错误是否为内容安全拒绝（HTTP 400 + 内容相关错误信息）
  static bool _isContentRejected(String? errorMessage) {
    if (errorMessage == null) return false;
    final lower = errorMessage.toLowerCase();
    return lower.contains('400') ||
        lower.contains('content') && lower.contains('not') ||
        lower.contains('safety') ||
        lower.contains('policy') ||
        lower.contains('违规') ||
        lower.contains('不允许') ||
        lower.contains('露骨') ||
        lower.contains('未成年');
  }

  /// 执行完整生图链路
  ///
  /// [character] 目标角色
  /// [recentMessages] 最近对话记录
  /// [userInstruction] 用户当前场景需求（可选，为空时自动从对话推导）
  /// [userId] 当前用户 ID
  ///
  /// 返回 [CharacterImagePipelineResult]
  Future<CharacterImagePipelineResult> generate({
    required AICharacter character,
    required List<ChatMessage> recentMessages,
    String? userInstruction,
    required String userId,
  }) async {
    final startTime = DateTime.now();
    debugPrint('[Pipeline] === 开始全链路生图 ===');
    debugPrint('[Pipeline] 角色: ${character.name} | 画风: ${character.styleLock} | 性别: ${character.gender}');

    try {
      // ── 阶段0：内容安全检测 ──
      debugPrint('[Pipeline] 阶段0: 内容安全检测...');
      final isAdult = PromptSanitizer.isAdultCharacter(
        character.characterTag,
        character.personality,
        character.backgroundStory,
      );

      // 检测用户指令和对话中的露骨内容
      final instructionRaw = userInstruction ?? '根据当前对话剧情生成角色场景画面';
      final chatText = recentMessages.map((m) => m.content).join(' ');
      final hasExplicit = PromptSanitizer.containsExplicitContent('$instructionRaw $chatText');

      String safeInstruction;
      if (isAdult || hasExplicit) {
        debugPrint('[Pipeline] ⚠️ 检测到成人向内容 | 角色标记: $isAdult | 露骨内容: $hasExplicit');
        debugPrint('[Pipeline] 自动转为合规场景...');
        safeInstruction = PromptSanitizer.toSafeScene(
          originalInstruction: instructionRaw,
          gender: character.gender ?? 'female',
          characterTag: character.characterTag,
        );
        debugPrint('[Pipeline] 合规场景: $safeInstruction');
      } else {
        safeInstruction = instructionRaw;
      }

      // ── 阶段1：构建 Prompt ──
      debugPrint('[Pipeline] 阶段1: 构建 Prompt...');
      _promptEngine ??= CharacterImagePromptEngine();
      final prompt = await _promptEngine!.buildPrompt(
        character: character,
        recentMessages: recentMessages,
        userInstruction: safeInstruction,
      );

      // ── 阶段2：二次脱敏检查 ──
      final sanitizedPrompt = PromptSanitizer.sanitize(
        prompt: prompt,
        level: PromptSafetyLevel.standard,
      );
      if (sanitizedPrompt != prompt) {
        debugPrint('[Pipeline] 脱敏引擎替换了敏感词');
      }

      // ── 阶段3：调用生图 ──
      debugPrint('[Pipeline] 阶段3: 调用生图...');
      AgnesImageResult result;

      if (character.referenceImg != null && character.referenceImg!.isNotEmpty) {
        // 图生图模式：用角色立绘锚定五官
        debugPrint('[Pipeline] 使用图生图模式，参考图: ${character.referenceImg}');
        result = await _agnesService.imageToImage(
          sourceImagePath: character.referenceImg!,
          prompt: sanitizedPrompt,
          characterName: character.name,
        );
      } else {
        // 文生图模式（无参考图时）
        debugPrint('[Pipeline] 使用文生图模式（无参考图）');
        result = await _agnesService.textToImage(
          prompt: sanitizedPrompt,
          characterName: character.name,
        );
      }

      // ── 阶段3.5：400 错误自动降级重试 ──
      if (!result.isSuccess && _isContentRejected(result.errorMessage)) {
        debugPrint('[Pipeline] API 拒绝内容，自动降级为安全场景重试...');
        final fallbackInstruction = PromptSanitizer.toSafeScene(
          originalInstruction: '角色日常肖像',
          gender: character.gender ?? 'female',
          characterTag: character.characterTag,
        );
        final fallbackPrompt = await _promptEngine!.buildPrompt(
          character: character,
          recentMessages: [],
          userInstruction: fallbackInstruction,
        );
        final safePrompt = PromptSanitizer.sanitize(
          prompt: fallbackPrompt,
          level: PromptSafetyLevel.standard,
        );

        if (character.referenceImg != null && character.referenceImg!.isNotEmpty) {
          result = await _agnesService.imageToImage(
            sourceImagePath: character.referenceImg!,
            prompt: safePrompt,
            characterName: character.name,
          );
        } else {
          result = await _agnesService.textToImage(
            prompt: safePrompt,
            characterName: character.name,
          );
        }
        if (result.isSuccess) {
          debugPrint('[Pipeline] ✅ 安全降级重试成功');
        }
      }

      if (!result.isSuccess) {
        debugPrint('[Pipeline] 生图失败: ${result.errorMessage}');
        return CharacterImagePipelineResult.failure(result.errorMessage ?? '未知错误');
      }

      // ── 阶段4：归档到角色画廊 ──
      debugPrint('[Pipeline] 阶段4: 归档到画廊...');
      final image = CharacterImage(
        id: _uuid.v4(),
        characterId: character.id,
        userId: userId,
        localPath: result.imagePath!,
        promptUsed: sanitizedPrompt,
        sceneDescription: safeInstruction,
        referenceImagePath: character.referenceImg,
        generationSeed: character.fixedSeed > 0 ? character.fixedSeed : -1,
        styleLock: character.styleLock,
        createdAt: DateTime.now(),
      );

      try {
        final repo = LocalStorageRepository();
        await repo.insertCharacterImage(image.toMap());
      } catch (e) {
        debugPrint('[Pipeline] 画廊归档失败（不影响主流程）: $e');
      }

      final elapsed = DateTime.now().difference(startTime);
      debugPrint('[Pipeline] === 全链路完成 | 耗时: ${elapsed.inSeconds}s ===');

      return CharacterImagePipelineResult.success(
        imagePath: result.imagePath!,
        prompt: sanitizedPrompt,
        image: image,
      );
    } catch (e, stack) {
      debugPrint('[Pipeline] 异常: $e');
      debugPrint('[Pipeline] 堆栈: $stack');
      return CharacterImagePipelineResult.failure('生成失败: $e');
    }
  }
}

/// Pipeline 执行结果
class CharacterImagePipelineResult {
  final bool isSuccess;
  final String? imagePath;
  final String? prompt;
  final CharacterImage? image;
  final String? errorMessage;

  const CharacterImagePipelineResult._({
    required this.isSuccess,
    this.imagePath,
    this.prompt,
    this.image,
    this.errorMessage,
  });

  factory CharacterImagePipelineResult.success({
    required String imagePath,
    required String prompt,
    required CharacterImage image,
  }) {
    return CharacterImagePipelineResult._(
      isSuccess: true,
      imagePath: imagePath,
      prompt: prompt,
      image: image,
    );
  }

  factory CharacterImagePipelineResult.failure(String message) {
    return CharacterImagePipelineResult._(
      isSuccess: false,
      errorMessage: message,
    );
  }
}