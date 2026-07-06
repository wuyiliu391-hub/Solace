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
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    final blockedByIndex = map['blockedBy'] as int? ?? 0;
    return ChatSession(
      id: map['id'] as String,
      userId: map['userId'] as String,
      aiCharacterId: map['aiCharacterId'] as String,
      aiCharacterName: map['aiCharacterName'] as String,
      aiCharacterAvatar: map['aiCharacterAvatar'] as String?,
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.tryParse(map['lastMessageTime'] as String? ?? '')
          : null,
      unreadCount: map['unreadCount'] as int? ?? 0,
      intimacyLevel: map['intimacyLevel'] as int? ?? 0,
      dailyIntimacyCount: map['dailyIntimacyCount'] as int? ?? 0,
      lastIntimacyDate: map['lastIntimacyDate'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String? ?? '')
          : null,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      isPinned: map['isPinned'] == 1 || map['isPinned'] == true,
      backgroundImage: map['backgroundImage'] as String?,
      isHidden: map['isHidden'] == 1 || map['isHidden'] == true,
      aiIsOnline: map['aiIsOnline'] == 1 || map['aiIsOnline'] == true,
      aiCurrentStatus: map['aiCurrentStatus'] as String?,
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
      ];
}
