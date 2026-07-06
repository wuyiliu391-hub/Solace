/// 角色生成图片记录模型
///
/// 每个角色拥有独立的图像画廊，所有生成图片自动归档，
/// 后续生成可复用旧图作为二次参考，进一步强化形象统一。
class CharacterImage {
  final String id;
  final String characterId;
  final String userId;
  final String localPath;
  final String? promptUsed;
  final String? sceneDescription;
  final String? referenceImagePath;
  final int generationSeed;
  final String resolution;
  final String styleLock;
  final DateTime createdAt;
  final bool isFavorite;

  const CharacterImage({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.localPath,
    this.promptUsed,
    this.sceneDescription,
    this.referenceImagePath,
    this.generationSeed = -1,
    this.resolution = '1024x1792',
    this.styleLock = 'anime',
    required this.createdAt,
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'characterId': characterId,
      'userId': userId,
      'localPath': localPath,
      'promptUsed': promptUsed,
      'sceneDescription': sceneDescription,
      'referenceImagePath': referenceImagePath,
      'generationSeed': generationSeed,
      'resolution': resolution,
      'styleLock': styleLock,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  factory CharacterImage.fromMap(Map<String, dynamic> map) {
    return CharacterImage(
      id: map['id'] as String,
      characterId: map['characterId'] as String,
      userId: map['userId'] as String,
      localPath: map['localPath'] as String,
      promptUsed: map['promptUsed'] as String?,
      sceneDescription: map['sceneDescription'] as String?,
      referenceImagePath: map['referenceImagePath'] as String?,
      generationSeed: (map['generationSeed'] as int?) ?? -1,
      resolution: (map['resolution'] as String?) ?? '1024x1792',
      styleLock: (map['styleLock'] as String?) ?? 'anime',
      createdAt: DateTime.parse(map['createdAt'] as String),
      isFavorite: (map['isFavorite'] as int?) == 1,
    );
  }

  CharacterImage copyWith({
    String? id,
    String? characterId,
    String? userId,
    String? localPath,
    String? promptUsed,
    String? sceneDescription,
    String? referenceImagePath,
    int? generationSeed,
    String? resolution,
    String? styleLock,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return CharacterImage(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      localPath: localPath ?? this.localPath,
      promptUsed: promptUsed ?? this.promptUsed,
      sceneDescription: sceneDescription ?? this.sceneDescription,
      referenceImagePath: referenceImagePath ?? this.referenceImagePath,
      generationSeed: generationSeed ?? this.generationSeed,
      resolution: resolution ?? this.resolution,
      styleLock: styleLock ?? this.styleLock,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
