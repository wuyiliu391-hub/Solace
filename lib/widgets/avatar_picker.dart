import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/permission_service.dart';
import 'image_cropper.dart';

class AvatarPicker extends StatefulWidget {
  final String? currentAvatar;
  final Function(String?) onAvatarSelected;

  /// 「清除头像」回调。留空则不显示清除按钮。
  ///
  /// 注意：清除**不能**复用 [onAvatarSelected] 传 null —— 各模型的
  /// `copyWith` 都是 `avatarUrl ?? this.avatarUrl` 写法，传 null 会被忽略，
  /// 旧头像反而清不掉。必须由调用方显式走清除分支。
  final VoidCallback? onAvatarCleared;

  final double size;

  const AvatarPicker({
    super.key,
    required this.currentAvatar,
    required this.onAvatarSelected,
    this.onAvatarCleared,
    this.size = 100,
  });

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            debugPrint('头像被点击了');
            _showImageSourceOptions(context);
          },
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                ClipOval(
                  child: _buildAvatarImage(context),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: widget.size * 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '点击选择头像',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarImage(BuildContext context) {
    final avatar = widget.currentAvatar;
    if (avatar == null || avatar.isEmpty) {
      return _buildDefaultAvatar(context);
    }

    // 本地文件路径
    if (avatar.startsWith('/')) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: Image.file(
            File(avatar),
            fit: BoxFit.cover,
            width: widget.size,
            height: widget.size,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultAvatar(context);
            },
          ),
        ),
      );
    }

    // 网络图片
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.network(
          avatar,
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar(context);
          },
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.favorite,
          size: widget.size * 0.35,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
        ),
      ),
    );
  }

  void _showImageSourceOptions(BuildContext context) {
    debugPrint('显示选择图片选项');
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '选择头像',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                Icons.photo_library,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('从相册选择'),
              onTap: () {
                debugPrint('选择从相册');
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.camera_alt,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('拍照'),
              onTap: () {
                debugPrint('选择拍照');
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if ((widget.currentAvatar?.isNotEmpty) == true &&
                widget.onAvatarCleared != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('清除头像'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onAvatarCleared!();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      debugPrint('开始选择图片，来源: $source');

      bool hasPermission = false;

      if (source == ImageSource.camera) {
        debugPrint('检查相机权限');
        hasPermission = await PermissionService.hasCameraPermission();
        if (!hasPermission) {
          debugPrint('申请相机权限');
          hasPermission = await PermissionService.requestCameraPermission();
        }
      } else {
        debugPrint('检查存储权限');
        hasPermission = await PermissionService.hasStoragePermission();
        if (!hasPermission) {
          debugPrint('申请存储权限');
          hasPermission = await PermissionService.requestStoragePermission();
        }
      }

      if (!hasPermission) {
        debugPrint('权限被拒绝');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要权限才能选择图片，请在设置中授权')),
          );
        }
        return;
      }

      // 这里不再压到 512：要留给裁剪器足够的像素，
      // 否则放大后重新裁剪会糊。裁剪器内部会再统一缩到 2048 并输出 512。
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (pickedFile == null) return;

      // 交给裁剪器：可自由缩放 / 拖动 / 旋转，输出正方形并直接落到
      // docs/avatars（持久目录，不会被清缓存清掉）。
      final cropped =
          await showImageCropper(context, File(pickedFile.path));
      if (cropped == null) return;
      if (!mounted) return;
      widget.onAvatarSelected(cropped);
    } catch (e) {
      debugPrint('选择图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择失败: $e')),
        );
      }
    }
  }
}
