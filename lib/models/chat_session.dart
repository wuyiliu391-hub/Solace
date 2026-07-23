import 'package:equatable/equatable.dart';

enum BlockedBy { none, user, ai }

class ChatSession extends Equatable {
  final String id;
  final String userId;
  final String aiCharacterId;
  final String aiCharacterName;
  final String? aiCharacterAvatar;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final int intimacyLevel;
  final int dailyIntimacyCount;
  final String? lastIntimacyDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isMuted;
  final bool isPinned;
  final String? backgroundImage;
  final bool isHidden;
  final bool aiIsOnline;
  final String? aiCurrentStatus;
  /// 角色最后上线时间（用于在线状态判断）
  final DateTime? lastOnlineAt;
  final int syncSeq;
  final bool isBlocked;
  final BlockedBy blockedBy;
  final DateTime? blockedAt;
  final String? blockReason;
  final String sessionType; // 'private' = user-AI, 'social' = AI-AI
  final String intimacyMode; // 'quick' | 'slow'
  final int streakDays;
  final bool isInFriction;
  final int frictionDaysLeft;
  /// 小说模式：-1=跟随全局设置，0=关闭，1=开启
  final int novelMode;

  const ChatSession({
    required this.id,
    required this.userId,
    required this.aiCharacterId,
    required this.aiCharacterName,
    this.aiCharacterAvatar,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.intimacyLevel = 0,
    this.dailyIntimacyCount = 0,
    this.lastIntimacyDate,
    required this.createdAt,
    this.updatedAt,
    this.isMuted = false,
    this.isPinned = false,
    this.backgroundImage,
    this.isHidden = false,
    this.aiIsOnline = true,
    this.aiCurrentStatus,
    this.lastOnlineAt,
    this.syncSeq = 0,
    this.isBlocked = false,
    this.blockedBy = BlockedBy.none,
    this.blockedAt,
    this.blockReason,
    this.sessionType = 'private',
    this.intimacyMode = 'quick',
    this.streakDays = 0,
    this.isInFriction = false,
    this.frictionDaysLeft = 0,
    this.novelMode = -1,
  });

  ChatSession copyWith({
    String? id,
    String? userId,
    String? aiCharacterId,
    String? aiCharacterName,
    String? aiCharacterAvatar,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    int? intimacyLevel,
    int? dailyIntimacyCount,
    String? lastIntimacyDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isMuted,
    bool? isPinned,
    String? backgroundImage,
    bool? isHidden,
    bool? aiIsOnline,
    String? aiCurrentStatus,
    DateTime? lastOnlineAt,
    int? syncSeq,
    bool? isBlocked,
    BlockedBy? blockedBy,
    DateTime? blockedAt,
    String? blockReason,
    String? sessionType,
    bool clearBlock = false,
    String? intimacyMode,
    int? streakDays,
    bool? isInFriction,
    int? frictionDaysLeft,
    int? novelMode,
  }) {
    return ChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      aiCharacterId: aiCharacterId ?? this.aiCharacterId,
      aiCharacterName: aiCharacterName ?? this.aiCharacterName,
      aiCharacterAvatar: aiCharacterAvatar ?? this.aiCharacterAvatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      intimacyLevel: intimacyLevel ?? this.intimacyLevel,
      dailyIntimacyCount: dailyIntimacyCount ?? this.dailyIntimacyCount,
      lastIntimacyDate: lastIntimacyDate ?? this.lastIntimacyDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      isHidden: isHidden ?? this.isHidden,
      aiIsOnline: aiIsOnline ?? this.aiIsOnline,
      aiCurrentStatus: aiCurrentStatus ?? this.aiCurrentStatus,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      syncSeq: syncSeq ?? this.syncSeq,
      isBlocked: clearBlock ? false : (isBlocked ?? this.isBlocked),
      blockedBy: clearBlock ? BlockedBy.none : (blockedBy ?? this.blockedBy),
      blockedAt: clearBlock ? null : (blockedAt ?? this.blockedAt),
      blockReason: clearBlock ? null : (blockReason ?? this.blockReason),
      sessionType: sessionType ?? this.sessionType,
      intimacyMode: intimacyMode ?? this.intimacyMode,
      streakDays: streakDays ?? this.streakDays,
      isInFriction: isInFriction ?? this.isInFriction,
      frictionDaysLeft: frictionDaysLeft ?? this.frictionDaysLeft,
      novelMode: novelMode ?? this.novelMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'aiCharacterId': aiCharacterId,
      'aiCharacterName': aiCharacterName,
      'aiCharacterAvatar': aiCharacterAvatar,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'intimacyLevel': intimacyLevel,
      'dailyIntimacyCount': dailyIntimacyCount,
      'lastIntimacyDate': lastIntimacyDate,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted ? 1 : 0,
      'isPinned': isPinned ? 1 : 0,
      'backgroundImage': backgroundImage,
      'isHidden': isHidden ? 1 : 0,
      'aiIsOnline': aiIsOnline ? 1 : 0,
      'aiCurrentStatus': aiCurrentStatus,
      'lastOnlineAt': lastOnlineAt?.toIso8601String(),
      'sync_seq': syncSeq,
      'isBlocked': isBlocked ? 1 : 0,
      'blockedBy': blockedBy.index,
      'blockedAt': blockedAt?.toIso8601String(),
      'blockReason': blockReason,
      'sessionType': sessionType,
      'intimacyMode': intimacyMode,
      'streakDays': streakDays,
      'isInFriction': isInFriction ? 1 : 0,
      'frictionDaysLeft': frictionDaysLeft,
      'novelMode': novelMode,
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    final blockedByIndex = map['blockedBy'] as int? ?? 0;
    
    // 处理 lastMessageTime：可能是 String、int 或 null
    DateTime? parsedLastMessageTime;
    final lastMsgTimeVal = map['lastMessageTime'];
    if (lastMsgTimeVal != null) {
      if (lastMsgTimeVal is String) {
        parsedLastMessageTime = DateTime.tryParse(lastMsgTimeVal);
      } else if (lastMsgTimeVal is int) {
        parsedLastMessageTime = DateTime.fromMillisecondsSinceEpoch(lastMsgTimeVal);
      }
    }
    
    // 处理 createdAt：可能是 String、int 或 null
    DateTime? parsedCreatedAt;
    final createdAtVal = map['createdAt'];
    if (createdAtVal != null) {
      if (createdAtVal is String) {
        parsedCreatedAt = DateTime.tryParse(createdAtVal);
      } else if (createdAtVal is int) {
        parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(createdAtVal);
      }
    }
    
    // 处理 updatedAt
    DateTime? parsedUpdatedAt;
    final updatedAtVal = map['updatedAt'];
    if (updatedAtVal != null) {
      if (updatedAtVal is String) {
        parsedUpdatedAt = DateTime.tryParse(updatedAtVal);
      } else if (updatedAtVal is int) {
        parsedUpdatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtVal);
      }
    }
    
    return ChatSession(
      id: map['id'] as String,
      userId: map['userId'] as String,
      aiCharacterId: map['aiCharacterId'] as String,
      aiCharacterName: map['aiCharacterName'] as String,
      aiCharacterAvatar: map['aiCharacterAvatar'] as String?,
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: parsedLastMessageTime,
      unreadCount: map['unreadCount'] as int? ?? 0,
      intimacyLevel: map['intimacyLevel'] as int? ?? 0,
      dailyIntimacyCount: map['dailyIntimacyCount'] as int? ?? 0,
      lastIntimacyDate: map['lastIntimacyDate'] as String?,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      updatedAt: parsedUpdatedAt,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      isPinned: map['isPinned'] == 1 || map['isPinned'] == true,
      backgroundImage: map['backgroundImage'] as String?,
      isHidden: map['isHidden'] == 1 || map['isHidden'] == true,
      aiIsOnline: map['aiIsOnline'] == 1 || map['aiIsOnline'] == true,
      aiCurrentStatus: map['aiCurrentStatus'] as String?,
      lastOnlineAt: map['lastOnlineAt'] != null
          ? DateTime.tryParse(map['lastOnlineAt'] as String? ?? '')
          : null,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      isBlocked: map['isBlocked'] == 1 || map['isBlocked'] == true,
      blockedBy: blockedByIndex < BlockedBy.values.length
          ? BlockedBy.values[blockedByIndex]
          : BlockedBy.none,
      blockedAt: map['blockedAt'] != null
          ? DateTime.tryParse(map['blockedAt'] as String? ?? '')
          : null,
      blockReason: map['blockReason'] as String?,
      sessionType: map['sessionType'] as String? ?? 'private',
      intimacyMode: map['intimacyMode'] as String? ?? 'quick',
      streakDays: map['streakDays'] as int? ?? 0,
      isInFriction: map['isInFriction'] == 1 || map['isInFriction'] == true,
      frictionDaysLeft: map['frictionDaysLeft'] as int? ?? 0,
      novelMode: map['novelMode'] as int? ?? -1,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        aiCharacterId,
        aiCharacterName,
        aiCharacterAvatar,
        lastMessage,
        lastMessageTime,
        unreadCount,
        intimacyLevel,
        dailyIntimacyCount,
        lastIntimacyDate,
        createdAt,
        updatedAt,
        isMuted,
        isPinned,
        backgroundImage,
        isHidden,
        aiIsOnline,
        aiCurrentStatus,
        lastOnlineAt,
        syncSeq,
        isBlocked,
        blockedBy,
        blockedAt,
        blockReason,
        sessionType,
        intimacyMode,
        streakDays,
        isInFriction,
        frictionDaysLeft,
        novelMode,
      ];
}
