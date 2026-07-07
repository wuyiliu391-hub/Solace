import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/permission_service.dart';

/// 矩形封面选择器（图库/拍照），用于故事书封面
class CoverPicker extends StatelessWidget {
  final String? coverUrl;
  final ValueChanged<String?> onSelected;
  final double height;

  const CoverPicker({
    super.key,
    required this.coverUrl,
    required this.onSelected,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showOptions(context),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: (coverUrl != null && coverUrl!.isNotEmpty)
            ? Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl!.startsWith('http')
                      ? Image.network(coverUrl!, fit: BoxFit.cover)
                      : Image.file(File(coverUrl!), fit: BoxFit.cover),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black54,
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 32, color: cs.primary.withOpacity(0.6)),
                  const SizedBox(height: 6),
                  Text('选择封面',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.5))),
                ],
              ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(context, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(context, ImageSource.camera);
              },
            ),
            if (coverUrl != null && coverUrl!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error),
                title: const Text('移除封面'),
                onTap: () {
                  Navigator.pop(ctx);
                  onSelected(null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    try {
      bool ok;
      if (source == ImageSource.camera) {
        ok = await PermissionService.hasCameraPermission() ||
            await PermissionService.requestCameraPermission();
      } else {
        ok = await PermissionService.hasStoragePermission() ||
            await PermissionService.requestStoragePermission();
      }
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要权限才能选择图片')),
          );
        }
        return;
      }
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked != null) {
        final cached = await _copyToCache(picked.path);
        onSelected(cached ?? picked.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择失败: $e')),
        );
      }
    }
  }

  Future<String?> _copyToCache(String src) async {
    try {
      final dir = Directory.systemTemp;
      final ext = src.contains('.') ? src.split('.').last : 'jpg';
      final dest =
          '${dir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(src).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }
}
