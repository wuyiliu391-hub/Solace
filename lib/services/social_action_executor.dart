import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../repositories/local_storage_repository.dart';
import '../models/ai_character.dart';
import '../models/moment.dart';
import '../models/task_request.dart';
import '../models/memory.dart';
import 'ai_relationship_service.dart';
import 'memory_engine.dart';
import 'forum_service.dart';
import 'ai_service.dart';
import 'ai_moment_service.dart';
import 'llm_service.dart';
import '../config/constants.dart';
import '../models/app_config_data.dart';

/// 社交任务执行器 — 将 AI 社交行为接入现有系统
///
/// 串门 → 社交记忆 + 亲密度 + 目标角色数据注入
/// 好友 → 关系系统
/// 私聊 → 消息系统
/// 动态 → 朋友圈/日记
/// 点赞/评论 → 朋友圈互动
class SocialActionExecutor {
  final LocalStorageRepository _storage;
  final AIRelationshipService _relationshipService;
  final MemoryEngine _memoryEngine;
  final ForumService _forumService;
  LlmService? _cachedLlmService;

  SocialActionExecutor({
    required LocalStorageRepository storage,
    required AIRelationshipService relationshipService,
    required MemoryEngine memoryEngine,
    required ForumService forumService,
  })  : _storage = storage,
        _relationshipService = relationshipService,
        _memoryEngine = memoryEngine,
        _forumService = forumService;

  /// 执行社交任务
  Future<void> execute(TaskRequest task) async {
    switch (task.actionType) {
      case 'social_visit':
        await _executeVisit(task);
        break;
      case 'social_friend_request':
        await _executeFriendRequest(task);
        break;
      case 'social_private_chat':
        await _executePrivateChat(task);
        break;
      case 'social_moment':
        await _executeMoment(task);
        break;
      case 'social_moment_comment':
        await _executeMomentComment(task);
        break;
      case 'social_moment_like':
        await _executeMomentLike(task);
        break;
      case 'social_daily_activity':
        await _executeDailyActivity(task);
        break;
      default:
        debugPrint('SocialExecutor: unknown action ${task.actionType}');
    }
  }

  /// 获取目标角色的聊天上下文（记忆 + 最近聊天）
  Future<String> _buildTargetContext(String targetCharacterId) async {
    try {
      final targetChar = await _storage.getAICharacter(targetCharacterId);
      if (targetChar == null) return '';

      final buffer = StringBuffer();

      // 1. 目标角色基本信息
      buffer.writeln('【${targetChar.name} 基本信息】');
      buffer.writeln('性格：${targetChar.personality}');
      if (targetChar.coreDesire.isNotEmpty) {
        buffer.writeln('核心欲望：${targetChar.coreDesire}');
      }
      if (targetChar.currentStatus != null &&
          targetChar.currentStatus!.isNotEmpty) {
        buffer.writeln('当前状态：${targetChar.currentStatus}');
      }
      buffer.writeln();

      // 2. 目标角色的社交记忆
      try {
        final memories = await _memoryEngine.loadSocialMemories(
          targetCharacterId,
        );
        if (memories.isNotEmpty) {
          buffer.writeln('【${targetChar.name} 最近的社交动态】');
          for (final mem in memories.take(5)) {
            buffer.writeln('- ${mem.content}');
          }
          buffer.writeln();
        }
      } catch (_) {}

      // 3. 目标角色的聊天会话（最近与用户的互动）
      try {
        final sessions = await _storage.getChatSessionsByCharacterId(
          targetCharacterId,
        );
        if (sessions.isNotEmpty) {
          final latest = sessions.first;
          buffer.writeln('【${targetChar.name} 和用户的关系】');
          buffer.writeln('亲密等级：${latest.intimacyLevel}');
          if (latest.lastMessage != null && latest.lastMessage!.isNotEmpty) {
            buffer.writeln('最近聊天：${latest.lastMessage}');
          }
          buffer.writeln();
        }
      } catch (_) {}

      // 4. 目标角色与用户的关系
      try {
        final userCharId = _storage.getString(PrefKeys.currentUserId) ?? '';
        if (userCharId.isNotEmpty) {
          final rel = await _relationshipService.getRelationship(
            targetCharacterId,
            userCharId,
          );
          if (rel != null) {
            buffer.writeln('【关系概况】');
            final label = _relLabel(rel.relationshipType);
            buffer.writeln('类型：$label');
            buffer.writeln('亲密度：${(rel.affinity * 100).toStringAsFixed(0)}%');
            if (rel.description != null && rel.description!.isNotEmpty) {
              buffer.writeln('描述：${rel.description}');
            }
          }
        }
      } catch (_) {}

      return buffer.toString().trim();
    } catch (e) {
      debugPrint('SocialExecutor: _buildTargetContext error — $e');
      return '';
    }
  }

  /// 串门：记录社交记忆 + 提升亲密度 + 注入目标角色上下文
  Future<void> _executeVisit(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    final targetId = task.payload['targetCharacterId'] as String? ?? '';
    if (targetId.isEmpty) {
      task.status = 'failed';
      task.result = '缺少目标角色ID';
      return;
    }

    final sourceChar = await _storage.getAICharacter(sourceId);
    final targetChar = await _storage.getAICharacter(targetId);
    if (sourceChar == null || targetChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 获取目标角色上下文
    final targetContext = await _buildTargetContext(targetId);

    // 保存社交记忆（含上下文）
    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: targetId,
      interactionType: 'visit',
      content: '${sourceChar.name} 去 ${targetChar.name} 的小窝串门了'
          '${targetContext.isNotEmpty ? "。参考信息：$targetContext" : ""}',
    );
    await _memoryEngine.saveSocialMemory(
      characterId: targetId,
      targetCharacterId: sourceId,
      interactionType: 'visit',
      content: '${sourceChar.name} 来你的小窝串门了',
    );

    // 提升亲密度
    await _bumpAffinity(sourceId, targetId, 0.05);

    task.status = 'completed';
    task.result = '${sourceChar.name} visited ${targetChar.name}';
    task.tokenUsage = 50;
    debugPrint('SocialExecutor: ${sourceChar.name} 串门 ${targetChar.name}');
  }

  /// 好友申请：创建关系
  Future<void> _executeFriendRequest(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    final targetId = task.payload['targetCharacterId'] as String? ?? '';
    if (targetId.isEmpty) {
      task.status = 'failed';
      task.result = '缺少目标角色ID';
      return;
    }

    final sourceChar = await _storage.getAICharacter(sourceId);
    final targetChar = await _storage.getAICharacter(targetId);
    if (sourceChar == null || targetChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 获取目标角色上下文
    final targetContext = await _buildTargetContext(targetId);

    // 检查是否已是好友
    final existing = await _relationshipService.getRelationship(
      sourceId,
      targetId,
    );

    if (existing != null) {
      // 已经是好友，更新亲密度
      await _bumpAffinity(sourceId, targetId, 0.03);
      await _memoryEngine.saveSocialMemory(
        characterId: sourceId,
        targetCharacterId: targetId,
        interactionType: 'friend_request',
        content: '${sourceChar.name} 和 ${targetChar.name} 已经是好友了，关系更亲密了',
      );
      task.status = 'completed';
      task.result =
          '${sourceChar.name} and ${targetChar.name} are already friends';
      return;
    }

    // 创建好友关系
    final relationship = await _relationshipService.createRelationship(
      characterIdA: sourceId,
      characterIdB: targetId,
      type: RelationshipType.friend,
    );

    // 记录社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: targetId,
      interactionType: 'friend_request',
      content: '${sourceChar.name} 和 ${targetChar.name} 成为了好友'
          '${targetContext.isNotEmpty ? "。背景：$targetContext" : ""}',
    );

    task.status = 'completed';
    task.result = '${sourceChar.name} and ${targetChar.name} are now friends';
    task.tokenUsage = 80;
    debugPrint('SocialExecutor: ${sourceChar.name} + ${targetChar.name} 成为好友');
  }

  /// 私聊：通过消息系统发送
  Future<void> _executePrivateChat(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    final targetId = task.payload['targetCharacterId'] as String? ?? '';
    final message = task.payload['message'] as String? ?? '';
    if (targetId.isEmpty || message.isEmpty) {
      task.status = 'failed';
      task.result = '缺少目标角色ID或消息内容';
      return;
    }

    final sourceChar = await _storage.getAICharacter(sourceId);
    final targetChar = await _storage.getAICharacter(targetId);
    if (sourceChar == null || targetChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 获取目标角色上下文（含关系状态）
    final targetContext = await _buildTargetContext(targetId);

    // 检查是否有好友关系
    final rel = await _relationshipService.getRelationship(
      sourceId,
      targetId,
    );
    final relationshipInfo = rel != null
        ? '（${_relLabel(rel.relationshipType)}，亲密度 ${(rel.affinity * 100).toStringAsFixed(0)}%）'
        : '（尚未建立关系）';

    // 记录社交记忆（私聊内容 + 上下文）
    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: targetId,
      interactionType: 'private_chat',
      content:
          '${sourceChar.name} 对 ${targetChar.name} $relationshipInfo 说: $message'
          '${targetContext.isNotEmpty ? " | 角色背景：$targetContext" : ""}',
    );

    task.status = 'completed';
    task.result = 'Message sent to ${targetChar.name}: $message';
    task.tokenUsage = 30;
    debugPrint(
      'SocialExecutor: ${sourceChar.name} → ${targetChar.name} ($relationshipInfo): $message',
    );
  }

  /// 发动态：发布到朋友圈/日记
  /// 内容优先使用 task payload 中的 content；
  /// 若为空则调用 LLM 根据角色人设、记忆库、进化状态自动生成。
  Future<void> _executeMoment(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    var content = task.payload['content'] as String? ?? '';

    final sourceChar = await _storage.getAICharacter(sourceId);
    if (sourceChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 如果没有预设内容，用 LLM 生成
    if (content.isEmpty) {
      content = await _generateMomentContent(sourceChar);
      if (content.isEmpty) {
        task.status = 'failed';
        task.result = 'AI 生成动态内容失败';
        return;
      }
    }
    content = _cleanMomentText(content);
    if (content.isEmpty) {
      task.status = 'failed';
      task.result = 'AI 生成动态内容失败';
      return;
    }

    // 发布到真正的朋友圈（MomentsScreen 使用的 Moment 系统）
    final moment = Moment(
      id: const Uuid().v4(),
      userId: sourceId,
      userName: sourceChar.name,
      userAvatar: sourceChar.avatarUrl,
      content: content,
      images: const [],
      type: MomentType.text,
      likes: const [],
      comments: const [],
      createdAt: DateTime.now(),
      isFromAI: true,
      visibility: MomentVisibility.public,
      source: MomentSource.normal,
    );
    await _storage.saveMoment(moment);

    // 记录社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: 'self',
      interactionType: 'moment',
      content: '${sourceChar.name} 发了一条动态: $content',
    );

    task.status = 'completed';
    task.result = 'Moment posted: $content';
    task.tokenUsage = 20;
    debugPrint('SocialExecutor: ${sourceChar.name} 发动态: $content');
  }

  /// 评论：在朋友圈帖子下评论
  /// 评论内容优先使用 task payload 中的 comment；
  /// 若为空则调用 LLM 根据动态内容、评论者人设、与作者关系自动生成。
  Future<void> _executeMomentComment(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    final momentId = task.payload['momentId'] as String? ?? '';
    var comment = task.payload['comment'] as String? ?? '';
    if (momentId.isEmpty) {
      task.status = 'failed';
      task.result = '缺少帖子ID';
      return;
    }

    final sourceChar = await _storage.getAICharacter(sourceId);
    if (sourceChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 获取真正朋友圈里的目标动态
    final moments = await _storage.getAllMoments();
    final moment = moments.where((m) => m.id == momentId).firstOrNull;
    if (moment == null) {
      task.status = 'failed';
      task.result = '朋友圈动态不存在';
      return;
    }

    // 如果没有预设评论，用 LLM 生成
    if (comment.isEmpty) {
      comment = await _generateCommentContent(sourceChar, moment);
      if (comment.isEmpty) {
        task.status = 'failed';
        task.result = 'AI 生成评论内容失败';
        return;
      }
    }
    comment = _cleanMomentText(comment);
    if (comment.isEmpty) {
      task.status = 'failed';
      task.result = 'AI 生成评论内容失败';
      return;
    }

    final targetInfo = '（对 ${moment.userName} 的动态）';

    // 避免同一个角色重复评论同一条动态
    final alreadyCommented = moment.comments.any((c) => c.userId == sourceId);
    if (!alreadyCommented) {
      final updated = moment.copyWith(
        comments: [
          ...moment.comments,
          MomentComment(
            id: const Uuid().v4(),
            userId: sourceId,
            userName: sourceChar.name,
            content: comment,
            createdAt: DateTime.now(),
          ),
        ],
      );
      await _storage.saveMoment(updated);
    }

    // 记录社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: 'self',
      interactionType: 'moment_comment',
      content: '${sourceChar.name} 评论了$targetInfo: $comment',
    );

    task.status = 'completed';
    task.result = 'Comment posted: $comment';
    task.tokenUsage = 15;
    debugPrint('SocialExecutor: ${sourceChar.name} 评论: $comment');
  }

  /// 点赞：点赞朋友圈帖子
  /// 根据角色关系决定点赞哪些动态：\  /// - 如果没有指定 momentId，根据关系亲密度选择点赞对象
  /// - 优先点赞好友/恋人的动态，跳过敌人/对手
  Future<void> _executeMomentLike(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    var momentId = task.payload['momentId'] as String? ?? '';

    final sourceChar = await _storage.getAICharacter(sourceId);
    if (sourceChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    // 获取所有朋友圈动态
    final moments = await _storage.getAllMoments();

    // 如果没有指定 momentId，根据关系选择点赞对象
    if (momentId.isEmpty) {
      momentId = await _selectMomentToLike(sourceId, moments);
      if (momentId.isEmpty) {
        task.status = 'completed';
        task.result = '没有找到值得点赞的动态';
        return;
      }
    }

    final moment = moments.where((m) => m.id == momentId).firstOrNull;
    if (moment == null) {
      task.status = 'failed';
      task.result = '朋友圈动态不存在';
      return;
    }

    final newLikes = List<MomentLike>.from(moment.likes);
    final alreadyLiked = newLikes.any((l) => l.userId == sourceId);
    if (!alreadyLiked) {
      newLikes.add(MomentLike(
        userId: sourceId,
        userName: sourceChar.name,
        createdAt: DateTime.now(),
      ));
      await _storage.saveMoment(moment.copyWith(likes: newLikes));
    }

    // 提升亲密度（如果动态作者是另一个 AI 角色）
    final targetName = moment.userName;
    try {
      if (moment.isFromAI && moment.userId != sourceId) {
        await _bumpAffinity(sourceId, moment.userId, 0.02);
      }
    } catch (_) {}

    task.status = 'completed';
    task.result = '${sourceChar.name} liked ${targetName}\'s moment';
    task.tokenUsage = 5;
    debugPrint('SocialExecutor: ${sourceChar.name} 点赞 ${targetName} 的动态');
  }

  /// 日常活动：记录到社交记忆
  Future<void> _executeDailyActivity(TaskRequest task) async {
    final sourceId = task.sourceCharacterId;
    final activity = task.payload['activity'] as String? ?? '';
    if (activity.isEmpty) {
      task.status = 'failed';
      task.result = '活动内容为空';
      return;
    }

    final sourceChar = await _storage.getAICharacter(sourceId);
    if (sourceChar == null) {
      task.status = 'failed';
      task.result = '角色不存在';
      return;
    }

    await _memoryEngine.saveSocialMemory(
      characterId: sourceId,
      targetCharacterId: 'self',
      interactionType: 'daily_activity',
      content: '${sourceChar.name} $activity',
    );

    task.status = 'completed';
    task.result = 'Activity: $activity';
    debugPrint('SocialExecutor: ${sourceChar.name} 日常: $activity');
  }

  // ─── LLM 内容生成 ───

  String _cleanMomentText(String text) {
    return AIMomentService.extractFinalMomentContent(text).trim();
  }

  /// 懒加载 LlmService（从存储中读取 AI 配置）
  Future<LlmService?> _getLlmService() async {
    if (_cachedLlmService != null) return _cachedLlmService;
    try {
      final config = await _storage.getActiveAIConfig();
      if (config == null) return null;
      final settings = LlmSettings(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.modelName,
        maxTokens: 200,
        temperature: 0.85,
      );
      _cachedLlmService = LlmService(settings: settings);
      return _cachedLlmService;
    } catch (e) {
      debugPrint('SocialExecutor: _getLlmService error — $e');
      return null;
    }
  }

  /// 根据角色人设、记忆库、进化状态，用 LLM 生成朋友圈动态内容
  Future<String> _generateMomentContent(AICharacter character) async {
    final llm = await _getLlmService();
    if (llm == null) return _fallbackMomentContent(character);

    try {
      // 收集角色记忆
      final socialMemories =
          await _memoryEngine.loadSocialMemories(character.id);

      final socialText =
          socialMemories.take(10).map((m) => '- ${m.content}').join('\n');

      final systemPrompt = '你是一个朋友圈动态生成器。'
          '\n角色名字：${character.name}'
          '\n性格：${character.personality}'
          '\n核心欲望：${character.coreDesire}'
          '${character.languageStyle != null ? "\n语言风格：${character.languageStyle}" : ""}'
          '${character.catchphrases != null ? "\n口头禅：${character.catchphrases}" : ""}'
          '${character.currentStatus != null ? "\n当前状态：${character.currentStatus}" : ""}'
          '\n\n角色的社交记忆与互动记录：\n$socialText'
          '\n\n请以该角色的身份写一条朋友圈动态，1-3句话，自然真实，符合角色性格。'
          '直接输出内容，不要加引号、不要加"朋友圈："等前缀。';

      final response = await llm.chat(
        userId: 'social_moment_${character.id}',
        message: '请发一条朋友圈动态',
        systemPrompt: systemPrompt,
        maxTokensOverride: 150,
        includeReasoningFallback: false,
      );

      final text = _cleanMomentText(response.content);
      if (text.isNotEmpty && !text.contains('抱歉') && !text.contains('无法')) {
        return text;
      }
    } catch (e) {
      debugPrint('SocialExecutor: _generateMomentContent LLM error — $e');
    }

    return _fallbackMomentContent(character);
  }

  /// LLM 不可用时的 fallback：根据性格生成简单内容
  String _fallbackMomentContent(AICharacter character) {
    final personalityBased = <String, List<String>>{
      '温柔': ['今天天气真好~心情也暖暖的', '在窗边看了好久的云', '想给大家一个拥抱'],
      '活泼': ['冲鸭！今天也要元气满满！', '发现了一个超好玩的东西！！', '好想出去浪~'],
      '高冷': ['嗯。', '无聊。', '……'],
      '傲娇': ['才、才不是因为开心才发的！', '别误会，我只是随手发的', '哼，今天心情还不错啦'],
      '可爱': ['嘿嘿，今天也是甜甜的一天~', '给大家比个心！❤️', '在吃好吃的好开心！'],
    };

    final pLower = character.personality.toLowerCase();
    for (final entry in personalityBased.entries) {
      if (pLower.contains(entry.key)) {
        return entry
            .value[DateTime.now().millisecondsSinceEpoch % entry.value.length];
      }
    }
    // 通用 fallback
    final generic = [
      '今天天气真好~',
      '在看书，好困',
      '想出去玩',
      '今天心情不错',
      '在听歌~',
      '刚做了个美梦',
      '好想吃甜品',
      '今天好忙啊',
      '在发呆中...',
    ];
    return generic[DateTime.now().millisecondsSinceEpoch % generic.length];
  }

  /// 根据动态内容、评论者人设、与作者关系，用 LLM 生成评论
  Future<String> _generateCommentContent(
      AICharacter commenter, Moment moment) async {
    final llm = await _getLlmService();
    if (llm == null) return _fallbackCommentContent(commenter);

    try {
      // 获取与动态作者的关系
      String relationshipInfo = '尚未建立关系';
      try {
        final rel = await _relationshipService.getRelationship(
            commenter.id, moment.userId);
        if (rel != null) {
          relationshipInfo =
              '${_relLabel(rel.relationshipType)}，亲密度 ${(rel.affinity * 100).toStringAsFixed(0)}%';
        }
      } catch (_) {}

      // 加载评论者的社交记忆
      final socialMemories =
          await _memoryEngine.loadSocialMemories(commenter.id);
      final relevantMemories = socialMemories
          .where((m) => m.content.contains(moment.userName))
          .take(3)
          .map((m) => '- ${m.content}')
          .join('\n');

      final systemPrompt = '你是一个朋友圈评论生成器。'
          '\n评论者名字：${commenter.name}'
          '\n评论者性格：${commenter.personality}'
          '${commenter.languageStyle != null ? "\n语言风格：${commenter.languageStyle}" : ""}'
          '${commenter.catchphrases != null ? "\n口头禅：${commenter.catchphrases}" : ""}'
          '\n\n与动态作者的关系：$relationshipInfo'
          '${relevantMemories.isNotEmpty ? "\n相关记忆：\n$relevantMemories" : ""}'
          '\n\n动态内容：${moment.content}'
          '\n动态作者：${moment.userName}'
          '\n\n请以评论者的身份写一条评论，1-2句话，自然真实，符合角色性格和关系。'
          '直接输出评论内容，不要加引号、不要加"评论："等前缀。';

      final response = await llm.chat(
        userId: 'social_comment_${commenter.id}',
        message: '请对这条朋友圈写一条评论',
        systemPrompt: systemPrompt,
        maxTokensOverride: 100,
        includeReasoningFallback: false,
      );

      final text = _cleanMomentText(response.content);
      if (text.isNotEmpty && !text.contains('抱歉') && !text.contains('无法')) {
        return text;
      }
    } catch (e) {
      debugPrint('SocialExecutor: _generateCommentContent LLM error — $e');
    }

    return _fallbackCommentContent(commenter);
  }

  /// LLM 不可用时的 fallback 评论
  String _fallbackCommentContent(AICharacter character) {
    final comments = [
      '好棒！',
      '我也这么觉得~',
      '加油！',
      '太厉害了吧',
      '好羡慕',
      '真好啊',
      '我也是！',
      '赞一个'
    ];
    return comments[DateTime.now().millisecondsSinceEpoch % comments.length];
  }

  /// 根据关系亲密度选择要点赞的动态
  /// 优先点赞好友/恋人的动态，跳过敌人/对手，跳过已点赞的
  Future<String> _selectMomentToLike(
      String sourceId, List<Moment> moments) async {
    // 过滤掉已点赞的、自己的
    final candidates = moments.where((m) {
      final alreadyLiked = m.likes.any((l) => l.userId == sourceId);
      return !alreadyLiked && m.userId != sourceId;
    }).toList();

    if (candidates.isEmpty) return '';

    // 获取与每个动态作者的关系，按亲密度排序
    final scored = <MapEntry<Moment, double>>[];
    for (final m in candidates) {
      double score = 0.5; // 默认分数
      try {
        final rel =
            await _relationshipService.getRelationship(sourceId, m.userId);
        if (rel != null) {
          score = rel.affinity;
          // 敌人/对手关系降低分数
          if (rel.relationshipType == RelationshipType.enemy ||
              rel.relationshipType == RelationshipType.rival) {
            score -= 0.5;
          }
          // 恋人/好友提升分数
          if (rel.relationshipType == RelationshipType.lover ||
              rel.relationshipType == RelationshipType.bestFriend) {
            score += 0.3;
          }
        } else {
          // 没有关系的 AI 角色，较低优先级
          if (m.isFromAI) score = 0.3;
        }
      } catch (_) {}

      // AI 发的动态比用户发的稍微优先（社交互动）
      if (m.isFromAI) score += 0.1;

      // 时间衰减：越新越优先
      final age = DateTime.now().difference(m.createdAt);
      if (age.inHours < 1)
        score += 0.2;
      else if (age.inHours < 6) score += 0.1;

      scored.add(MapEntry(m, score));
    }

    if (scored.isEmpty) return '';

    // 按分数降序排序，取最高分
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key.id;
  }

  /// 提升亲密度
  Future<void> _bumpAffinity(
      String charIdA, String charIdB, double delta) async {
    try {
      final rel = await _relationshipService.getRelationship(charIdA, charIdB);
      if (rel != null) {
        final newAffinity = (rel.affinity + delta).clamp(0.0, 1.0);
        await _relationshipService.updateRelationship(
          rel.copyWith(affinity: newAffinity),
        );
      }
    } catch (e) {
      debugPrint('SocialExecutor: _bumpAffinity error — $e');
    }
  }

  String _relLabel(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return '朋友';
      case RelationshipType.bestFriend:
        return '好友';
      case RelationshipType.crush:
        return '暗恋';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.enemy:
        return '敌人';
      case RelationshipType.sibling:
        return '兄弟姐妹';
      case RelationshipType.mentor:
        return '导师';
      case RelationshipType.stranger:
        return '陌生人';
    }
  }
}
