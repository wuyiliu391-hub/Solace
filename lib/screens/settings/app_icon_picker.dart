import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../repositories/local_storage_repository.dart';

/// 应用图标自定义界面
///
/// 支持：
/// - 6 种预设图标
/// - 自定义图片选择
/// - Android 自适应图标限制提示
class AppIconPicker extends StatefulWidget {
  const AppIconPicker({super.key});

  @override
  State<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<AppIconPicker> {
  final ImagePicker _picker = ImagePicker();

  // 预设图标列表：name → IconData/路径
  static const List<_PresetIcon> _presetIcons = [
    _PresetIcon(
      name: 'default',
      label: '默认',
      icon: Icons.favorite,
      color: Color(0xFFFF6B6B),
    ),
    _PresetIcon(
      name: 'pink_heart',
      label: '粉色爱心',
      icon: Icons.favorite,
      color: Color(0xFFFF8A9E),
    ),
    _PresetIcon(
      name: 'blue_star',
      label: '蓝色星星',
      icon: Icons.star,
      color: Color(0xFF6B9EFF),
    ),
    _PresetIcon(
      name: 'green_leaf',
      label: '绿色叶子',
      icon: Icons.eco,
      color: Color(0xFF6BCB77),
    ),
    _PresetIcon(
      name: 'purple_moon',
      label: '紫色月亮',
      icon: Icons.nightlight_round,
      color: Color(0xFF9C7CDB),
    ),
    _PresetIcon(
      name: 'orange_sun',
      label: '橙色太阳',
      icon: Icons.wb_sunny,
      color: Color(0xFFFFA726),
    ),
  ];

  String _selectedIcon = 'default';
  String? _customIconPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentIcon();
  }

  Future<void> _loadCurrentIcon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _customIconPath = prefs.getString('app_icon_path');
        if (_customIconPath != null && _customIconPath!.isNotEmpty) {
          _selectedIcon = 'custom';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCustomImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );

      if (image == null) return;

      // 复制图片到持久化目录
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'app_icon_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');

      setState(() {
        _customIconPath = savedImage.path;
        _selectedIcon = 'custom';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  Future<void> _saveIcon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? iconPath;
      if (_selectedIcon == 'custom' && _customIconPath != null) {
        iconPath = _customIconPath;
      }
      if (iconPath != null) {
        await prefs.setString('app_icon_path', iconPath);
      } else {
        await prefs.remove('app_icon_path');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('应用图标已保存')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('应用图标')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用图标'),
        centerTitle: true,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveIcon,
            child: const Text(
              '保存',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 16),

          // 当前预览
          _buildPreview(colorScheme),
          const SizedBox(height: 24),

          // Android 限制提示
          _buildInfoBanner(colorScheme),
          const SizedBox(height: 24),

          // 预设图标网格
          _buildSectionTitle('预设图标'),
          const SizedBox(height: 12),
          _buildPresetGrid(colorScheme),
          const SizedBox(height: 24),

          // 自定义图片
          _buildSectionTitle('自定义图标'),
          const SizedBox(height: 12),
          _buildCustomImageOption(colorScheme),
          const SizedBox(height: 32),

          // 保存按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveIcon,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '保存设置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorScheme colorScheme) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withOpacity(0.2),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _buildSelectedIconDisplay(48),
          ),
          const SizedBox(height: 12),
          Text(
            _selectedIcon == 'custom'
                ? '自定义图标'
                : _presetIcons
                    .firstWhere((e) => e.name == _selectedIcon,
                        orElse: () => _presetIcons.first)
                    .label,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedIconDisplay(double size) {
    if (_selectedIcon == 'custom' && _customIconPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.file(
          File(_customIconPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image,
            size: size,
            color: Colors.grey,
          ),
        ),
      );
    }

    final preset = _presetIcons.firstWhere(
      (e) => e.name == _selectedIcon,
      orElse: () => _presetIcons.first,
    );

    return Icon(preset.icon, size: size, color: preset.color);
  }

  Widget _buildInfoBanner(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: Colors.blue.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '自定义图标仅在部分 Android 设备上生效。Android 自适应图标需要原生代码支持，如需完整适配请查看开发文档。',
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPresetGrid(ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: _presetIcons.length,
      itemBuilder: (context, index) {
        final preset = _presetIcons[index];
        final isSelected = _selectedIcon == preset.name;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedIcon = preset.name;
              _customIconPath = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? preset.color.withOpacity(0.15)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? preset.color : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: preset.color.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  preset.icon,
                  size: 36,
                  color: preset.color,
                ),
                const SizedBox(height: 6),
                Text(
                  preset.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? preset.color : null,
                  ),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: preset.color,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomImageOption(ColorScheme colorScheme) {
    final isSelected = _selectedIcon == 'custom';

    return GestureDetector(
      onTap: _pickCustomImage,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B6B).withOpacity(0.08)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B6B) : colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 图标预览
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _customIconPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_customIconPath!),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image,
                          size: 28,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: Color(0xFFFF6B6B),
                    ),
            ),
            const SizedBox(width: 16),
            // 文字说明
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customIconPath != null ? '重新选择图片' : '从相册选择',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择 512x512 以内的正方形图片效果最佳',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预设图标数据
class _PresetIcon {
  final String name;
  final String label;
  final IconData icon;
  final Color color;

  const _PresetIcon({
    required this.name,
    required this.label,
    required this.icon,
    required this.color,
  });
}
