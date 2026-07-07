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

  /// 最近一次「生活推进」（增量追加）时，真实单聊的可见消息累计数。
  /// 用于对比"这台手机自上次更新以来，你俩又聊了多少"，作为自动推进的阈值依据。
  final int lastAdvanceMsgCount;

  /// 最近一次「生活推进」时间（用于冷却，避免频繁增量）。
  final DateTime? lastAdvanceAt;

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
    this.lastAdvanceMsgCount = 0,
    this.lastAdvanceAt,
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
    int? lastAdvanceMsgCount,
    DateTime? lastAdvanceAt,
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
      lastAdvanceMsgCount: lastAdvanceMsgCount ?? this.lastAdvanceMsgCount,
      lastAdvanceAt: lastAdvanceAt ?? this.lastAdvanceAt,
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
        'lastAdvanceMsgCount': lastAdvanceMsgCount,
        'lastAdvanceAt': lastAdvanceAt?.toIso8601String(),
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
        lastAdvanceMsgCount: (map['lastAdvanceMsgCount'] as int?) ?? 0,
        lastAdvanceAt: map['lastAdvanceAt'] != null
            ? DateTime.tryParse(map['lastAdvanceAt'] as String)
            : null,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: map['updatedAt'] != null
            ? DateTime.tryParse(map['updatedAt'] as String)
            : null,
        syncSeq: (map['sync_seq'] as int?) ?? (map['syncSeq'] as int?) ?? 0,
      );

  @override
  List<Object?> get props =>
      [id, characterId, status, generatedAt, lastAdvanceMsgCount, lastAdvanceAt];
}
