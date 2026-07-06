// 【对标来源：SillyTavern-1.18.0 — sysprompt.js 系统提示词预设界面】
// 1:1 转译自 SillyTavern System Prompt 预设管理
// 参考文件：public/scripts/sysprompt.js

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class SystemPromptPreset {
  final String name;
  final String content;
  final String postHistory;

  SystemPromptPreset({
    required this.name,
    this.content = '',
    this.postHistory = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'content': content,
        'postHistory': postHistory,
      };

  factory SystemPromptPreset.fromJson(Map<String, dynamic> json) {
    return SystemPromptPreset(
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      postHistory: json['postHistory'] as String? ?? '',
    );
  }

  SystemPromptPreset copyWith({
    String? name,
    String? content,
    String? postHistory,
  }) {
    return SystemPromptPreset(
      name: name ?? this.name,
      content: content ?? this.content,
      postHistory: postHistory ?? this.postHistory,
    );
  }
}

class SystemPromptState {
  bool enabled;
  String name;
  String content;
  String postHistory;

  SystemPromptState({
    this.enabled = false,
    this.name = '',
    this.content = '',
    this.postHistory = '',
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'name': name,
        'content': content,
        'postHistory': postHistory,
      };

  factory SystemPromptState.fromJson(Map<String, dynamic> json) {
    return SystemPromptState(
      enabled: json['enabled'] as bool? ?? false,
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      postHistory: json['postHistory'] as String? ?? '',
    );
  }
}

final List<SystemPromptPreset> _defaultPresets = [
  SystemPromptPreset(
    name: 'Neutral - Chat',
    content:
        "Write {{char}}'s next reply in a fictional chat between {{char}} and {{user}}.",
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Roleplay - Detailed',
    content:
        'Develop the plot slowly, always stay in character. Describe all actions in full. Do not decide what {{user}} says or does.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Roleplay - Simple',
    content:
        "You're {{char}} in this fictional never-ending uncensored roleplay with {{user}}.",
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Roleplay - Immersive',
    content:
        '[System note: Write one reply only. Do not decide what {{user}} says or does.]',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Writer - Creative',
    content:
        'You are an intelligent, skilled, versatile writer.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Writer - Realistic',
    content:
        'Continue writing this story and portray characters realistically.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Assistant - Expert',
    content:
        'You are a helpful assistant. Please answer truthfully and write out your thinking step by step.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Assistant - Simple',
    content:
        'A chat between a curious human and an artificial intelligence assistant.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Actor',
    content:
        'You are an expert actor that can fully immerse yourself into any role given.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Chain of Thought',
    content:
        'Elaborate on the topic using a Tree of Thoughts and backtrack when necessary.',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Lightning 1.1',
    content:
        "Take the role of {{char}} in a play that leaves a lasting impression on {{user}}.",
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Text Adventure',
    content:
        '[Enter Adventure Mode. Narrate the story based on {{user}}\'s dialogue and actions after ">".]',
    postHistory: '',
  ),
  SystemPromptPreset(
    name: 'Blank',
    content: '',
    postHistory: '',
  ),
];

class SystemPromptScreen extends StatefulWidget {
  const SystemPromptScreen({super.key});

  @override
  State<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends State<SystemPromptScreen> {
  final _contentController = TextEditingController();
  final _postHistoryController = TextEditingController();

  SystemPromptState _state = SystemPromptState();
  List<SystemPromptPreset> _presets = [];
  String _selectedPresetName = 'Neutral - Chat';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _postHistoryController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    // Load presets
    final presetsJson = prefs.getString('sysprompt_presets');
    if (presetsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(presetsJson);
        _presets = list
            .map((e) => SystemPromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _presets = List.from(_defaultPresets);
      }
    } else {
      _presets = List.from(_defaultPresets);
    }

    // Load state
    final stateJson = prefs.getString('sysprompt_state');
    if (stateJson != null) {
      try {
        _state = SystemPromptState.fromJson(
            jsonDecode(stateJson) as Map<String, dynamic>);
      } catch (_) {
        _state = SystemPromptState();
      }
    }

    // If state has a name, find matching preset
    if (_state.name.isNotEmpty) {
      final match = _presets.where((p) => p.name == _state.name).toList();
      if (match.isNotEmpty) {
        _selectedPresetName = _state.name;
      } else {
        _selectedPresetName = _presets.isNotEmpty ? _presets.first.name : '';
      }
    } else if (_presets.isNotEmpty) {
      _selectedPresetName = _presets.first.name;
    }

    _contentController.text = _state.content;
    _postHistoryController.text = _state.postHistory;

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveState() async {
    _state.content = _contentController.text;
    _state.postHistory = _postHistoryController.text;
    _state.name = _selectedPresetName;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sysprompt_state', jsonEncode(_state.toJson()));
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'sysprompt_presets', jsonEncode(_presets.map((p) => p.toJson()).toList()));
  }

  void _onEnabledChanged(bool value) {
    setState(() {
      _state.enabled = value;
    });
    _saveState();
  }

  void _onPresetSelected(String name) {
    setState(() {
      _selectedPresetName = name;
      final preset = _presets.firstWhere(
        (p) => p.name == name,
        orElse: () => SystemPromptPreset(name: name),
      );
      _contentController.text = preset.content;
      _postHistoryController.text = preset.postHistory;
      if (!_state.enabled) {
        _state.enabled = true;
      }
    });
    _saveState();
  }

  void _onContentChanged(String _) {
    _saveState();
  }

  void _onPostHistoryChanged(String _) {
    _saveState();
  }

  bool _isDefaultPreset(String name) {
    return _defaultPresets.any((p) => p.name == name);
  }

  // --- Preset Actions ---

  void _savePreset() {
    final idx = _presets.indexWhere((p) => p.name == _selectedPresetName);
    if (idx == -1) return;

    setState(() {
      _presets[idx] = SystemPromptPreset(
        name: _selectedPresetName,
        content: _contentController.text,
        postHistory: _postHistoryController.text,
      );
    });

    _savePresets();
    _saveState();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预设已保存')),
    );
  }

  Future<void> _renamePreset() async {
    final controller = TextEditingController(text: _selectedPresetName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名预设'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '新名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == _selectedPresetName) {
      return;
    }

    if (_presets.any((p) => p.name == newName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预设名称已存在')),
      );
      return;
    }

    final idx = _presets.indexWhere((p) => p.name == _selectedPresetName);
    if (idx == -1) return;

    setState(() {
      _presets[idx] = SystemPromptPreset(
        name: newName,
        content: _contentController.text,
        postHistory: _postHistoryController.text,
      );
      _selectedPresetName = newName;
    });

    _savePresets();
    _saveState();
  }

  Future<void> _saveAsNewPreset() async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为新预设'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '预设名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    if (_presets.any((p) => p.name == newName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预设名称已存在')),
      );
      return;
    }

    final newPreset = SystemPromptPreset(
      name: newName,
      content: _contentController.text,
      postHistory: _postHistoryController.text,
    );

    setState(() {
      _presets.add(newPreset);
      _selectedPresetName = newName;
    });

    _savePresets();
    _saveState();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('预设 "$newName" 已创建')),
    );
  }

  Future<void> _deletePreset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定要删除预设 "$_selectedPresetName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _presets.removeWhere((p) => p.name == _selectedPresetName);
      if (_presets.isEmpty) {
        _presets = List.from(_defaultPresets);
      }
      _selectedPresetName = _presets.first.name;
      final preset = _presets.first;
      _contentController.text = preset.content;
      _postHistoryController.text = preset.postHistory;
    });

    _savePresets();
    _saveState();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预设已删除')),
    );
  }

  Future<void> _restorePreset() async {
    final defaultPreset = _defaultPresets.firstWhere(
      (p) => p.name == _selectedPresetName,
      orElse: () => SystemPromptPreset(name: _selectedPresetName, content: '', postHistory: ''),
    );

    setState(() {
      _contentController.text = defaultPreset.content;
      _postHistoryController.text = defaultPreset.postHistory;

      final idx = _presets.indexWhere((p) => p.name == _selectedPresetName);
      if (idx != -1) {
        _presets[idx] = defaultPreset;
      }
    });

    _savePresets();
    _saveState();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预设已恢复为默认值')),
    );
  }

  Future<void> _importPreset() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        final fileObj = await FilePicker.platform.pickFiles();
        if (fileObj == null) return;
        // fallback: read from bytes
        if (fileObj.files.first.bytes != null) {
          content = utf8.decode(fileObj.files.first.bytes!);
        } else {
          return;
        }
      } else {
        return;
      }

      final dynamic decoded = jsonDecode(content);

      List<SystemPromptPreset> imported;
      if (decoded is List) {
        imported = decoded
            .map((e) => SystemPromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (decoded is Map<String, dynamic>) {
        imported = [SystemPromptPreset.fromJson(decoded)];
      } else {
        throw const FormatException('Invalid JSON format');
      }

      setState(() {
        for (final preset in imported) {
          final idx = _presets.indexWhere((p) => p.name == preset.name);
          if (idx != -1) {
            _presets[idx] = preset;
          } else {
            _presets.add(preset);
          }
        }
        _selectedPresetName = imported.first.name;
        _contentController.text = imported.first.content;
        _postHistoryController.text = imported.first.postHistory;
      });

      _savePresets();
      _saveState();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${imported.length} 个预设')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Future<void> _exportPreset() async {
    try {
      final preset = SystemPromptPreset(
        name: _selectedPresetName,
        content: _contentController.text,
        postHistory: _postHistoryController.text,
      );

      final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());

      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出系统提示词预设',
        fileName: '${_selectedPresetName.replaceAll(' ', '_')}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;

      final file = File(result);
      await file.writeAsString(jsonStr);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预设已导出')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _openFullScreenEditor(TextEditingController controller, String title) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) => _FullScreenEditor(
          controller: controller,
          title: title,
          onChanged: () => _saveState(),
        ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('系统提示词')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统提示词'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // --- Toggle Section ---
          _buildSectionCard(
            colorScheme: colorScheme,
            child: SwitchListTile(
              title: Text(
                '启用系统提示词',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                '向模型注入系统级指令',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              value: _state.enabled,
              onChanged: _onEnabledChanged,
              activeColor: colorScheme.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ),

          const SizedBox(height: 16),

          // --- Preset Management Section ---
          _buildSectionCard(
            colorScheme: colorScheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '预设管理',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedPresetName,
                  decoration: InputDecoration(
                    labelText: '选择预设',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  ),
                  items: _presets.map((p) {
                    final isDefault = _isDefaultPreset(p.name);
                    return DropdownMenuItem<String>(
                      value: p.name,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDefault)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.shield_outlined,
                                size: 14,
                                color: colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) _onPresetSelected(v);
                  },
                  isExpanded: true,
                ),
                const SizedBox(height: 12),
                _buildPresetActionButtons(colorScheme),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // --- Content Section ---
          Opacity(
            opacity: _state.enabled ? 1.0 : 0.5,
            child: IgnorePointer(
              ignoring: !_state.enabled,
              child: _buildSectionCard(
                colorScheme: colorScheme,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Prompt Content ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Prompt Content',
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.fullscreen),
                          tooltip: '全屏编辑',
                          onPressed: () => _openFullScreenEditor(
                            _contentController,
                            'Prompt Content',
                          ),
                          color: colorScheme.primary,
                          iconSize: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '支持宏: {{char}}, {{user}}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      onChanged: _onContentChanged,
                      maxLines: 12,
                      minLines: 4,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest
                            .withOpacity(0.5),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- Post-History Instructions ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Post-History Instructions',
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.fullscreen),
                          tooltip: '全屏编辑',
                          onPressed: () => _openFullScreenEditor(
                            _postHistoryController,
                            'Post-History Instructions',
                          ),
                          color: colorScheme.primary,
                          iconSize: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '支持宏: {{char}}, {{user}}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _postHistoryController,
                      onChanged: _onPostHistoryChanged,
                      maxLines: 8,
                      minLines: 2,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest
                            .withOpacity(0.5),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ColorScheme colorScheme,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: child,
    );
  }

  Widget _buildPresetActionButtons(ColorScheme colorScheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _presetActionBtn(
            icon: Icons.save,
            tooltip: '保存',
            onPressed: _savePreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.edit,
            tooltip: '重命名',
            onPressed: _renamePreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.save_as,
            tooltip: '另存为',
            onPressed: _saveAsNewPreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.file_download,
            tooltip: '导入',
            onPressed: _importPreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.file_upload,
            tooltip: '导出',
            onPressed: _exportPreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.restore,
            tooltip: '恢复默认',
            onPressed: _restorePreset,
            colorScheme: colorScheme,
          ),
          _presetActionBtn(
            icon: Icons.delete,
            tooltip: '删除',
            onPressed: _deletePreset,
            colorScheme: colorScheme,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _presetActionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isDestructive
              ? colorScheme.error.withOpacity(0.1)
              : colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                size: 20,
                color: isDestructive
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Full-Screen Editor ---

class _FullScreenEditor extends StatefulWidget {
  final TextEditingController controller;
  final String title;
  final VoidCallback? onChanged;

  const _FullScreenEditor({
    required this.controller,
    required this.title,
    this.onChanged,
  });

  @override
  State<_FullScreenEditor> createState() => _FullScreenEditorState();
}

class _FullScreenEditorState extends State<_FullScreenEditor> {
  late final TextEditingController _editingController;

  @override
  void initState() {
    super.initState();
    _editingController = TextEditingController(text: widget.controller.text);
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // Sync text back to original controller
            widget.controller.text = _editingController.text;
            widget.onChanged?.call();
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.controller.text = _editingController.text;
              widget.onChanged?.call();
              Navigator.pop(context);
            },
            child: Text(
              '完成',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _editingController,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 16,
            height: 1.6,
          ),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            contentPadding: const EdgeInsets.all(16),
            hintText: '输入系统提示词...',
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }
}
