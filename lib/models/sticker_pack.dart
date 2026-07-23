import 'dart:convert';
import 'package:equatable/equatable.dart';

class StickerItem extends Equatable {
  final String id;
  final String imagePath;
  final String? name;
  final DateTime createdAt;

  const StickerItem({
    required this.id,
    required this.imagePath,
    this.name,
    required this.createdAt,
  });

  StickerItem copyWith({
    String? id,
    String? imagePath,
    String? name,
    DateTime? createdAt,
  }) {
    return StickerItem(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StickerItem.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return StickerItem(
      id: (map['id'] as String?) ?? '',
      imagePath: (map['imagePath'] as String?) ?? '',
      name: map['name'] as String?,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, imagePath, name, createdAt];
}

class StickerPack extends Equatable {
  final String id;
  final String name;
  final String? coverImagePath;
  final List<StickerItem> stickers;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDefault;
  final int syncSeq;

  const StickerPack({
    required this.id,
    required this.name,
    this.coverImagePath,
    this.stickers = const [],
    required this.createdAt,
    this.updatedAt,
    this.isDefault = false,
    this.syncSeq = 0,
  });

  StickerPack copyWith({
    String? id,
    String? name,
    String? coverImagePath,
    List<StickerItem>? stickers,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDefault,
    int? syncSeq,
  }) {
    return StickerPack(
      id: id ?? this.id,
      name: name ?? this.name,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      stickers: stickers ?? this.stickers,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDefault: isDefault ?? this.isDefault,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coverImagePath': coverImagePath,
      'stickers': jsonEncode(stickers.map((s) => s.toMap()).toList()),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isDefault': isDefault ? 1 : 0,
      'sync_seq': syncSeq,
    };
  }

  factory StickerPack.fromMap(Map<String, dynamic> map) {
    List<StickerItem> stickersList = [];
    if (map['stickers'] != null) {
      final stickersJson = jsonDecode(map['stickers'] as String) as List;
      stickersList = stickersJson
          .map((s) => StickerItem.fromMap(s as Map<String, dynamic>))
          .toList();
    }

    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return StickerPack(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      coverImagePath: map['coverImagePath'] as String?,
      stickers: stickersList,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: tryParseDateTime(map['updatedAt']),
      isDefault: (map['isDefault'] as int?) == 1,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, name, coverImagePath, stickers, createdAt, updatedAt, isDefault, syncSeq];
}
