// 【对标来源：SillyTavern-1.18.0 — PromptManager.js Prompt 管理界面】
// 1:1 转译自 SillyTavern PromptManager 编辑/排序/注入逻辑
// 参考文件：public/scripts/PromptManager.js

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/prompt_entry.dart';

/// Prompt 管理界面（对标 SillyTavern PromptManager 弹窗）
/// 功能：排序、编辑、启用/禁用、导入/导出 Prompt 模板
class PromptManagerScreen extends StatefulWidget {
  const PromptManagerScreen({super.key});

  @override
  State<PromptManagerScreen> createState() => _PromptManagerScreenState();
}

class _PromptManagerScreenState extends State<PromptManagerScreen> {
  // ---------------------------------------------------------------------------
  // SillyTavern 内置默认 Prompt 列表
  // 参考：public/scripts/PromptManager.js defaultPrompts
  // ---------------------------------------------------------------------------
  static final List<PromptEntry> _defaultPrompts = [
    const PromptEntry(
      name: 'Main Prompt',
      role: 'system',
      prompt: "Write {{char}}'s next reply in a fictional chat between "
          "{{char}} and {{user}}. Write 1 reply only in internet RP style, "
          "italicize actions, and avoid writing {{user}}'s actions or dialogue. "
          "Be proactive, creative, and drive the plot and conversation forward.",
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Auxiliary Prompt',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Chat Examples',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Post-History Instructions',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Chat History',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'World Info (after)',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'World Info (before)',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Enhance Definitions',
      role: 'system',
      prompt: 'If you have more knowledge of {{char}}, add it to the system prompt.',
      enabled: false,
      system: true,
    ),
    const PromptEntry(
      name: 'Char Description',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Char Personality',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Scenario',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
    const PromptEntry(
      name: 'Persona Description',
      role: 'system',
      prompt: '',
      enabled: true,
      system: true,
    ),
  ];

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  late List<PromptEntry> _prompts;
  PromptEntry? _editingPrompt;
  int? _editingIndex;
  bool _initialized = false;

  // 注入触发器选项（对标 SillyTavern PromptManager injection trigger checkboxes）
  static const List<String> _triggerOptions = [
    'normal',
    'continue',
    'impersonate',
    'swipe',
    'regenerate',
    'quiet',
  ];

  // 注入位置选项（对标 SillyTavern PromptManager injection position dropdown）
  static const List<String> _positionOptions = [
    '↑Context',
    '↓Context',
    '@Depth',
  ];

  // 角色选项
  static const List<String> _roleOptions = ['system', 'user', 'assistant'];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _prompts = List.of(_defaultPrompts);
    _loadSavedPrompts();
  }

  /// 从本地存储加载已保存的 Prompt 列表
  Future<void> _loadSavedPrompts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/prompt_manager_prompts.json');
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        setState(() {
          _prompts = jsonList.map((e) => PromptEntry.fromJson(e)).toList();
          _initialized = true;
        });
      } else {
        setState(() => _initialized = true);
      }
    } catch (e) {
      debugPrint('PromptManager: 加载失败 $e');
      setState(() => _initialized = true);
    }
  }

  /// 保存 Prompt 列表到本地存储
  Future<void> _savePrompts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/prompt_manager_prompts.json');
      final jsonStr = jsonEncode(_prompts.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('PromptManager: 保存失败 $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(colorScheme),
      body: Column(
        children: [
          _buildHeaderRow(colorScheme),
          Expanded(child: _buildPromptList(colorScheme)),
          _buildFooterRow(colorScheme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      title: const Text('Prompt 管理'),
      backgroundColor: colorScheme.surface,
      elevation: 0,
      foregroundColor: colorScheme.onSurface,
      actions: [
        IconButton(
          icon: const Icon(Icons.file_upload),
          tooltip: '导入',
          onPressed: _importPrompts,
        ),
        IconButton(
          icon: const Icon(Icons.file_download),
          tooltip: '导出',
          onPressed: _exportPrompts,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Header Row — 标题 + Token 统计
  // ---------------------------------------------------------------------------
  Widget _buildHeaderRow(ColorScheme colorScheme) {
    final enabledCount = _prompts.where((p) => p.enabled).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Prompts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$enabledCount/${_prompts.length}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Token: -',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main Prompt List — ReorderableListView
  // ---------------------------------------------------------------------------
  Widget _buildPromptList(ColorScheme colorScheme) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_prompts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_add, size: 48, color: colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(
              '暂无 Prompt 条目',
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _prompts.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        final prompt = _prompts[index];
        return _buildPromptCard(prompt, index, colorScheme);
      },
    );
  }

  /// 单个 Prompt 卡片
  Widget _buildPromptCard(PromptEntry prompt, int index, ColorScheme colorScheme) {
    final isDisabled = !prompt.enabled;
    final textColor = isDisabled
        ? colorScheme.onSurface.withOpacity(0.35)
        : colorScheme.onSurface;
    final secondaryColor = isDisabled
        ? colorScheme.onSurface.withOpacity(0.2)
        : colorScheme.onSurface.withOpacity(0.4);

    return Card(
      key: ValueKey('prompt_${prompt.name}_$index'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: isDisabled
          ? colorScheme.surface.withOpacity(0.5)
          : colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditSheet(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 拖拽手柄
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  color: secondaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),

              // 类型图标
              Icon(
                _getTypeIcon(prompt),
                size: 18,
                color: isDisabled
                    ? colorScheme.onSurface.withOpacity(0.2)
                    : colorScheme.primary,
              ),
              const SizedBox(width: 10),

              // 名称 + 注入位置信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      prompt.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (prompt.injectionPosition == '@Depth')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '@ depth:${prompt.injectionDepth} order:${prompt.injectionOrder}',
                          style: TextStyle(fontSize: 11, color: secondaryColor),
                        ),
                      ),
                  ],
                ),
              ),

              // Trailing: 角色图标 + 操作按钮
              ..._buildTrailingWidgets(prompt, index, colorScheme, textColor, secondaryColor),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建尾部操作区：角色图标、注入深度标签、编辑、开关、Token
  List<Widget> _buildTrailingWidgets(
    PromptEntry prompt,
    int index,
    ColorScheme colorScheme,
    Color textColor,
    Color secondaryColor,
  ) {
    final widgets = <Widget>[];

    // 角色图标（非 system 显示）
    if (prompt.role != 'system') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            prompt.role == 'assistant' ? Icons.smart_toy : Icons.person,
            size: 16,
            color: secondaryColor,
          ),
        ),
      );
    }

    // 注入深度标签
    if (prompt.injectionPosition == '@Depth') {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '@${prompt.injectionDepth}',
            style: TextStyle(fontSize: 11, color: colorScheme.primary),
          ),
        ),
      );
    }

    // Token 计数
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text(
          '-',
          style: TextStyle(fontSize: 12, color: secondaryColor),
        ),
      ),
    );

    // 编辑按钮
    widgets.add(
      IconButton(
        icon: Icon(Icons.edit, size: 18, color: secondaryColor),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: '编辑',
        onPressed: () => _openEditSheet(index),
      ),
    );

    // 启用/禁用开关
    widgets.add(
      SizedBox(
        height: 28,
        child: Switch(
          value: prompt.enabled,
          onChanged: (val) => _toggleEnabled(index, val),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeColor: colorScheme.primary,
        ),
      ),
    );

    return widgets;
  }

  /// 根据 Prompt 类型返回图标
  IconData _getTypeIcon(PromptEntry prompt) {
    if (prompt.name.toLowerCase().contains('marker') ||
        prompt.name.toLowerCase().contains('chat history')) {
      return Icons.push_pin;
    }
    if (prompt.role == 'user') {
      return Icons.star;
    }
    return Icons.square_outlined;
  }

  // ---------------------------------------------------------------------------
  // Footer Row — 新增 / 导入 / 导出
  // ---------------------------------------------------------------------------
  Widget _buildFooterRow(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.onSurface.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          _footerButton(
            icon: Icons.add,
            label: '新增',
            colorScheme: colorScheme,
            onTap: _addNewPrompt,
          ),
          const SizedBox(width: 12),
          _footerButton(
            icon: Icons.file_download,
            label: '导入',
            colorScheme: colorScheme,
            onTap: _importPrompts,
          ),
          const SizedBox(width: 12),
          _footerButton(
            icon: Icons.file_upload,
            label: '导出',
            colorScheme: colorScheme,
            onTap: _exportPrompts,
          ),
          const Spacer(),
          // 重置默认
          TextButton.icon(
            icon: Icon(Icons.restore, size: 16, color: colorScheme.onSurface.withOpacity(0.5)),
            label: Text(
              '重置默认',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withOpacity(0.5)),
            ),
            onPressed: _resetToDefaults,
          ),
        ],
      ),
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// 拖拽排序回调
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _prompts.removeAt(oldIndex);
      _prompts.insert(newIndex, item);
    });
    _savePrompts();
  }

  /// 切换启用/禁用
  void _toggleEnabled(int index, bool value) {
    setState(() {
      final old = _prompts[index];
      _prompts[index] = PromptEntry(
        name: old.name,
        role: old.role,
        injectionTrigger: old.injectionTrigger,
        injectionPosition: old.injectionPosition,
        injectionDepth: old.injectionDepth,
        injectionOrder: old.injectionOrder,
        prompt: old.prompt,
        forbidOverrides: old.forbidOverrides,
        enabled: value,
        system: old.system,
      );
    });
    _savePrompts();
  }

  /// 新增 Prompt
  void _addNewPrompt() {
    _editingIndex = null;
    _editingPrompt = const PromptEntry(name: '');
    _showEditSheet();
  }

  /// 打开编辑底部弹窗
  void _openEditSheet(int index) {
    _editingIndex = index;
    _editingPrompt = _prompts[index];
    _showEditSheet();
  }

  /// 重置为默认 Prompt 列表
  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置确认'),
        content: const Text('将恢复为 SillyTavern 默认 Prompt 列表，当前所有自定义修改将丢失。确认重置？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _prompts = List.of(_defaultPrompts));
              _savePrompts();
            },
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }

  /// 删除 Prompt（仅非系统内置可删除）
  void _deletePrompt(int index) {
    final prompt = _prompts[index];
    if (prompt.system) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('系统内置 Prompt 不可删除')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确认删除 Prompt "${prompt.name}"？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _prompts.removeAt(index));
              _savePrompts();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Import / Export
  // ---------------------------------------------------------------------------

  /// 导入 Prompt 列表（.json 文件）
  Future<void> _importPrompts() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final jsonStr = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonStr);

      final imported = jsonList.map((e) => PromptEntry.fromJson(e)).toList();
      if (imported.isEmpty) {
        _showSnackBar('导入的文件为空或格式不正确');
        return;
      }

      setState(() => _prompts = imported);
      _savePrompts();
      _showSnackBar('成功导入 ${imported.length} 条 Prompt');
    } catch (e) {
      debugPrint('PromptManager: 导入失败 $e');
      _showSnackBar('导入失败: $e');
    }
  }

  /// 导出 Prompt 列表为 .json 文件
  Future<void> _exportPrompts() async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ')
          .convert(_prompts.map((e) => e.toJson()).toList());

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/prompt_export_$timestamp.json');
      await file.writeAsString(jsonStr);

      _showSnackBar('已导出到: ${file.path}');
    } catch (e) {
      debugPrint('PromptManager: 导出失败 $e');
      _showSnackBar('导出失败: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit Bottom Sheet
  // ---------------------------------------------------------------------------

  void _showEditSheet() {
    final prompt = _editingPrompt;
    if (prompt == null) return;

    // 表单控制器
    final nameCtrl = TextEditingController(text: prompt.name);
    final promptCtrl = TextEditingController(text: prompt.prompt);
    final depthCtrl = TextEditingController(text: prompt.injectionDepth.toString());
    final orderCtrl = TextEditingController(text: prompt.injectionOrder.toString());

    // 可变状态
    String role = prompt.role;
    String injectionPosition = prompt.injectionPosition;
    List<String> triggers = List.of(prompt.injectionTrigger);
    bool forbidOverrides = prompt.forbidOverrides;
    bool enabled = prompt.enabled;

    // 深度/顺序在 @Depth 时才可见
    bool showDepthFields = injectionPosition == '@Depth';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colorScheme = Theme.of(ctx).colorScheme;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.92,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    // 顶部拖拽指示条
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            _editingIndex == null ? '新增 Prompt' : '编辑 Prompt',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (_editingIndex != null &&
                              !(_editingIndex != null && _prompts[_editingIndex!].system))
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: '删除',
                              onPressed: () {
                                Navigator.pop(ctx);
                                _deletePrompt(_editingIndex!);
                              },
                            ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    // 表单内容
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        children: [
                          // --- 名称 ---
                          _sectionLabel('名称', colorScheme),
                          const SizedBox(height: 4),
                          TextField(
                            controller: nameCtrl,
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                            decoration: _inputDecoration('Prompt 名称', colorScheme),
                          ),
                          const SizedBox(height: 16),

                          // --- 角色 ---
                          _sectionLabel('角色', colorScheme),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            value: role,
                            items: _roleOptions.map((r) {
                              return DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setSheetState(() => role = val);
                            },
                            decoration: _inputDecoration('选择角色', colorScheme),
                            dropdownColor: colorScheme.surface,
                          ),
                          const SizedBox(height: 16),

                          // --- 注入触发器 ---
                          _sectionLabel('注入触发器', colorScheme),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _triggerOptions.map((t) {
                              final selected = triggers.contains(t);
                              return FilterChip(
                                label: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: colorScheme.primary,
                                backgroundColor: colorScheme.surface,
                                onSelected: (val) {
                                  setSheetState(() {
                                    if (val) {
                                      triggers.add(t);
                                    } else {
                                      triggers.remove(t);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // --- 注入位置 ---
                          _sectionLabel('注入位置', colorScheme),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            value: injectionPosition,
                            items: _positionOptions.map((p) {
                              return DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setSheetState(() => injectionPosition = val);
                              }
                            },
                            decoration: _inputDecoration('注入位置', colorScheme),
                            dropdownColor: colorScheme.surface,
                          ),
                          const SizedBox(height: 16),

                          // --- 注入深度 & 顺序（仅 @Depth 时显示） ---
                          if (showDepthFields) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionLabel('注入深度', colorScheme),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: depthCtrl,
                                        keyboardType: TextInputType.number,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurface,
                                        ),
                                        decoration: _inputDecoration('0-9999', colorScheme),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _sectionLabel('注入顺序', colorScheme),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: orderCtrl,
                                        keyboardType: TextInputType.number,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurface,
                                        ),
                                        decoration: _inputDecoration('0-9999', colorScheme),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          // --- Prompt 内容 ---
                          _sectionLabel('Prompt 内容', colorScheme),
                          const SizedBox(height: 4),
                          TextField(
                            controller: promptCtrl,
                            maxLines: 8,
                            minLines: 4,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                            decoration: _inputDecoration(
                              '支持 {{char}}、{{user}} 等宏',
                              colorScheme,
                            ).copyWith(
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- 禁止覆盖 ---
                          SwitchListTile(
                            title: Text(
                              '禁止角色卡覆盖',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '开启后角色卡无法覆盖此 Prompt',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                            value: forbidOverrides,
                            onChanged: (val) {
                              setSheetState(() => forbidOverrides = val);
                            },
                            activeColor: colorScheme.primary,
                            contentPadding: EdgeInsets.zero,
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),

                    // 底部按钮
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.onSurface,
                                side: BorderSide(
                                  color: colorScheme.onSurface.withOpacity(0.2),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('取消', style: TextStyle(fontSize: 14)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                _saveEditedPrompt(
                                  nameCtrl.text.trim(),
                                  role,
                                  triggers,
                                  injectionPosition,
                                  depthCtrl.text,
                                  orderCtrl.text,
                                  promptCtrl.text,
                                  forbidOverrides,
                                  enabled,
                                );
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('保存', style: TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 保存编辑后的 Prompt
  void _saveEditedPrompt(
    String name,
    String role,
    List<String> triggers,
    String position,
    String depthStr,
    String orderStr,
    String prompt,
    bool forbidOverrides,
    bool enabled,
  ) {
    if (name.isEmpty) {
      _showSnackBar('名称不能为空');
      return;
    }

    final depth = int.tryParse(depthStr) ?? 4;
    final order = int.tryParse(orderStr) ?? 100;

    final entry = PromptEntry(
      name: name,
      role: role,
      injectionTrigger: triggers.isEmpty ? ['normal'] : triggers,
      injectionPosition: position,
      injectionDepth: depth.clamp(0, 9999),
      injectionOrder: order.clamp(0, 9999),
      prompt: prompt,
      forbidOverrides: forbidOverrides,
      enabled: enabled,
      system: _editingIndex != null ? _prompts[_editingIndex!].system : false,
    );

    setState(() {
      if (_editingIndex != null) {
        _prompts[_editingIndex!] = entry;
      } else {
        _prompts.add(entry);
      }
    });

    _savePrompts();
    _showSnackBar('Prompt "${entry.name}" 已保存');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(String label, ColorScheme colorScheme) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface.withOpacity(0.7),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme colorScheme) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 14,
        color: colorScheme.onSurface.withOpacity(0.3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.onSurface.withOpacity(0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.onSurface.withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      filled: true,
      fillColor: colorScheme.surface,
    );
  }
}
