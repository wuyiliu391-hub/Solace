import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../config/moments_theme.dart';

/// 身份信息
class PostIdentity {
  String name;
  String handle;
  String? avatarPath;
  String? gender; // male / female / other / null
  bool isVerified; // 蓝标认证

  PostIdentity({
    required this.name,
    required this.handle,
    this.avatarPath,
    this.gender,
    this.isVerified = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'handle': handle,
        'avatarPath': avatarPath,
        'gender': gender,
        'isVerified': isVerified,
      };

  factory PostIdentity.fromJson(Map<String, dynamic> json) => PostIdentity(
        name: json['name'] ?? '',
        handle: json['handle'] ?? '',
        avatarPath: json['avatarPath'],
        gender: json['gender'],
        isVerified: json['isVerified'] == true,
      );

  /// 性别图标
  IconData? get genderIcon {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      case 'other':
        return Icons.transgender;
      default:
        return null;
    }
  }

  /// 性别颜色
  Color get genderColor {
    switch (gender) {
      case 'male':
        return const Color(0xFF1DA1F2);
      case 'female':
        return const Color(0xFFF472B6);
      case 'other':
        return const Color(0xFF9C5A9A);
      default:
        return Colors.transparent;
    }
  }
}

/// 身份选择器 — 发帖/回复/点赞前选择用哪个身份
class IdentityPicker extends StatefulWidget {
  final PostIdentity currentIdentity;
  final ValueChanged<PostIdentity> onIdentityChanged;

  const IdentityPicker({
    super.key,
    required this.currentIdentity,
    required this.onIdentityChanged,
  });

  @override
  State<IdentityPicker> createState() => _IdentityPickerState();
}

class _IdentityPickerState extends State<IdentityPicker> {
  List<PostIdentity> _savedIdentities = [];

  @override
  void initState() {
    super.initState();
    _loadSavedIdentities();
  }

  Future<void> _loadSavedIdentities() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('x_post_identities');
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        setState(() {
          _savedIdentities =
              list.map((e) => PostIdentity.fromJson(e)).toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveIdentities() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'x_post_identities',
      jsonEncode(_savedIdentities.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPickerSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MomentsTheme.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: MomentsTheme.divider(context),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像
            _buildAvatar(widget.currentIdentity, 18),
            const SizedBox(width: 8),
            // 名字
            Text(
              widget.currentIdentity.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: MomentsTheme.textPrimary(context),
              ),
            ),
            // 性别图标
            if (widget.currentIdentity.genderIcon != null) ...[
              const SizedBox(width: 4),
              Icon(
                widget.currentIdentity.genderIcon,
                size: 14,
                color: widget.currentIdentity.genderColor,
              ),
            ],
            // 认证蓝标
            if (widget.currentIdentity.isVerified) ...[
              const SizedBox(width: 4),
              Icon(
                MomentsTheme.blueTick,
                size: 14,
                color: MomentsTheme.primary(context),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: MomentsTheme.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(PostIdentity identity, double radius) {
    if (identity.avatarPath != null && identity.avatarPath!.isNotEmpty) {
      if (identity.avatarPath!.startsWith('http')) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(identity.avatarPath!),
        );
      }
      final file = File(identity.avatarPath!);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: FileImage(file),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: MomentsTheme.primary(context).withOpacity(0.2),
      child: Text(
        identity.name.isNotEmpty ? identity.name[0] : '?',
        style: TextStyle(
          fontSize: radius * 0.8,
          color: MomentsTheme.primary(context),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: MomentsTheme.cardBackground(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖拽条
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: MomentsTheme.divider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '选择身份',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: MomentsTheme.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _createNewIdentity(ctx, setSheetState),
                      icon: Icon(Icons.add,
                          color: MomentsTheme.primary(context)),
                      label: Text('新建身份',
                          style: TextStyle(
                              color: MomentsTheme.primary(context))),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 0.5,
                  color: MomentsTheme.divider(context)),
              // 身份列表
              Expanded(
                child: ListView(
                  children: [
                    // 当前身份
                    _identityTile(
                      widget.currentIdentity,
                      isSelected: true,
                      onTap: () => Navigator.pop(ctx),
                    ),
                    Divider(
                        height: 0.5,
                        color: MomentsTheme.divider(context)),
                    // 保存的身份
                    ...List.generate(_savedIdentities.length, (i) {
                      final id = _savedIdentities[i];
                      return _identityTile(
                        id,
                        isSelected: false,
                        onTap: () {
                          widget.onIdentityChanged(id);
                          Navigator.pop(ctx);
                        },
                        onDelete: () {
                          setSheetState(() {
                            _savedIdentities.removeAt(i);
                          });
                          _saveIdentities();
                        },
                        onEdit: () =>
                            _editIdentity(ctx, setSheetState, i),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identityTile(
    PostIdentity identity, {
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    VoidCallback? onEdit,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(identity, 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        identity.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: MomentsTheme.textPrimary(context),
                        ),
                      ),
                      if (identity.genderIcon != null) ...[
                        const SizedBox(width: 4),
                        Icon(identity.genderIcon,
                            size: 16, color: identity.genderColor),
                      ],
                      if (identity.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(MomentsTheme.blueTick,
                            size: 16, color: MomentsTheme.primary(context)),
                      ],
                    ],
                  ),
                  Text(
                    '@${identity.handle}',
                    style: TextStyle(
                      fontSize: 14,
                      color: MomentsTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: MomentsTheme.primary(context))
            else ...[
              if (onEdit != null)
                IconButton(
                  icon: Icon(Icons.edit,
                      size: 18,
                      color: MomentsTheme.textSecondary(context)),
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: MomentsTheme.like(context)),
                  onPressed: onDelete,
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _createNewIdentity(
      BuildContext ctx, StateSetter setSheetState) {
    _showIdentityEditor(ctx, null, (identity) {
      setSheetState(() {
        _savedIdentities.add(identity);
      });
      _saveIdentities();
      widget.onIdentityChanged(identity);
    });
  }

  void _editIdentity(
      BuildContext ctx, StateSetter setSheetState, int index) {
    _showIdentityEditor(ctx, _savedIdentities[index], (identity) {
      setSheetState(() {
        _savedIdentities[index] = identity;
      });
      _saveIdentities();
      widget.onIdentityChanged(identity);
    });
  }

  void _showIdentityEditor(
    BuildContext ctx,
    PostIdentity? existing,
    ValueChanged<PostIdentity> onSave,
  ) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final handleCtrl = TextEditingController(text: existing?.handle ?? '');
    String? avatarPath = existing?.avatarPath;
    String? gender = existing?.gender;
    bool isVerified = existing?.isVerified ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setEditorState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx2).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: MomentsTheme.cardBackground(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing != null ? '编辑身份' : '新建身份',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: MomentsTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 头像选择
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                            source: ImageSource.gallery);
                        if (picked != null) {
                          setEditorState(() => avatarPath = picked.path);
                        }
                      },
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor:
                            MomentsTheme.primary(context).withOpacity(0.2),
                        backgroundImage: avatarPath != null
                            ? (avatarPath!.startsWith('http')
                                ? NetworkImage(avatarPath!)
                                : FileImage(File(avatarPath!))
                                    as ImageProvider)
                            : null,
                        child: avatarPath == null
                            ? Icon(Icons.camera_alt,
                                color: MomentsTheme.primary(context))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 名字
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: MomentsTheme.textPrimary(context)),
                    decoration: InputDecoration(
                      labelText: '昵称',
                      labelStyle: TextStyle(
                          color: MomentsTheme.textSecondary(context)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      prefixIcon: Icon(Icons.person,
                          color: MomentsTheme.primary(context)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // handle
                  TextField(
                    controller: handleCtrl,
                    style: TextStyle(
                        color: MomentsTheme.textPrimary(context)),
                    decoration: InputDecoration(
                      labelText: 'ID（@handle）',
                      labelStyle: TextStyle(
                          color: MomentsTheme.textSecondary(context)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      prefixIcon: Icon(Icons.alternate_email,
                          color: MomentsTheme.primary(context)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 性别选择
                  Text(
                    '性别',
                    style: TextStyle(
                      fontSize: 14,
                      color: MomentsTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _genderChip('male', '男', Icons.male,
                          const Color(0xFF1DA1F2), gender, (g) {
                        setEditorState(() => gender = g);
                      }),
                      const SizedBox(width: 8),
                      _genderChip('female', '女', Icons.female,
                          const Color(0xFFF472B6), gender, (g) {
                        setEditorState(() => gender = g);
                      }),
                      const SizedBox(width: 8),
                      _genderChip('other', '其他', Icons.transgender,
                          const Color(0xFF9C5A9A), gender, (g) {
                        setEditorState(() => gender = g);
                      }),
                      const SizedBox(width: 8),
                      _genderChip(null, '不设', null,
                          MomentsTheme.textSecondary(context), gender,
                          (g) {
                        setEditorState(() => gender = g);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 认证蓝标
                  Row(
                    children: [
                      Icon(MomentsTheme.blueTick,
                          size: 20, color: MomentsTheme.primary(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '认证蓝标',
                          style: TextStyle(
                            fontSize: 15,
                            color: MomentsTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      Switch(
                        value: isVerified,
                        activeColor: MomentsTheme.primary(context),
                        onChanged: (v) {
                          setEditorState(() => isVerified = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 保存按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        final handle = handleCtrl.text.trim();
                        if (name.isEmpty || handle.isEmpty) return;
                        onSave(PostIdentity(
                          name: name,
                          handle: handle,
                          avatarPath: avatarPath,
                          gender: gender,
                          isVerified: isVerified,
                        ));
                        Navigator.pop(ctx2);
                        Navigator.pop(ctx); // 关闭选择器
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MomentsTheme.primary(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('保存'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String? value, String label, IconData? icon,
      Color color, String? current, ValueChanged<String?> onTap) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : MomentsTheme.divider(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? color : MomentsTheme.textSecondary(context)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? color : MomentsTheme.textSecondary(context),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
