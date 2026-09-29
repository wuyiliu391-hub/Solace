/// 已抓到的娃娃（存入「娃娃柜」）。
///
/// 纯本地存储：以 JSON 列表形式存进 SharedPreferences（见 storage KV 封装），
/// 不新增数据库表，避免 schema 迁移。
class OwnedDoll {
  final String uid; // 每只娃娃实例唯一 id
  final String dollId; // 对应 ClawDoll.id
  final String name;
  final String emoji;
  final String rarity; // DollRarity.name：common / rare / hidden
  final DateTime obtainedAt;
  final String? characterId; // 抓这只娃娃时的陪玩角色
  final String? characterName;
  final bool gifted; // 是否已送给角色

  const OwnedDoll({
    required this.uid,
    required this.dollId,
    required this.name,
    required this.emoji,
    required this.rarity,
    required this.obtainedAt,
    this.characterId,
    this.characterName,
    this.gifted = false,
  });

  OwnedDoll copyWith({bool? gifted}) => OwnedDoll(
        uid: uid,
        dollId: dollId,
        name: name,
        emoji: emoji,
        rarity: rarity,
        obtainedAt: obtainedAt,
        characterId: characterId,
        characterName: characterName,
        gifted: gifted ?? this.gifted,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'dollId': dollId,
        'name': name,
        'emoji': emoji,
        'rarity': rarity,
        'obtainedAt': obtainedAt.toIso8601String(),
        'characterId': characterId,
        'characterName': characterName,
        'gifted': gifted,
      };

  factory OwnedDoll.fromJson(Map<String, dynamic> json) => OwnedDoll(
        uid: json['uid'] as String,
        dollId: json['dollId'] as String? ?? '',
        name: json['name'] as String? ?? '娃娃',
        emoji: json['emoji'] as String? ?? '🧸',
        rarity: json['rarity'] as String? ?? 'common',
        obtainedAt: DateTime.tryParse(json['obtainedAt'] as String? ?? '') ??
            DateTime.now(),
        characterId: json['characterId'] as String?,
        characterName: json['characterName'] as String?,
        gifted: json['gifted'] as bool? ?? false,
      );
}
