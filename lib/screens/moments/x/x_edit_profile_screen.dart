import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../blocs/auth/auth_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/user.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../services/permission_service.dart';
import '../../../widgets/moments/circular_avatar.dart';

class XEditProfileScreen extends StatefulWidget {
  final User user;

  const XEditProfileScreen({super.key, required this.user});

  @override
  State<XEditProfileScreen> createState() => _XEditProfileScreenState();
}

class _XEditProfileScreenState extends State<XEditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  String? _avatarPath;
  String? _backgroundPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.nickname);
    _bioController = TextEditingController(
      text: widget.user.bio?.isNotEmpty == true
          ? widget.user.bio
          : widget.user.signature ?? '',
    );
    _locationController =
        TextEditingController(text: widget.user.location ?? '');
    _websiteController = TextEditingController(text: widget.user.status ?? '');
    _nameController.addListener(_refreshHeaderPreview);
    _avatarPath = widget.user.avatarUrl;
    _backgroundPath = widget.user.backgroundImage;
  }

  @override
  void dispose() {
    _nameController.removeListener(_refreshHeaderPreview);
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _refreshHeaderPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(
            '取消',
            style: TextStyle(
              color: MomentsTheme.textPrimary(context),
              fontSize: 16,
            ),
          ),
        ),
        title: Text(
          '编辑资料',
          style: TextStyle(
            color: MomentsTheme.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: MomentsTheme.textPrimary(context),
                foregroundColor: MomentsTheme.background(context),
                disabledBackgroundColor:
                    MomentsTheme.textSecondary(context).withOpacity(0.35),
                shape: const StadiumBorder(),
                minimumSize: const Size(68, 34),
              ),
              child: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MomentsTheme.background(context),
                      ),
                    )
                  : const Text('保存',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: MomentsTheme.divider(context)),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _headerEditor(),
          const SizedBox(height: 18),
          _field('名称', _nameController, maxLength: 30),
          _field('简介', _bioController, maxLength: 160, maxLines: 3),
          _field('位置', _locationController, maxLength: 30),
          _field('网站', _websiteController, maxLength: 60),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _headerEditor() {
    return SizedBox(
      height: 198,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _pickImage(isBackground: true),
            child: SizedBox(
              height: 136,
              width: double.infinity,
              child:
                  _backgroundPath != null && File(_backgroundPath!).existsSync()
                      ? Image.file(File(_backgroundPath!), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: MomentsTheme.surface(context)),
                        )
                      : Container(color: MomentsTheme.surface(context)),
            ),
          ),
          Positioned.fill(
            top: 0,
            bottom: 62,
            child: Center(
              child:
                  _cameraOverlay(onTap: () => _pickImage(isBackground: true)),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _pickImage(isBackground: false),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: MomentsTheme.background(context),
                      shape: BoxShape.circle,
                    ),
                    child: CircularAvatar(
                      avatarPath: _avatarPath,
                      name: _nameController.text.trim().isEmpty
                          ? widget.user.nickname
                          : _nameController.text.trim(),
                      radius: 38,
                    ),
                  ),
                  _cameraOverlay(onTap: () => _pickImage(isBackground: false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraOverlay({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.camera_alt_outlined,
            color: Colors.white, size: 20),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MomentsTheme.divider(context), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: TextStyle(
          color: MomentsTheme.textPrimary(context),
          fontSize: 17,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: MomentsTheme.textSecondary(context),
            fontSize: 14,
          ),
          border: InputBorder.none,
          counterStyle: TextStyle(
            color: MomentsTheme.textSecondary(context),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage({required bool isBackground}) async {
    if (!await PermissionService.requestStoragePermission()) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (picked == null) return;

    final path = await _copyToPersistentPath(
      picked.path,
      folder: isBackground ? 'profile_backgrounds' : 'avatars',
      fileName: isBackground ? 'user_bg' : 'user_avatar',
    );

    if (!mounted) return;
    setState(() {
      if (isBackground) {
        _backgroundPath = path;
      } else {
        _avatarPath = path;
      }
    });
  }

  Future<String> _copyToPersistentPath(
    String sourcePath, {
    required String folder,
    required String fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/$folder');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${targetDir.path}/${fileName}_$stamp.$ext';
    await source.copy(destPath);
    return destPath;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }

    setState(() => _saving = true);
    final updatedUser = widget.user.copyWith(
      nickname: name,
      avatarUrl: _avatarPath,
      backgroundImage: _backgroundPath,
      bio: _bioController.text.trim(),
      signature: _bioController.text.trim(),
      location: _locationController.text.trim(),
      status: _websiteController.text.trim(),
    );

    try {
      final storage = context.read<LocalStorageRepository>();
      await storage.saveUser(updatedUser);
      if (!mounted) return;

      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        authBloc.add(AuthUserUpdated(updatedUser));
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }
}
