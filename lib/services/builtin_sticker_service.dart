import 'dart:convert';
import 'package:flutter/services.dart';

class BuiltinSticker {
  final String id;
  final String file;
  final String name;
  final List<String> tags;
  final String emotion;
  final double intensity;

  BuiltinSticker({
    required this.id,
    required this.file,
    required this.name,
    required this.tags,
    required this.emotion,
    required this.intensity,
  });

  factory BuiltinSticker.fromJson(Map<String, dynamic> json) {
    return BuiltinSticker(
      id: json['id'] as String,
      file: json['file'] as String,
      name: json['name'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      emotion: json['emotion'] as String,
      intensity: (json['intensity'] as num).toDouble(),
    );
  }
}

class BuiltinStickerPack {
  final String packName;
  final String packId;
  final String description;
  final List<BuiltinSticker> stickers;

  BuiltinStickerPack({
    required this.packName,
    required this.packId,
    required this.description,
    required this.stickers,
  });

  factory BuiltinStickerPack.fromJson(Map<String, dynamic> json) {
    return BuiltinStickerPack(
      packName: json['packName'] as String,
      packId: json['packId'] as String,
      description: json['description'] as String,
      stickers: (json['stickers'] as List<dynamic>)
          .map((s) => BuiltinSticker.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BuiltinStickerService {
  static BuiltinStickerPack? _cachedPack;

  static Future<BuiltinStickerPack> loadDefaultPack() async {
    if (_cachedPack != null) return _cachedPack!;

    final jsonString = await rootBundle.loadString(
      'assets/stickers/default_pack/metadata.json',
    );
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    _cachedPack = BuiltinStickerPack.fromJson(json);
    return _cachedPack!;
  }

  static BuiltinSticker? findStickerById(String id) {
    if (_cachedPack == null) return null;
    try {
      return _cachedPack!.stickers.firstWhere((s) => s.id == id);
    } catch (_) {
      final lower = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      try {
        return _cachedPack!.stickers.firstWhere(
          (s) => s.id.toLowerCase() == lower || s.id.toLowerCase().contains(lower) || lower.contains(s.id.toLowerCase()),
        );
      } catch (_) {
        return null;
      }
    }
  }

  static String getStickerDescription(String id) {
    final sticker = findStickerById(id);
    if (sticker == null) return '一个表情包';
    return '【${sticker.name}】表情，代表${sticker.tags.join('、')}的情绪';
  }

  static String getStickerAssetPath(String fileName) {
    return 'assets/stickers/default_pack/$fileName';
  }

  static void clearCache() {
    _cachedPack = null;
  }
}
