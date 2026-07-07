// 【对标来源：SillyTavern-1.18.0 — instruct-mode.js Instruct 模板设置界面】
// 1:1 转译自 SillyTavern Instruct Mode 全部序列字段和预设管理
// 参考文件：public/scripts/instruct-mode.js、public/scripts/power-user.js

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/safe_file_picker.dart';

/// Instruct 模板设置数据模型
class InstructSettings {
  bool enabled;
  String preset;
  String inputSequence;
  String inputSuffix;
  String outputSequence;
  String outputSuffix;
  String systemSequence;
  String systemSuffix;
  String lastSystemSequence;
  String firstInputSequence;
  String firstOutputSequence;
  String lastInputSequence;
  String lastOutputSequence;
  String storyStringPrefix;
  String storyStringSuffix;
  String stopSequence;
  bool wrap;
  bool macro;
  String namesBehavior;
  String activationRegex;
  bool bindToContext;
  String userAlignmentMessage;
  bool systemSameAsUser;
  bool sequencesAsStopStrings;
  bool skipExamples;

  InstructSettings({
    this.enabled = false,
    this.preset = 'Alpaca',
    this.inputSequence = '### Instruction:',
    this.inputSuffix = '',
    this.outputSequence = '### Response:',
    this.outputSuffix = '',
    this.systemSequence = '',
    this.systemSuffix = '',
    this.lastSystemSequence = '',
    this.firstInputSequence = '',
    this.firstOutputSequence = '',
    this.lastInputSequence = '',
    this.lastOutputSequence = '',
    this.storyStringPrefix = '',
    this.storyStringSuffix = '',
    this.stopSequence = '',
    this.wrap = true,
    this.macro = true,
    this.namesBehavior = 'force',
    this.activationRegex = '',
    this.bindToContext = false,
    this.userAlignmentMessage = '',
    this.systemSameAsUser = false,
    this.sequencesAsStopStrings = true,
    this.skipExamples = false,
  });

  factory InstructSettings.fromJson(Map<String, dynamic> json) {
    return InstructSettings(
      enabled: json['enabled'] ?? false,
      preset: json['preset'] ?? 'Alpaca',
      inputSequence: json['inputSequence'] ?? '### Instruction:',
      inputSuffix: json['inputSuffix'] ?? '',
      outputSequence: json['outputSequence'] ?? '### Response:',
      outputSuffix: json['outputSuffix'] ?? '',
      systemSequence: json['systemSequence'] ?? '',
      systemSuffix: json['systemSuffix'] ?? '',
      lastSystemSequence: json['lastSystemSequence'] ?? '',
      firstInputSequence: json['firstInputSequence'] ?? '',
      firstOutputSequence: json['firstOutputSequence'] ?? '',
      lastInputSequence: json['lastInputSequence'] ?? '',
      lastOutputSequence: json['lastOutputSequence'] ?? '',
      storyStringPrefix: json['storyStringPrefix'] ?? '',
      storyStringSuffix: json['storyStringSuffix'] ?? '',
      stopSequence: json['stopSequence'] ?? '',
      wrap: json['wrap'] ?? true,
      macro: json['macro'] ?? true,
      namesBehavior: json['namesBehavior'] ?? 'force',
      activationRegex: json['activationRegex'] ?? '',
      bindToContext: json['bindToContext'] ?? false,
      userAlignmentMessage: json['userAlignmentMessage'] ?? '',
      systemSameAsUser: json['systemSameAsUser'] ?? false,
      sequencesAsStopStrings: json['sequencesAsStopStrings'] ?? true,
      skipExamples: json['skipExamples'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'preset': preset,
      'inputSequence': inputSequence,
      'inputSuffix': inputSuffix,
      'outputSequence': outputSequence,
      'outputSuffix': outputSuffix,
      'systemSequence': systemSequence,
      'systemSuffix': systemSuffix,
      'lastSystemSequence': lastSystemSequence,
      'firstInputSequence': firstInputSequence,
      'firstOutputSequence': firstOutputSequence,
      'lastInputSequence': lastInputSequence,
      'lastOutputSequence': lastOutputSequence,
      'storyStringPrefix': storyStringPrefix,
      'storyStringSuffix': storyStringSuffix,
      'stopSequence': stopSequence,
      'wrap': wrap,
      'macro': macro,
      'namesBehavior': namesBehavior,
      'activationRegex': activationRegex,
      'bindToContext': bindToContext,
      'userAlignmentMessage': userAlignmentMessage,
      'systemSameAsUser': systemSameAsUser,
      'sequencesAsStopStrings': sequencesAsStopStrings,
      'skipExamples': skipExamples,
    };
  }
}

/// 内置预设
final List<Map<String, dynamic>> _builtInPresets = [
  {
    'name': 'Alpaca',
    'inputSequence': '### Instruction:',
    'outputSequence': '### Response:',
  },
  {
    'name': 'ChatML',
    'inputSequence': '<|im_start|>user',
    'outputSequence': '<|im_start|>assistant',
    'systemSequence': '<|im_start|>system',
  },
  {
    'name': 'Vicuna',
    'inputSequence': 'USER:',
    'outputSequence': 'ASSISTANT:',
  },
];

/// Instruct 模板设置界面
class InstructModeScreen extends StatefulWidget {
  const InstructModeScreen({super.key});

  @override
  State<InstructModeScreen> createState() => _InstructModeScreenState();
}

class _InstructModeScreenState extends State<InstructModeScreen> {
  InstructSettings _settings = InstructSettings();
  List<Map<String, dynamic>> _presets = [];
  String _selectedPresetName = 'Alpaca';

  static const _settingsKey = 'instruct_mode_settings';
  static const _presetsKey = 'instruct_mode_presets';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// 加载所有数据
  Future<void> _loadAll() async {
    final sp = await SharedPreferences.getInstance();

    // 加载预设列表
    final presetsJson = sp.getString(_presetsKey);
    if (presetsJson != null) {
      final list = jsonDecode(presetsJson) as List;
      _presets = list.cast<Map<String, dynamic>>();
    }
    if (_presets.isEmpty) {
      _presets =
          _builtInPresets.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    // 加载当前设置
    final settingsJson = sp.getString(_settingsKey);
    if (settingsJson != null) {
      _settings = InstructSettings.fromJson(jsonDecode(settingsJson));
      _selectedPresetName = _settings.preset;
    } else {
      _applyPreset(_presets.first);
    }

    setState(() {});
  }

  /// 持久化当前设置
  Future<void> _persistSettings() async {
    final sp = await SharedPreferences.getInstance();
    _settings.preset = _selectedPresetName;
    await sp.setString(_settingsKey, jsonEncode(_settings.toJson()));
  }

  /// 持久化预设列表
  Future<void> _persistPresets() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_presetsKey, jsonEncode(_presets));
  }

  /// 应用预设到当前设置
  void _applyPreset(Map<String, dynamic> preset) {
    _selectedPresetName = preset['name'] ?? 'Alpaca';
    _settings = InstructSettings.fromJson(preset);
    _settings.preset = _selectedPresetName;
  }

  /// 从当前设置保存到当前预设
  void _saveToCurrentPreset() {
    final idx = _presets.indexWhere((p) => p['name'] == _selectedPresetName);
    if (idx >= 0) {
      _presets[idx] = _settings.toJson();
      _presets[idx].remove('enabled');
      _presets[idx]['name'] = _selectedPresetName;
    }
    _persistPresets();
    _persistSettings();
  }

  /// 保存当前设置到预设（覆盖）
  void _savePreset() {
    _saveToCurrentPreset();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预设已保存')),
    );
  }

  /// 另存为新预设
  Future<void> _saveAsNewPreset() async {
    final controller = TextEditingController(text: _selectedPresetName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为新预设'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: '预设名称', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final presetData = _settings.toJson();
    presetData.remove('enabled');
    presetData['name'] = name;
    _presets.add(presetData);
    _selectedPresetName = name;
    _settings.preset = name;
    _persistPresets();
    _persistSettings();
    setState(() {});
  }

  /// 重命名预设
  Future<void> _renamePreset() async {
    final controller = TextEditingController(text: _selectedPresetName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名预设'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: '新名称', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确认')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _selectedPresetName) return;
    final idx = _presets.indexWhere((p) => p['name'] == _selectedPresetName);
    if (idx >= 0) {
      _presets[idx]['name'] = name;
      _selectedPresetName = name;
      _settings.preset = name;
      _persistPresets();
      _persistSettings();
      setState(() {});
    }
  }

  /// 删除当前预设
  Future<void> _deletePreset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定删除预设 "$_selectedPresetName" 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    _presets.removeWhere((p) => p['name'] == _selectedPresetName);
    if (_presets.isEmpty) {
      _presets =
          _builtInPresets.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    _selectedPresetName = _presets.first['name'];
    _applyPreset(_presets.first);
    _persistPresets();
    _persistSettings();
    setState(() {});
  }

  /// 恢复内置预设
  void _restoreDefaults() {
    _presets =
        _builtInPresets.map((e) => Map<String, dynamic>.from(e)).toList();
    _selectedPresetName = 'Alpaca';
    _applyPreset(_presets.first);
    _persistPresets();
    _persistSettings();
    setState(() {});
  }

  /// 导出预设到 JSON 文件
  Future<void> _exportPreset() async {
    final json = jsonEncode(_settings.toJson());
    final result = await SafeFilePicker.saveFile(
      dialogTitle: '导出 Instruct 预设',
      fileName: '${_selectedPresetName}_instruct.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      File(result).writeAsStringSync(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('预设已导出')),
        );
      }
    }
  }

  /// 从 JSON 文件导入预设
  Future<void> _importPreset() async {
    final result = await SafeFilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    try {
      final file = File(result.files.first.path!);
      final jsonData =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final name = jsonData['name'] as String? ?? '导入的预设';
      jsonData['name'] = name;
      _presets.add(jsonData);
      _selectedPresetName = name;
      _settings = InstructSettings.fromJson(jsonData);
      _settings.preset = name;
      _persistPresets();
      _persistSettings();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败')),
        );
      }
    }
  }

  /// 更新设置字段并自动持久化
  void _updateField(void Function() updater) {
    setState(updater);
    _persistSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Instruct 模板'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Section 1: 开关 ──
          _buildCard(
            colorScheme,
            SwitchListTile(
              secondary: Icon(Icons.power_settings_new,
                  color: _settings.enabled
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.4)),
              title: Text('启用 Instruct 模式', style: textTheme.titleMedium),
              subtitle: Text(
                _settings.enabled ? '已启用' : '已禁用',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
              ),
              value: _settings.enabled,
              onChanged: (v) => _updateField(() => _settings.enabled = v),
              activeColor: colorScheme.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),

          // ── 以下所有内容在禁用时灰显 ──
          Opacity(
            opacity: _settings.enabled ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !_settings.enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 2: 预设管理 ──
                  _buildCard(
                    colorScheme,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('预设管理',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _presets
                                  .any((p) => p['name'] == _selectedPresetName)
                              ? _selectedPresetName
                              : null,
                          decoration: _inputDecoration('选择预设', colorScheme),
                          items: _presets
                              .map((p) => DropdownMenuItem(
                                    value: p['name'] as String,
                                    child: Text(p['name'] as String),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _selectedPresetName = v;
                              _applyPreset(
                                  _presets.firstWhere((p) => p['name'] == v));
                            });
                            _persistSettings();
                          },
                          isExpanded: true,
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _iconBtn(
                                  Icons.save, '保存', _savePreset, colorScheme),
                              _iconBtn(Icons.edit, '重命名', _renamePreset,
                                  colorScheme),
                              _iconBtn(Icons.save_as, '另存为', _saveAsNewPreset,
                                  colorScheme),
                              _iconBtn(Icons.file_upload, '导入', _importPreset,
                                  colorScheme),
                              _iconBtn(Icons.file_download, '导出', _exportPreset,
                                  colorScheme),
                              _iconBtn(Icons.delete_outline, '删除',
                                  _deletePreset, colorScheme,
                                  isError: true),
                              _iconBtn(Icons.restore, '恢复默认', _restoreDefaults,
                                  colorScheme),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Section 3: 选项开关 ──
                  _buildCard(
                    colorScheme,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('设置选项',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        _buildCheckbox(
                            '用换行符包裹序列',
                            _settings.wrap,
                            (v) => _updateField(() => _settings.wrap = v),
                            colorScheme),
                        _buildCheckbox(
                            '替换序列中的宏',
                            _settings.macro,
                            (v) => _updateField(() => _settings.macro = v),
                            colorScheme),
                        _buildCheckbox(
                            '序列作为停止字符串',
                            _settings.sequencesAsStopStrings,
                            (v) => _updateField(
                                () => _settings.sequencesAsStopStrings = v),
                            colorScheme),
                        _buildCheckbox(
                            '跳过示例对话格式化',
                            _settings.skipExamples,
                            (v) =>
                                _updateField(() => _settings.skipExamples = v),
                            colorScheme),
                        _buildCheckbox(
                            '系统序列与用户相同',
                            _settings.systemSameAsUser,
                            (v) => _updateField(
                                () => _settings.systemSameAsUser = v),
                            colorScheme),
                        _buildCheckbox(
                            '绑定到上下文',
                            _settings.bindToContext,
                            (v) =>
                                _updateField(() => _settings.bindToContext = v),
                            colorScheme),
                        const Divider(height: 24),
                        // Names 行为下拉
                        DropdownButtonFormField<String>(
                          value: _settings.namesBehavior,
                          decoration: _inputDecoration('名称行为', colorScheme),
                          items: const [
                            DropdownMenuItem(value: 'none', child: Text('从不')),
                            DropdownMenuItem(
                                value: 'force', child: Text('群组和角色')),
                            DropdownMenuItem(
                                value: 'always', child: Text('始终')),
                          ],
                          onChanged: (v) => _updateField(
                              () => _settings.namesBehavior = v ?? 'force'),
                          isExpanded: true,
                        ),
                        const SizedBox(height: 12),
                        // 激活正则
                        TextField(
                          controller: TextEditingController(
                              text: _settings.activationRegex),
                          onChanged: (v) =>
                              _updateField(() => _settings.activationRegex = v),
                          decoration: _inputDecoration('激活正则表达式', colorScheme),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Section 4: 序列配置 ──
                  // A. Story String
                  _buildExpansionTile(
                    '故事字符串序列',
                    colorScheme,
                    textTheme,
                    initiallyExpanded: true,
                    children: [
                      _buildSequenceField(
                          '故事字符串前缀',
                          _settings.storyStringPrefix,
                          (v) => _updateField(
                              () => _settings.storyStringPrefix = v),
                          colorScheme),
                      _buildSequenceField(
                          '故事字符串后缀',
                          _settings.storyStringSuffix,
                          (v) => _updateField(
                              () => _settings.storyStringSuffix = v),
                          colorScheme),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // B. User Message
                  _buildExpansionTile(
                    '用户消息序列',
                    colorScheme,
                    textTheme,
                    initiallyExpanded: true,
                    children: [
                      _buildSequenceField(
                          '用户消息前缀 (input_sequence)',
                          _settings.inputSequence,
                          (v) =>
                              _updateField(() => _settings.inputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '用户消息后缀 (input_suffix)',
                          _settings.inputSuffix,
                          (v) => _updateField(() => _settings.inputSuffix = v),
                          colorScheme),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // C. Assistant Message
                  _buildExpansionTile(
                    '助手消息序列',
                    colorScheme,
                    textTheme,
                    initiallyExpanded: true,
                    children: [
                      _buildSequenceField(
                          '助手消息前缀 (output_sequence)',
                          _settings.outputSequence,
                          (v) =>
                              _updateField(() => _settings.outputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '助手消息后缀 (output_suffix)',
                          _settings.outputSuffix,
                          (v) => _updateField(() => _settings.outputSuffix = v),
                          colorScheme),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // D. System Message
                  _buildExpansionTile(
                    '系统消息序列',
                    colorScheme,
                    textTheme,
                    initiallyExpanded: false,
                    children: [
                      _buildSequenceField(
                        '系统消息前缀 (system_sequence)',
                        _settings.systemSequence,
                        _settings.systemSameAsUser
                            ? null
                            : (v) => _updateField(
                                () => _settings.systemSequence = v),
                        colorScheme,
                        disabled: _settings.systemSameAsUser,
                      ),
                      _buildSequenceField(
                        '系统消息后缀 (system_suffix)',
                        _settings.systemSuffix,
                        _settings.systemSameAsUser
                            ? null
                            : (v) =>
                                _updateField(() => _settings.systemSuffix = v),
                        colorScheme,
                        disabled: _settings.systemSameAsUser,
                      ),
                      if (_settings.systemSameAsUser)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '已启用"系统序列与用户相同"，系统消息序列将使用用户消息序列',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary.withOpacity(0.8)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // E. Misc. Sequences
                  _buildExpansionTile(
                    '其他序列',
                    colorScheme,
                    textTheme,
                    initiallyExpanded: false,
                    children: [
                      _buildSequenceField(
                          '首个助手前缀 (first_output)',
                          _settings.firstOutputSequence,
                          (v) => _updateField(
                              () => _settings.firstOutputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '末尾助手前缀 (last_output)',
                          _settings.lastOutputSequence,
                          (v) => _updateField(
                              () => _settings.lastOutputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '首个用户前缀 (first_input)',
                          _settings.firstInputSequence,
                          (v) => _updateField(
                              () => _settings.firstInputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '末尾用户前缀 (last_input)',
                          _settings.lastInputSequence,
                          (v) => _updateField(
                              () => _settings.lastInputSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '系统指令前缀 (last_system)',
                          _settings.lastSystemSequence,
                          (v) => _updateField(
                              () => _settings.lastSystemSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '停止序列 (stop_sequence)',
                          _settings.stopSequence,
                          (v) => _updateField(() => _settings.stopSequence = v),
                          colorScheme),
                      _buildSequenceField(
                          '用户对齐消息 (user_alignment)',
                          _settings.userAlignmentMessage,
                          (v) => _updateField(
                              () => _settings.userAlignmentMessage = v),
                          colorScheme),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 构建卡片容器 ──
  Widget _buildCard(ColorScheme colorScheme, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: child,
    );
  }

  // ── 输入框装饰 ──
  InputDecoration _inputDecoration(String label, ColorScheme colorScheme) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
    );
  }

  // ── 复选框 ──
  Widget _buildCheckbox(String title, bool value, ValueChanged<bool> onChanged,
      ColorScheme colorScheme) {
    return CheckboxListTile(
      title: Text(title),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: colorScheme.primary,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  // ── 序列输入框 ──
  Widget _buildSequenceField(
    String label,
    String value,
    ValueChanged<String>? onChanged,
    ColorScheme colorScheme, {
    bool disabled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: TextEditingController(text: value),
        onChanged: onChanged,
        enabled: !disabled,
        maxLines: null,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: disabled
              ? colorScheme.surfaceContainerHighest.withOpacity(0.2)
              : colorScheme.surfaceContainerHighest.withOpacity(0.5),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  // ── 操作按钮 ──
  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap,
      ColorScheme colorScheme,
      {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isError
              ? colorScheme.error.withOpacity(0.1)
              : colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon,
                  size: 20,
                  color: isError ? colorScheme.error : colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  // ── 可折叠分组 ──
  Widget _buildExpansionTile(
    String title,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool initiallyExpanded,
    required List<Widget> children,
  }) {
    return _buildCard(
      colorScheme,
      ExpansionTile(
        title: Text(title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        initiallyExpanded: initiallyExpanded,
        collapsedIconColor: colorScheme.onSurface.withOpacity(0.6),
        iconColor: colorScheme.primary,
        children: children,
      ),
    );
  }
}
