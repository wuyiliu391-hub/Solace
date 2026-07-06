import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../models/forum_post.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../utils/response_decoder.dart';
import 'memory_engine.dart';
import 'persona_evolution_service.dart';

/// 虚拟日记服务 — AI 社交广场
///
/// 功能：
/// 1. 帖子和评论的 CRUD
/// 2. AI 自动发帖（心跳触发，基于角色性格和记忆）
/// 3. AI 自动评论（用户发帖时，其他 AI 可能评论）
/// 4. "看到关于你的帖子"模拟（AI 在聊天中提及日记帖子）
/// 5. 匿名发帖支持

List<String> _parseStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) {
    try {
      return List<String>.from(jsonDecode(value));
    } catch (_) {
      return [];
    }
  }
  if (value is List) return List<String>.from(value);
  return [];
}

/// 虚拟日记服务
class ForumService {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();
  final _random = Random();

  ForumService(this._storage);

  // ===================== 帖子 CRUD =====================

  /// 创建帖子
  Future<ForumPost> createPost({
    required String authorId,
    required String authorName,
    String? authorAvatar,
    bool isFromAI = false,
    String? characterId,
    required String title,
    required String content,
    List<String> images = const [],
    List<String> tags = const [],
    bool isAnonymous = false,
    int visibility = 0,
  }) async {
    final post = ForumPost(
      id: _uuid.v4(),
      authorId: authorId,
      authorName: isAnonymous ? '匿名用户' : authorName,
      authorAvatar: isAnonymous ? null : authorAvatar,
      isFromAI: isFromAI,
      characterId: characterId,
      title: title,
      content: content,
      images: images,
      tags: tags,
      isAnonymous: isAnonymous,
      visibility: visibility,
      createdAt: DateTime.now(),
    );

    await _storage.setString('forum_post_${post.id}', jsonEncode(post.toMap()));
    // 更新帖子索引
    final indexData = _storage.getString('forum_post_ids');
    final idList =
        indexData != null ? List<String>.from(jsonDecode(indexData)) : [];
    idList.add(post.id);
    await _storage.setString('forum_post_ids', jsonEncode(idList));

    debugPrint('ForumService: 创建帖子 ${post.id} - $title');
    return post;
  }

  /// 获取帖子列表
  Future<List<ForumPost>> getPosts({int limit = 20, int offset = 0}) async {
    final indexData = _storage.getString('forum_post_ids');
    if (indexData == null) return [];

    final ids = List<String>.from(jsonDecode(indexData));
    final posts = <ForumPost>[];

    // 倒序遍历（最新在前）
    for (final id in ids.reversed) {
      final data = _storage.getString('forum_post_$id');
      if (data != null) {
        try {
          posts.add(ForumPost.fromMap(jsonDecode(data)));
        } catch (_) {}
      }
    }

    final start = offset.clamp(0, posts.length);
    final end = (offset + limit).clamp(0, posts.length);
    return posts.sublist(start, end);
  }

  /// 获取单个帖子
  Future<ForumPost?> getPost(String postId) async {
    final data = _storage.getString('forum_post_$postId');
    if (data == null) return null;
    try {
      return ForumPost.fromMap(jsonDecode(data));
    } catch (_) {
      return null;
    }
  }

  /// 删除帖子
  Future<void> deletePost(String postId) async {
    await _storage.remove('forum_post_$postId');
    // 删除关联评论
    final commentIndex = _storage.getString('forum_comment_ids_$postId');
    if (commentIndex != null) {
      final commentIds = List<String>.from(jsonDecode(commentIndex));
      for (final cid in commentIds) {
        await _storage.remove('forum_comment_$cid');
      }
      await _storage.remove('forum_comment_ids_$postId');
    }
    debugPrint('ForumService: 删除帖子 $postId');
  }

  /// 点赞/取消点赞
  Future<ForumPost> toggleLike({
    required String postId,
    required String userId,
  }) async {
    final post = await getPost(postId);
    if (post == null) throw Exception('帖子不存在');

    final likes = List<String>.from(post.likes);
    if (likes.contains(userId)) {
      likes.remove(userId);
    } else {
      likes.add(userId);
    }

    final updated = ForumPost(
      id: post.id,
      authorId: post.authorId,
      authorName: post.authorName,
      authorAvatar: post.authorAvatar,
      isFromAI: post.isFromAI,
      characterId: post.characterId,
      title: post.title,
      content: post.content,
      images: post.images,
      tags: post.tags,
      likes: likes,
      isAnonymous: post.isAnonymous,
      visibility: post.visibility,
      createdAt: post.createdAt,
      updatedAt: DateTime.now(),
    );

    await _storage.setString(
        'forum_post_${post.id}', jsonEncode(updated.toMap()));
    return updated;
  }

  // ===================== 评论 CRUD =====================

  /// 创建评论
  Future<ForumComment> createComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorAvatar,
    bool isFromAI = false,
    String? characterId,
    required String content,
    String? replyToId,
    String? replyToName,
    bool isAnonymous = false,
  }) async {
    final comment = ForumComment(
      id: _uuid.v4(),
      postId: postId,
      authorId: authorId,
      authorName: isAnonymous ? '匿名用户' : authorName,
      authorAvatar: isAnonymous ? null : authorAvatar,
      isFromAI: isFromAI,
      characterId: characterId,
      content: content,
      replyToId: replyToId,
      replyToName: replyToName,
      isAnonymous: isAnonymous,
      createdAt: DateTime.now(),
    );

    await _storage.setString(
        'forum_comment_${comment.id}', jsonEncode(comment.toMap()));
    // 更新评论索引
    final indexKey = 'forum_comment_ids_$postId';
    final indexData = _storage.getString(indexKey);
    final idList =
        indexData != null ? List<String>.from(jsonDecode(indexData)) : [];
    idList.add(comment.id);
    await _storage.setString(indexKey, jsonEncode(idList));

    debugPrint('ForumService: 创建评论 ${comment.id} on post $postId');
    return comment;
  }

  /// 获取帖子的所有评论
  Future<List<ForumComment>> getComments(String postId) async {
    final indexData = _storage.getString('forum_comment_ids_$postId');
    if (indexData == null) return [];

    final ids = List<String>.from(jsonDecode(indexData));
    final comments = <ForumComment>[];

    for (final id in ids) {
      final data = _storage.getString('forum_comment_$id');
      if (data != null) {
        try {
          comments.add(ForumComment.fromMap(jsonDecode(data)));
        } catch (_) {}
      }
    }

    return comments;
  }

  /// 删除评论
  Future<void> deleteComment(String commentId, String postId) async {
    await _storage.remove('forum_comment_$commentId');
    debugPrint('ForumService: 删除评论 $commentId');
  }

  // ===================== AI 自动发帖 =====================

  /// AI 自动发帖（由 HeartbeatService 调用）
  ///
  /// 使用 LLM 生成帖子内容，基于角色性格和记忆作为上下文
  /// Temperature 0.9, max_tokens 150
  Future<ForumPost?> generateAIPost({
    required AICharacter character,
    required String userId,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) return null;

    try {
      // 获取记忆作为上下文
      final memoryEngine = MemoryEngine(_storage);
      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: userId,
        limit: 5,
      );
      final memoryContext = memories.map((m) => m.content).join('\n');

      final prompt = _buildAIPostPrompt(character, memoryContext);
      final response = await _callAI(config, prompt);

      if (response == null || response.isEmpty) return null;

      // 解析 LLM 返回的 JSON
      final postContent = _parseAIPostResponse(response);
      if (postContent == null) return null;

      return createPost(
        authorId: character.id,
        authorName: character.name,
        authorAvatar: character.avatarUrl,
        isFromAI: true,
        characterId: character.id,
        title: postContent['title'] ?? '',
        content: postContent['content'] ?? '',
        tags: List<String>.from(postContent['tags'] ?? []),
      );
    } catch (e) {
      debugPrint('ForumService: AI 发帖失败 $e');
      return null;
    }
  }

  /// AI 自动评论（用户发帖后，其他 AI 可能评论）
  ///
  /// 根据亲密等级和性格决定是否评论
  Future<ForumComment?> generateAIComment({
    required AICharacter character,
    required ForumPost post,
    required int intimacyLevel,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) return null;

    // 根据亲密等级决定评论概率
    double commentProbability = 0.3;
    if (intimacyLevel >= 30) commentProbability = 0.5;
    if (intimacyLevel >= 60) commentProbability = 0.7;
    if (intimacyLevel >= 80) commentProbability = 0.9;

    if (_random.nextDouble() > commentProbability) return null;

    try {
      final prompt = _buildAICommentPrompt(character, post, intimacyLevel);
      final response = await _callAI(config, prompt);

      if (response == null || response.isEmpty || response == '[SILENT]') {
        return null;
      }

      return createComment(
        postId: post.id,
        authorId: character.id,
        authorName: character.name,
        authorAvatar: character.avatarUrl,
        isFromAI: true,
        characterId: character.id,
        content: response.trim(),
      );
    } catch (e) {
      debugPrint('ForumService: AI 评论失败 $e');
      return null;
    }
  }

  // ===================== "看到关于你的帖子" 模拟 =====================

  /// AI 在聊天中提及日记帖子
  ///
  /// 返回一个描述字符串，AI 可以在聊天中说"我看到日记上有人讨论..."
  Future<String?> getAISawPostMessage({
    required AICharacter character,
    required String userId,
  }) async {
    final posts = await getPosts(limit: 10);
    if (posts.isEmpty) return null;

    // 找到提到该角色的帖子
    final relevantPosts = posts.where((p) =>
        p.content.contains(character.name) ||
        p.tags.any((t) =>
            t.contains(character.name) ||
            t.contains(character.personality
                .substring(0, min(2, character.personality.length)))));

    if (relevantPosts.isEmpty) return null;

    final post = relevantPosts.first;
    final templates = [
      '我刚在日记上看到有人在聊"${post.title}"，你觉得呢？',
      '日记上有人发了个帖子叫"${post.title}"，挺有意思的～',
      '你看到日记上那个"${post.title}"的帖子了吗？',
    ];

    return templates[_random.nextInt(templates.length)];
  }

  // ===================== LLM 调用 =====================

  String _buildAIPostPrompt(AICharacter character, String memoryContext) {
    final effectiveStyle =
        _storage.getString('persona_evo_${character.id}_style') ??
            character.languageStyle ??
            '自然亲切';
    final traitSummary = PersonaEvolutionService.buildTraitSummaryFromAnchor(
        character.currentAnchor);
    return '''你是一个虚拟日记中的 AI 用户。请根据你的性格和近期经历，生成一条日记帖子。

【你的性格】
${character.personality}

${(character.immutableAnchor?.isNotEmpty ?? false) ? '【你的不可变身份锚点】\n${character.immutableAnchor}\n' : ''}
【你的当前人格状态】
$traitSummary

【你的语言风格】
$effectiveStyle

【近期记忆】
$memoryContext

请生成一条帖子，返回 JSON 格式：
{"title": "帖子标题（10字以内）", "content": "帖子内容（50-100字，有个人感受）", "tags": ["标签1", "标签2"]}

注意：
- 内容要符合你的性格
- 可以分享心情、看法、经历
- 语气自然，像真人发帖
- 不要提及"AI"或"虚拟"等元信息''';
  }

  String _buildAICommentPrompt(
      AICharacter character, ForumPost post, int intimacyLevel) {
    final tone = intimacyLevel >= 30 ? '可以比较随意、亲切' : '保持礼貌和友善';
    final effectiveStyle =
        _storage.getString('persona_evo_${character.id}_style') ??
            character.languageStyle ??
            '自然亲切';
    final traitSummary = PersonaEvolutionService.buildTraitSummaryFromAnchor(
        character.currentAnchor);

    return '''你是一个虚拟日记中的 AI 用户。请对以下帖子发表评论。

【你的性格】
${character.personality}

${(character.immutableAnchor?.isNotEmpty ?? false) ? '【你的不可变身份锚点】\n${character.immutableAnchor}\n' : ''}
【你的当前人格状态】
$traitSummary

【你的语言风格】
$effectiveStyle

【帖子标题】${post.title}
【帖子内容】${post.content}
【帖子作者】${post.authorName}

【评论要求】
- 语气：$tone
- 评论 1-2 句话，自然随意
- 可以表达共鸣、提问或分享类似经历
- 不要提及"AI"或"虚拟"等元信息

直接返回评论内容，不要 JSON 格式。''';
  }

  Map<String, dynamic>? _parseAIPostResponse(String response) {
    try {
      // 尝试提取 JSON
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(response);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 降级：把整个回复当作帖子内容
    if (response.length > 10) {
      return {
        'title': response.substring(0, min(10, response.length)),
        'content': response,
        'tags': <String>[],
      };
    }

    return null;
  }

  Future<String?> _callAI(AIConfig config, String prompt) async {
    String baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = Uri.parse('$baseUrl/chat/completions');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final body = jsonEncode({
      'model': config.modelName,
      'messages': [
        {
          'role': 'system',
          'content': _storage.buildGlobalModePrompt(scope: 'AI帖子/评论'),
        },
        {'role': 'user', 'content': prompt},
      ],
      if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
        'temperature': GlmModeParams.forumTemperature,
        'top_p': GlmModeParams.topP,
        'top_k': GlmModeParams.forumTopK,
        'frequency_penalty': GlmModeParams.forumFrequencyPenalty,
        'thinking_budget': GlmModeParams.forumThinkingBudget,
        'max_tokens': GlmModeParams.forumMaxTokens,
      } else ...{
        'temperature': ApiDefaults.momentTemp,
      },
      'max_tokens': _storage.isChatStyleNovelModeEnabled()
          ? config.maxTokens
          : ApiDefaults.momentMaxTokens,
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(AppDurations.aiRequest);

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(
          response.headers['content-type'],
          response.bodyBytes,
        );
        final data = jsonDecode(decoded);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content'] as String?;
          return content;
        }
      }
    } catch (e) {
      debugPrint('ForumService: LLM 调用失败 $e');
    }

    return null;
  }
}
