import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/sticker_pack.dart';
import '../repositories/local_storage_repository.dart';

class StickerPackService {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  StickerPackService(this._storage);

  Future<List<StickerPack>> getAllStickerPacks() async {
    return await _storage.getAllStickerPacks();
  }

  Future<StickerPack?> getStickerPack(String id) async {
    return await _storage.getStickerPack(id);
  }

  Future<StickerPack> createStickerPack({
    required String name,
    List<String>? initialImagePaths,
  }) async {
    final now = DateTime.now();
    final packId = _uuid.v4();
    
    List<StickerItem> stickers = [];
    String? coverImagePath;

    if (initialImagePaths != null && initialImagePaths.isNotEmpty) {
      for (final imagePath in initialImagePaths) {
        final sticker = await _addStickerFromImage(packId, imagePath);
        stickers.add(sticker);
      }
      coverImagePath = stickers.first.imagePath;
    }

    final pack = StickerPack(
      id: packId,
      name: name,
      coverImagePath: coverImagePath,
      stickers: stickers,
      createdAt: now,
      updatedAt: now,
    );

    await _storage.saveStickerPack(pack);
    return pack;
  }

  Future<StickerItem> addStickerToPack({
    required String packId,
    required String imagePath,
    String? name,
  }) async {
    final pack = await _storage.getStickerPack(packId);
    if (pack == null) {
      throw Exception('表情包不存在');
    }

    final sticker = await _addStickerFromImage(packId, imagePath, name: name);
    
    final updatedStickers = [...pack.stickers, sticker];
    final updatedPack = pack.copyWith(
      stickers: updatedStickers,
      coverImagePath: pack.coverImagePath ?? sticker.imagePath,
      updatedAt: DateTime.now(),
    );

    await _storage.saveStickerPack(updatedPack);
    return sticker;
  }

  Future<StickerItem> _addStickerFromImage(
    String packId,
    String sourcePath, {
    String? name,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final stickersDir = Directory(p.join(appDir.path, 'stickers', packId));
      if (!await stickersDir.exists()) {
        await stickersDir.create(recursive: true);
      }

      final stickerId = _uuid.v4();
      final extension = p.extension(sourcePath);
      final newPath = p.join(stickersDir.path, '$stickerId$extension');

      final sourceFile = File(sourcePath);
      await sourceFile.copy(newPath);

      return StickerItem(
        id: stickerId,
        imagePath: newPath,
        name: name,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('添加表情失败: $e');
      rethrow;
    }
  }

  Future<void> removeStickerFromPack({
    required String packId,
    required String stickerId,
  }) async {
    final pack = await _storage.getStickerPack(packId);
    if (pack == null) return;

    final sticker = pack.stickers.firstWhere(
      (s) => s.id == stickerId,
      orElse: () => throw Exception('表情不存在'),
    );

    try {
      final file = File(sticker.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除表情文件失败: $e');
    }

    final updatedStickers = pack.stickers.where((s) => s.id != stickerId).toList();
    final newCover = updatedStickers.isEmpty 
        ? null 
        : (pack.coverImagePath == sticker.imagePath 
            ? updatedStickers.first.imagePath 
            : pack.coverImagePath);

    final updatedPack = pack.copyWith(
      stickers: updatedStickers,
      coverImagePath: newCover,
      updatedAt: DateTime.now(),
    );

    await _storage.saveStickerPack(updatedPack);
  }

  Future<void> deleteStickerPack(String packId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final stickersDir = Directory(p.join(appDir.path, 'stickers', packId));
      if (await stickersDir.exists()) {
        await stickersDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除表情包文件夹失败: $e');
    }

    await _storage.deleteStickerPack(packId);
  }

  Future<void> renameStickerPack(String packId, String newName) async {
    final pack = await _storage.getStickerPack(packId);
    if (pack == null) return;

    final updatedPack = pack.copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );

    await _storage.saveStickerPack(updatedPack);
  }

  Future<StickerPack> createStickerFromImageDirectly({
    required String imagePath,
    String? packName,
  }) async {
    final name = packName ?? '我的表情包 ${DateTime.now().month}-${DateTime.now().day}';
    return await createStickerPack(name: name, initialImagePaths: [imagePath]);
  }
}
