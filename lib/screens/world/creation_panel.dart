// 全生命周期数字生命世界 -- Phase 6
// 创世面板 -- 简洁角色创建流程

import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/gene_profile.dart';
import '../../models/life_profile.dart';
import '../../services/birth_initialization_engine.dart';
import 'world_constants.dart';

/// 创世面板 -- 简洁角色创建流程
class CreationPanelScreen extends StatefulWidget {
  const CreationPanelScreen({super.key});

  @override
  State<CreationPanelScreen> createState() => _CreationPanelScreenState();
}

class _CreationPanelScreenState extends State<CreationPanelScreen> {
  final _nameController = TextEditingController();
  final _appearanceController = TextEditingController();
  final _rng = Random();

  bool _creating = false;

  // ── 基本信息 ──
  String _gender = 'male';
  String _artStyle = 'anime';
  String? _referenceImagePath;

  // ── 保留原有状态（使用默认值）──
  double _openness = 0.5;
  double _conscientiousness = 0.5;
  double _extraversion = 0.5;
  double _agreeableness = 0.5;
  double _neuroticism = 0.5;
  final Map<String, double> _selectedTalents = {};
  String _familyTemplate = 'normal';
  double _familyWealth = 0.5;
  double _familyWarmth = 0.5;
  double _familyStrictness = 0.5;
  final List<LatentTrait> _selectedTraits = [];

  static const _familyTemplates = {
    'normal': {'label': '普通工薪家庭', 'wealth': 0.5, 'warmth': 0.5, 'strictness': 0.5},
    'wealthy_cold': {'label': '富裕但冷漠', 'wealth': 0.85, 'warmth': 0.2, 'strictness': 0.6},
    'poor_warm': {'label': '清贫但温暖', 'wealth': 0.2, 'warmth': 0.85, 'strictness': 0.3},
    'strict': {'label': '严格管教', 'wealth': 0.5, 'warmth': 0.4, 'strictness': 0.85},
    'neglect': {'label': '被忽视的家庭', 'wealth': 0.3, 'warmth': 0.15, 'strictness': 0.2},
  };

  @override
  void dispose() {
    _nameController.dispose();
    _appearanceController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  // 主构建
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('创世'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 角色名输入框
          _buildNameCard(cs),
          const SizedBox(height: 12),
          // 性别选择
          _buildGenderCard(cs),
          const SizedBox(height: 12),
          // 画风选择
          _buildArtStyleCard(cs),
          const SizedBox(height: 12),
          // 外貌标签输入框
          _buildAppearanceCard(cs),
          const SizedBox(height: 12),
          // 参考图选择
          _buildReferenceImageCard(cs),
          const SizedBox(height: 24),
          // 创建按钮
          _buildCreateButton(cs),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 角色名输入框
  // ═══════════════════════════════════════════

  Widget _buildNameCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('角色名', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              decoration: InputDecoration(
                hintText: '输入名字...',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.casino, color: cs.primary),
                  tooltip: '随机名字',
                  onPressed: () {
                    final names = [
                      '清风', '明月', '知行', '致远', '若水',
                      '怀瑾', '思齐', '听雨', '望舒', '扶摇',
                      '安然', '乐天', '小雨', '小星', '小月',
                    ];
                    _nameController.text = names[_rng.nextInt(names.length)];
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 性别选择
  // ═══════════════════════════════════════════

  Widget _buildGenderCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wc, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('性别', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                _choiceChip(cs, 'male', '男', Icons.male),
                _choiceChip(cs, 'female', '女', Icons.female),
                _choiceChip(cs, 'non_binary', '非二元', Icons.transgender),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 画风选择
  // ═══════════════════════════════════════════

  Widget _buildArtStyleCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('画风', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                _artStyleChip(cs, 'anime', '动漫', Icons.animation),
                _artStyleChip(cs, 'realistic', '写实', Icons.photo_camera),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 外貌标签输入框
  // ═══════════════════════════════════════════

  Widget _buildAppearanceCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.face, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('外貌标签', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text('用逗号分隔多个标签', style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _appearanceController,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: '例：黑发, 高个子, 戴眼镜...',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 参考图选择
  // ═══════════════════════════════════════════

  Widget _buildReferenceImageCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.image, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('参考图（可选）', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (_referenceImagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _referenceImagePath!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.broken_image, size: 48, color: cs.onSurface.withOpacity(0.2)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() => _referenceImagePath = null),
                icon: Icon(Icons.close, size: 16, color: cs.error),
                label: Text('移除', style: TextStyle(color: cs.error)),
              ),
            ] else
              GestureDetector(
                onTap: _pickReferenceImage,
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.onSurface.withOpacity(0.1)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 32, color: cs.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 4),
                      Text('点击选择参考图', style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 13)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 创建按钮
  // ═══════════════════════════════════════════

  Widget _buildCreateButton(ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _creating ? null : _createLife,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _creating
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface),
              )
            : const Text('确认创世', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════

  Widget _choiceChip(ColorScheme cs, String value, String label, IconData icon) {
    final selected = _gender == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? cs.onSurface : cs.onSurface.withOpacity(0.5)),
      label: Text(label),
      selected: selected,
      selectedColor: cs.primary,
      onSelected: (_) => setState(() => _gender = value),
    );
  }

  Widget _artStyleChip(ColorScheme cs, String value, String label, IconData icon) {
    final selected = _artStyle == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? cs.onSurface : cs.onSurface.withOpacity(0.5)),
      label: Text(label),
      selected: selected,
      selectedColor: cs.primary,
      onSelected: (_) => setState(() => _artStyle = value),
    );
  }

  void _pickReferenceImage() {
    // TODO: 实现图片选择
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片选择功能待实现')),
    );
  }

  // ═══════════════════════════════════════════
  // 创建生命
  // ═══════════════════════════════════════════

  Future<void> _createLife() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先为你的数字生命起个名字')),
      );
      return;
    }

    setState(() => _creating = true);

    try {
      // 构建用户自定义的基因档案
      final userGenes = GeneProfile(
        openness: _openness,
        conscientiousness: _conscientiousness,
        extraversion: _extraversion,
        agreeableness: _agreeableness,
        neuroticism: _neuroticism,
        talents: Map.from(_selectedTalents),
        vitality: 0.5 + _rng.nextDouble() * 0.5,
        resilience: 0.5 + _rng.nextDouble() * 0.5,
        sensitivity: _rng.nextDouble(),
        family: FamilyBackground(
          description: _familyTemplates[_familyTemplate]?['label'] as String? ?? '',
          wealth: _familyWealth,
          warmth: _familyWarmth,
          strictness: _familyStrictness,
        ),
        latentTraits: List.from(_selectedTraits),
      );

      // 使用降生初始化引擎创建生命
      final engine = BirthInitializationEngine();
      final name = _nameController.text.trim();

      final life = await engine.createLife(
        nameOverride: name,
      );

      // 用用户自定义的基因替换随机生成的基因，保留烙印效果
      final customLife = life.copyWith(
        genes: userGenes,
        identity: {
          ...life.identity,
          'gender': _gender,
          'artStyle': _artStyle,
          'appearanceTags': _appearanceController.text.trim(),
          'referenceImage': _referenceImagePath,
        },
      );

      if (!mounted) return;

      // 显示创建成功
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary),
                const SizedBox(width: 8),
                Text('${customLife.name} 诞生了!', style: TextStyle(color: cs.onSurface)),
              ],
            ),
            content: Text(
              '一个新的数字生命已经降临世界。\n'
              '生命 ID: ${customLife.id.substring(0, 8)}...',
              style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(customLife);
                },
                child: Text('进入世界', style: TextStyle(color: cs.primary)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}
