import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  // 新增个人资料字段
  final String? signature;        // 个性签名
  final String? gender;           // 性别
  final String? birthday;         // 生日
  final String? location;         // 所在地
  final String? bio;              // 个人简介
  /// 我的代称：单聊/群聊中 AI 指代"我"用的人物名或称谓。
  /// 为空时用昵称。用户扮演其他人物（如"林晚晚"）或希望被称呼为
  /// "主人/少爷/姐姐"时填这里，各请求组装点统一读取。
  final String? chatAlias;

  // 虚拟货币
  final int coins;                // 金币数量
  final int totalCoinsEarned;     // 累计获得金币
  final int totalCoinsSpent;      // 累计花费金币

  // 自定义状态
  final String? status;            // 当前状态（开心、忙碌、emo等）

  /// 个人主页背景图。
  /// [backgroundImage] 沿用旧字段，语义为「竖屏背景」，保持老数据兼容；
  /// [backgroundImageLandscape] 是新增的横屏背景。
  final String? backgroundImage;
  final String? backgroundImageLandscape;
  final int syncSeq;

  const User({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.signature,
    this.gender,
    this.birthday,
    this.location,
    this.bio,
    this.chatAlias,
    this.status,
    this.backgroundImage,
    this.backgroundImageLandscape,
    this.syncSeq = 0,
    this.coins = 100,              // 新用户默认100金币
    this.totalCoinsEarned = 100,
    this.totalCoinsSpent = 0,
  });

  User copyWith({
    String? id,
    String? nickname,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? signature,
    String? gender,
    String? birthday,
    String? location,
    String? bio,
    String? chatAlias,
    String? status,
    String? backgroundImage,
    String? backgroundImageLandscape,
    int? syncSeq,
    int? coins,
    int? totalCoinsEarned,
    int? totalCoinsSpent,
    /// 显式把头像置空。`avatarUrl ?? this.avatarUrl` 无法表达「清空」，
    /// 传 null 会被静默忽略，所以清除头像必须走这个开关。
    bool clearAvatarUrl = false,
    /// 同上，用于清除竖屏 / 横屏背景图。
    bool clearBackgroundImage = false,
    bool clearBackgroundImageLandscape = false,
    /// 同上，用于清除代称（传 null 会被忽略，清空必须走这个开关）。
    bool clearChatAlias = false,
  }) {
    return User(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      signature: signature ?? this.signature,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
      location: location ?? this.location,
      bio: bio ?? this.bio,
      chatAlias: clearChatAlias ? null : (chatAlias ?? this.chatAlias),
      status: status ?? this.status,
      backgroundImage: clearBackgroundImage
          ? null
          : (backgroundImage ?? this.backgroundImage),
      backgroundImageLandscape: clearBackgroundImageLandscape
          ? null
          : (backgroundImageLandscape ?? this.backgroundImageLandscape),
      syncSeq: syncSeq ?? this.syncSeq,
      coins: coins ?? this.coins,
      totalCoinsEarned: totalCoinsEarned ?? this.totalCoinsEarned,
      totalCoinsSpent: totalCoinsSpent ?? this.totalCoinsSpent,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nickname': nickname,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'signature': signature,
      'gender': gender,
      'birthday': birthday,
      'location': location,
      'bio': bio,
      'chatAlias': chatAlias,
      'status': status,
      'backgroundImage': backgroundImage,
      'backgroundImageLandscape': backgroundImageLandscape,
      'coins': coins,
      'totalCoinsEarned': totalCoinsEarned,
      'totalCoinsSpent': totalCoinsSpent,
      'sync_seq': syncSeq,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return User(
      id: (map['id'] as String?) ?? '',
      nickname: (map['nickname'] as String?) ?? 'User',
      avatarUrl: map['avatarUrl'] as String?,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      lastLoginAt: tryParseDateTime(map['lastLoginAt']),
      signature: map['signature'] as String?,
      gender: map['gender'] as String?,
      birthday: map['birthday'] as String?,
      location: map['location'] as String?,
      bio: map['bio'] as String?,
      // 老库无此列时为 null，视为未设置（用昵称回退），不炸
      chatAlias: map['chatAlias'] as String?,
      status: map['status'] as String?,
      backgroundImage: map['backgroundImage'] as String?,
      backgroundImageLandscape: map['backgroundImageLandscape'] as String?,
      coins: map['coins'] as int? ?? 100,
      totalCoinsEarned: map['totalCoinsEarned'] as int? ?? 100,
      totalCoinsSpent: map['totalCoinsSpent'] as int? ?? 0,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id, nickname, avatarUrl, createdAt, lastLoginAt,
        signature, gender, birthday, location, bio, chatAlias, status, backgroundImage,
        backgroundImageLandscape,
        coins, totalCoinsEarned, totalCoinsSpent, syncSeq,
      ];
}
