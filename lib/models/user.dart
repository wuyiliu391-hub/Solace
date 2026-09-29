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

  // 虚拟货币
  final int coins;                // 金币数量
  final int totalCoinsEarned;     // 累计获得金币
  final int totalCoinsSpent;      // 累计花费金币

  // 自定义状态
  final String? status;            // 当前状态（开心、忙碌、emo等）
  final String? backgroundImage;   // 个人主页背景图
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
    this.status,
    this.backgroundImage,
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
    String? status,
    String? backgroundImage,
    int? syncSeq,
    int? coins,
    int? totalCoinsEarned,
    int? totalCoinsSpent,
  }) {
    return User(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      signature: signature ?? this.signature,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
      location: location ?? this.location,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      backgroundImage: backgroundImage ?? this.backgroundImage,
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
      'status': status,
      'backgroundImage': backgroundImage,
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
      status: map['status'] as String?,
      backgroundImage: map['backgroundImage'] as String?,
      coins: map['coins'] as int? ?? 100,
      totalCoinsEarned: map['totalCoinsEarned'] as int? ?? 100,
      totalCoinsSpent: map['totalCoinsSpent'] as int? ?? 0,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    id, nickname, avatarUrl, createdAt, lastLoginAt,
    signature, gender, birthday, location, bio, status, backgroundImage,
    coins, totalCoinsEarned, totalCoinsSpent, syncSeq,
  ];
}
