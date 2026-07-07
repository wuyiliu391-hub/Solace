import 'package:equatable/equatable.dart';

/// 虚拟手机 · 主记录
///
/// 每个 AI 角色拥有一部「专属虚拟手机」。这里的一切都是根据角色人设/背景
/// 由 LLM 虚构生成的模拟内容——不是任何真实设备的数据，不存在任何隐私泄露。
class VirtualPhone extends Equatable {
  final String id;
  final String characterId;

  /// 手机主人昵称（通常就是角色名，用于状态栏/标题展示）
  final String ownerName;

  /// 壁纸主色（ARGB int），默认粉色系
  final int wallpaperColor;

  /// 生成状态：empty(未生成) / generating / ready / failed
  final String status;

  /// 最近一次全量生成时间
  final DateTime? generatedAt;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final int syncSeq;

  const VirtualPhone({
    required this.id,
    required this.characterId,
    this.ownerName = '',
    this.wallpaperColor = 0xFFF472B6,
    this.status = 'empty',
    this.generatedAt,
    required this.createdAt,
    this.updatedAt,
    this.syncSeq = 0,
  });

  bool get isReady => status == 'ready';

  VirtualPhone copyWith({
    String? ownerName,
    int? wallpaperColor,
    String? status,
    DateTime? generatedAt,
    DateTime? updatedAt,
    int? syncSeq,
  }) {
    return VirtualPhone(
      id: id,
      characterId: characterId,
      ownerName: ownerName ?? this.ownerName,
      wallpaperColor: wallpaperColor ?? this.wallpaperColor,
      status: status ?? this.status,
      generatedAt: generatedAt ?? this.generatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'characterId': characterId,
        'ownerName': ownerName,
        'wallpaperColor': wallpaperColor,
        'status': status,
        'generatedAt': generatedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'sync_seq': syncSeq,
      };

  factory VirtualPhone.fromMap(Map<String, dynamic> map) => VirtualPhone(
        id: map['id'] as String,
        characterId: map['characterId'] as String,
        ownerName: map['ownerName'] as String? ?? '',
        wallpaperColor: (map['wallpaperColor'] as int?) ?? 0xFFF472B6,
        status: map['status'] as String? ?? 'empty',
        generatedAt: map['generatedAt'] != null
            ? DateTime.tryParse(map['generatedAt'] as String)
            : null,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: map['updatedAt'] != null
            ? DateTime.tryParse(map['updatedAt'] as String)
            : null,
        syncSeq: (map['sync_seq'] as int?) ?? (map['syncSeq'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, characterId, status, generatedAt];
}
