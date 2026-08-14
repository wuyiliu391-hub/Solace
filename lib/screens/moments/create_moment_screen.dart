import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/moment.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/permission_service.dart';
import '../../services/moment_interaction_service.dart';


class CreateMomentScreen extends StatefulWidget {
  const CreateMomentScreen({super.key});

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

class _CreateMomentScreenState extends State<CreateMomentScreen> {
  static const double _cardRadius = 16.0;

  final _textController = TextEditingController();
  final List<String> _selectedImages = [];
  bool _isLoading = false;
  MomentVisibility _visibility = MomentVisibility.public;

  /// 「不让谁看」：被屏蔽的角色 id
  final Set<String> _blockedCharacterIds = {};
  List<AICharacter>? _characters;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _getVisibilityLabel(MomentVisibility visibility) {
    switch (visibility) {
      case MomentVisibility.public:
        return '公开';
      case MomentVisibility.private:
        return '仅自己可见';
      case MomentVisibility.intimate:
        return '亲密好友可见';
      case MomentVisibility.normal:
        return '好友可见';
    }
  }

  IconData _getVisibilityIcon(MomentVisibility visibility) {
    switch (visibility) {
      case MomentVisibility.public:
        return Icons.public;
      case MomentVisibility.private:
        return Icons.lock;
      case MomentVisibility.intimate:
        return Icons.favorite;
      case MomentVisibility.normal:
        return Icons.people;
    }
  }

  void _showVisibilityPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择可见范围',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 20),
            ...MomentVisibility.values.map((v) => ListTile(
                  leading:
                      Icon(_getVisibilityIcon(v), color: colorScheme.primary),
                  title: Text(_getVisibilityLabel(v),
                      style: TextStyle(
                          color: colorScheme.onSurface, fontSize: 15)),
                  subtitle: Text(_getVisibilityDescription(v),
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  trailing: _visibility == v
                      ? Icon(Icons.check_circle, color: colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() => _visibility = v);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _getVisibilityDescription(MomentVisibility visibility) {
    switch (visibility) {
      case MomentVisibility.public:
        return '所有 AI 都能看到';
      case MomentVisibility.private:
        return '只有自己能看到';
      case MomentVisibility.intimate:
        return '亲密度 ≥ 60 的 AI 可见';
      case MomentVisibility.normal:
        return '亲密度 ≥ 30 的 AI 可见';
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      bool hasPermission = false;

      if (source == ImageSource.camera) {
        hasPermission = await PermissionService.hasCameraPermission();
        if (!hasPermission) {
          hasPermission = await PermissionService.requestCameraPermission();
        }
      } else {
        hasPermission = await PermissionService.hasStoragePermission();
        if (!hasPermission) {
          hasPermission = await PermissionService.requestStoragePermission();
        }
      }

      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要权限才能选择图片')),
        );
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final localPath = await _copyToCache(pickedFile.path);
        setState(() {
          if (_selectedImages.length < 9) {
            _selectedImages.add(localPath ?? pickedFile.path);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('最多只能选择9张图片')),
            );
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  Future<String?> _copyToCache(String sourcePath) async {
    try {
      final dir = Directory.systemTemp;
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final dest =
          '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(sourcePath).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('复制图片到缓存失败: $e');
      return null;
    }
  }

  Future<void> _publishMoment() async {
    if (_textController.text.trim().isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入内容或选择图片')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      final moment = Moment(
        id: const Uuid().v4(),
        userId: user.id,
        userName: user.nickname,
        userAvatar: user.avatarUrl,
        content: _textController.text.trim(),
        images: _selectedImages,
        type: _selectedImages.isEmpty
            ? MomentType.text
            : _selectedImages.length == 1
                ? MomentType.image
                : MomentType.mixed,
        createdAt: DateTime.now(),
        visibility: _visibility,
        source: MomentSource.normal,
        blockedUserIds: _blockedCharacterIds.toList(),
      );

      await storage.saveMoment(moment);

      // 角色按人设延迟点赞/评论用户动态
      unawaited(MomentInteractionService.instance.onUserPostedMoment(
        storage: storage,
        moment: moment,
        userId: user.id,
      ));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发布成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发布失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildTextCard(),
                    const SizedBox(height: 12),
                    _buildImageSection(),
                    const SizedBox(height: 12),
                    _buildPrivacyRow(),
                    const SizedBox(height: 12),
                    _buildVisibilityRow(),
                    const SizedBox(height: 12),
                    _buildBlockedRow(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_left,
                  size: 28, color: colorScheme.onSurface),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _isLoading ? null : _publishMoment,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: _isLoading
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Text('发布',
                      style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTextCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _textController,
        maxLines: null,
        minLines: 5,
        decoration: InputDecoration(
          hintText: '分享你的想法...',
          hintStyle:
              TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final int crossCount = 3;
    final double itemSize =
        (MediaQuery.of(context).size.width - 32 - (crossCount - 1) * 8) /
            crossCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ..._selectedImages.asMap().entries.map((entry) {
            final index = entry.key;
            final path = entry.value;
            return SizedBox(
              width: itemSize,
              height: itemSize,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      width: itemSize,
                      height: itemSize,
                      errorBuilder: (_, __, ___) => Container(
                        width: itemSize,
                        height: itemSize,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 32),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImages.removeAt(index);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withOpacity(0.54),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: colorScheme.surface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_selectedImages.length < 9)
            GestureDetector(
              onTap: () => _showImagePickerOptions(),
              child: SizedBox(
                width: itemSize,
                height: itemSize,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: colorScheme.outlineVariant, width: 1),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 36,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivacyRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded,
                size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('按隐私性',
                style: TextStyle(fontSize: 15, color: colorScheme.onSurface)),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 22, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showVisibilityPicker(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(_getVisibilityIcon(_visibility),
                size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text('谁可以看',
                style: TextStyle(fontSize: 15, color: colorScheme.onSurface)),
            const Spacer(),
            Text(_getVisibilityLabel(_visibility),
                style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 22, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final count = _blockedCharacterIds.length;
    return GestureDetector(
      onTap: () => _showBlockedPicker(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_off_rounded,
                size: 20, color: colorScheme.error),
            const SizedBox(width: 12),
            Text('不让谁看',
                style: TextStyle(fontSize: 15, color: colorScheme.onSurface)),
            const Spacer(),
            Text(
              count == 0 ? '所有人可见' : '已屏蔽 $count 位角色',
              style: TextStyle(
                fontSize: 14,
                color: count == 0
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.error,
                fontWeight: count == 0 ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 22, color: colorScheme.error),
          ],
        ),
      ),
    );
  }

  Future<void> _showBlockedPicker() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final colorScheme = Theme.of(context).colorScheme;
    _characters ??= await storage.getAllAICharacters();
    final chars = (_characters ?? [])
        .where((c) => !c.isHidden)
        .toList();
    if (chars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可选的 AI 角色')),
      );
      return;
    }

    // 打开选择器时同步一次最新名单（可能已有角色新增）
    if (!mounted) return;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('不让谁看到这条动态',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...chars.map((c) {
                        final checked =
                            _blockedCharacterIds.contains(c.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(c.name,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: colorScheme.onSurface)),
                          subtitle: Text('屏蔽后 TA 看不到这条动态，也不会来互动',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant)),
                          onChanged: (v) {
                            setSheetState(() {
                              if (v == true) {
                                _blockedCharacterIds.add(c.id);
                              } else {
                                _blockedCharacterIds.remove(c.id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(ctx, Set.of(_blockedCharacterIds)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('完成',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() {
        _blockedCharacterIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  void _showImagePickerOptions() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.photo_library, color: colorScheme.primary),
              title: Text('从相册选择',
                  style: TextStyle(fontSize: 15, color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: colorScheme.primary),
              title: Text('拍照',
                  style: TextStyle(fontSize: 15, color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  }
