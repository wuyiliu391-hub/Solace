import 'package:equatable/equatable.dart';
import 'dart:convert';

/// 群聊激活策略（对标 SillyTavern group_activation_strategy）
enum GroupActivationStrategy { natural, list, manual, pooled }

/// 群聊生成模式（对标 SillyTavern group_generation_mode）
enum GroupGenerationMode { swap, append, appendDisabled }

/// AI 群聊会话（对标 ChatSession 模式）
class GroupChatSession extends Equatable {
  /// 会话唯一 ID
  final String id;

  /// 所属用户 ID
  final String userId;

  /// 群名称
  final String name;

  /// 群头像 URL
  final String? avatarUrl;

  /// 成员 ID 列表（含用户 + AI）
  final List<String> memberIds;

  /// AI 角色 ID 列表
  final List<String> aiCharacterIds;

  /// 创建者 ID
  final String creatorId;

  /// 最后一条消息预览
  final String? lastMessage;

  /// 最后一条消息时间
  final DateTime? lastMessageTime;

  /// 未读消息数
  final int unreadCount;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime? updatedAt;

  /// 是否静音
  final bool isMuted;

  /// 是否置顶
  final bool isPinned;

  /// 背景图 URL
  final String? backgroundImage;

  /// 群公告
  final String? notice;

  /// 同步序列号
  final int syncSeq;

  /// 当前聊天记录 id（多聊天记录，默认=群 id）
  final String chatId;

  /// 激活策略：natural 提及+话痨 / list 按序轮流 / manual 手动 / pooled 轮转池
  final GroupActivationStrategy activationStrategy;

  /// 生成模式：swap 逐角色 / append 合并卡 / appendDisabled 合并卡(禁言排除)
  final GroupGenerationMode generationMode;

  /// 允许同一角色连续发言
  final bool allowSelfResponses;

  /// 禁言成员 id 列表
  final List<String> disabledMemberIds;

  /// 自动接话轮询间隔（秒，对标 auto_mode_delay 默认 5）
  final int autoModeDelay;

  /// 自动接话总开关
  final bool autoModeEnabled;

  /// 每个角色的自动接话间隔（秒）。未配置的角色回退到 autoModeDelay。
  final Map<String, int> autoModeDelaysByCharacter;

  /// 从消息页移除但保留在联系人中的软删除标记。
  final bool isHidden;

  /// APPEND 合并角色卡字段前缀模板
  final String joinPrefix;

  /// APPEND 合并角色卡字段后缀模板
  final String joinSuffix;

  const GroupChatSession({
    required this.id,
    this.userId = '',
    required this.name,
    this.avatarUrl,
    required this.memberIds,
    required this.aiCharacterIds,
    required this.creatorId,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.isMuted = false,
    this.isPinned = false,
    this.backgroundImage,
    this.notice,
    this.syncSeq = 0,
    String? chatId,
    this.activationStrategy = GroupActivationStrategy.natural,
    this.generationMode = GroupGenerationMode.swap,
    this.allowSelfResponses = false,
    this.disabledMemberIds = const [],
    this.autoModeDelay = 5,
    this.autoModeEnabled = false,
    this.autoModeDelaysByCharacter = const {},
    this.isHidden = false,
    this.joinPrefix = '',
    this.joinSuffix = '',
  }) : chatId = chatId ?? id;

  GroupChatSession copyWith({
    String? id,
    String? userId,
    String? name,
    String? avatarUrl,
    List<String>? memberIds,
    List<String>? aiCharacterIds,
    String? creatorId,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isMuted,
    bool? isPinned,
    String? backgroundImage,
    String? notice,
    int? syncSeq,
    String? chatId,
    GroupActivationStrategy? activationStrategy,
    GroupGenerationMode? generationMode,
    bool? allowSelfResponses,
    List<String>? disabledMemberIds,
    int? autoModeDelay,
    bool? autoModeEnabled,
    bool? isHidden,
    Map<String, int>? autoModeDelaysByCharacter,
    String? joinPrefix,
    String? joinSuffix,
  }) {
    return GroupChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      memberIds: memberIds ?? this.memberIds,
      aiCharacterIds: aiCharacterIds ?? this.aiCharacterIds,
      creatorId: creatorId ?? this.creatorId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      notice: notice ?? this.notice,
      syncSeq: syncSeq ?? this.syncSeq,
      chatId: chatId ?? this.chatId,
      activationStrategy: activationStrategy ?? this.activationStrategy,
      generationMode: generationMode ?? this.generationMode,
      allowSelfResponses: allowSelfResponses ?? this.allowSelfResponses,
      disabledMemberIds: disabledMemberIds ?? this.disabledMemberIds,
      autoModeDelay: autoModeDelay ?? this.autoModeDelay,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      isHidden: isHidden ?? this.isHidden,
      autoModeDelaysByCharacter:
          autoModeDelaysByCharacter ?? this.autoModeDelaysByCharacter,
      joinPrefix: joinPrefix ?? this.joinPrefix,
      joinSuffix: joinSuffix ?? this.joinSuffix,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'avatarUrl': avatarUrl,
      'memberIds': jsonEncode(memberIds),
      'aiCharacterIds': jsonEncode(aiCharacterIds),
      'creatorId': creatorId,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted ? 1 : 0,
      'isPinned': isPinned ? 1 : 0,
      'backgroundImage': backgroundImage,
      'notice': notice,
      'sync_seq': syncSeq,
      'chatId': chatId,
      'activationStrategy': activationStrategy.index,
      'generationMode': generationMode.index,
      'allowSelfResponses': allowSelfResponses ? 1 : 0,
      'disabledMemberIds': jsonEncode(disabledMemberIds),
      'autoModeDelay': autoModeDelay,
      'autoModeEnabled': autoModeEnabled ? 1 : 0,
      'isHidden': isHidden ? 1 : 0,
      'autoModeDelaysByCharacter': jsonEncode(autoModeDelaysByCharacter),
      'joinPrefix': joinPrefix,
      'joinSuffix': joinSuffix,
    };
  }

  factory GroupChatSession.fromMap(Map<String, dynamic> map) {
    DateTime? parsedLastMessageTime;
    final lmtVal = map['lastMessageTime'];
    if (lmtVal is String) {
      parsedLastMessageTime = DateTime.tryParse(lmtVal);
    } else if (lmtVal is int) {
      parsedLastMessageTime = DateTime.fromMillisecondsSinceEpoch(lmtVal);
    }

    DateTime? parsedCreatedAt;
    final caVal = map['createdAt'];
    if (caVal is String) {
      parsedCreatedAt = DateTime.tryParse(caVal);
    } else if (caVal is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(caVal);
    }

    DateTime? parsedUpdatedAt;
    final uaVal = map['updatedAt'];
    if (uaVal is String) {
      parsedUpdatedAt = DateTime.tryParse(uaVal);
    } else if (uaVal is int) {
      parsedUpdatedAt = DateTime.fromMillisecondsSinceEpoch(uaVal);
    }

    List<String> parseStringList(dynamic val) {
      if (val == null) return [];
      if (val is String) {
        try {
          final decoded = jsonDecode(val);
          if (decoded is List<dynamic>) return decoded.cast<String>();
        } catch (_) {}
        return val.split('||').where((s) => s.isNotEmpty).toList();
      }
      if (val is List<dynamic>) return val.cast<String>();
      return [];
    }

    final chatIdVal = map['chatId']?.toString() ?? map['id']?.toString() ?? '';
    final asVal = map['activationStrategy'];
    final asEnum = asVal is int &&
            asVal >= 0 &&
            asVal < GroupActivationStrategy.values.length
        ? GroupActivationStrategy.values[asVal]
        : GroupActivationStrategy.natural;
    final gmVal = map['generationMode'];
    final gmEnum =
        gmVal is int && gmVal >= 0 && gmVal < GroupGenerationMode.values.length
            ? GroupGenerationMode.values[gmVal]
            : GroupGenerationMode.swap;
    final rawDisabled = map['disabledMemberIds'];
    List<String> disabled = [];
    if (rawDisabled is String && rawDisabled.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDisabled);
        if (decoded is List) disabled = decoded.cast<String>();
      } catch (_) {}
    }
    final rawDelays = map['autoModeDelaysByCharacter'];
    final delays = <String, int>{};
    if (rawDelays is String && rawDelays.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDelays);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final delay = value is num ? value.toInt() : int.tryParse('$value');
            if (delay != null && delay > 0) delays['$key'] = delay;
          });
        }
      } catch (_) {}
    }

    return GroupChatSession(
      id: map['id'] as String,
      userId: map['userId']?.toString() ?? '',
      name: map['name'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      memberIds: parseStringList(map['memberIds']),
      aiCharacterIds: parseStringList(map['aiCharacterIds']),
      creatorId: map['creatorId'] as String? ?? '',
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: parsedLastMessageTime,
      unreadCount: map['unreadCount'] as int? ?? 0,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      updatedAt: parsedUpdatedAt,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      isPinned: map['isPinned'] == 1 || map['isPinned'] == true,
      backgroundImage: map['backgroundImage'] as String?,
      notice: map['notice'] as String?,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      chatId: chatIdVal,
      activationStrategy: asEnum,
      generationMode: gmEnum,
      allowSelfResponses:
          map['allowSelfResponses'] == 1 || map['allowSelfResponses'] == true,
      disabledMemberIds: disabled,
      autoModeDelay: (map['autoModeDelay'] as int?) ?? 5,
      autoModeEnabled:
          map['autoModeEnabled'] == 1 || map['autoModeEnabled'] == true,
      isHidden: map['isHidden'] == 1 || map['isHidden'] == true,
      autoModeDelaysByCharacter: delays,
      joinPrefix: map['joinPrefix']?.toString() ?? '',
      joinSuffix: map['joinSuffix']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'avatarUrl': avatarUrl,
      'memberIds': memberIds,
      'aiCharacterIds': aiCharacterIds,
      'creatorId': creatorId,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted,
      'isPinned': isPinned,
      'backgroundImage': backgroundImage,
      'notice': notice,
      'syncSeq': syncSeq,
      'chatId': chatId,
      'activationStrategy': activationStrategy.index,
      'generationMode': generationMode.index,
      'allowSelfResponses': allowSelfResponses,
      'disabledMemberIds': disabledMemberIds,
      'autoModeDelay': autoModeDelay,
      'autoModeEnabled': autoModeEnabled,
      'isHidden': isHidden,
      'autoModeDelaysByCharacter': autoModeDelaysByCharacter,
      'joinPrefix': joinPrefix,
      'joinSuffix': joinSuffix,
    };
  }

  factory GroupChatSession.fromJson(Map<String, dynamic> json) {
    final chatIdVal =
        json['chatId']?.toString() ?? json['id']?.toString() ?? '';
    final asVal = json['activationStrategy'];
    final asEnum = asVal is int &&
            asVal >= 0 &&
            asVal < GroupActivationStrategy.values.length
        ? GroupActivationStrategy.values[asVal]
        : GroupActivationStrategy.natural;
    final gmVal = json['generationMode'];
    final gmEnum =
        gmVal is int && gmVal >= 0 && gmVal < GroupGenerationMode.values.length
            ? GroupGenerationMode.values[gmVal]
            : GroupGenerationMode.swap;
    return GroupChatSession(
      id: json['id'] as String? ?? '',
      userId: json['userId']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      memberIds: (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? [],
      aiCharacterIds:
          (json['aiCharacterIds'] as List<dynamic>?)?.cast<String>() ?? [],
      creatorId: json['creatorId'] as String? ?? '',
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String? ?? '')
          : null,
      isMuted: json['isMuted'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      backgroundImage: json['backgroundImage'] as String?,
      notice: json['notice'] as String?,
      syncSeq: json['syncSeq'] as int? ?? 0,
      chatId: chatIdVal,
      activationStrategy: asEnum,
      generationMode: gmEnum,
      allowSelfResponses: json['allowSelfResponses'] as bool? ?? false,
      disabledMemberIds:
          (json['disabledMemberIds'] as List<dynamic>?)?.cast<String>() ?? [],
      autoModeDelay: json['autoModeDelay'] as int? ?? 5,
      autoModeEnabled: json['autoModeEnabled'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      autoModeDelaysByCharacter:
          (json['autoModeDelaysByCharacter'] as Map<dynamic, dynamic>?)?.map(
                (key, value) => MapEntry('$key', (value as num).toInt()),
              ) ??
              const {},
      joinPrefix: json['joinPrefix'] as String? ?? '',
      joinSuffix: json['joinSuffix'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        memberIds,
        aiCharacterIds,
        creatorId,
        lastMessage,
        lastMessageTime,
        unreadCount,
        createdAt,
        updatedAt,
        isMuted,
        isPinned,
        backgroundImage,
        notice,
        syncSeq,
        chatId,
        activationStrategy,
        generationMode,
        allowSelfResponses,
        disabledMemberIds,
        autoModeDelay,
        autoModeEnabled,
        joinPrefix,
        joinSuffix,
      ];
}
