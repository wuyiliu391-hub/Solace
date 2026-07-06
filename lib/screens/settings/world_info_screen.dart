// 【对标来源：SillyTavern-1.18.0 — world-info.js 世界观管理界面】
// 1:1 转译自 SillyTavern World Info 世界观设定 CRUD 逻辑
// 参考文件：public/scripts/world-info.js

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/character_card_v2.dart';
import '../../repositories/world_info_repository.dart';

/// 世界观管理界面（对标 SillyTavern World Info 面板）
/// 完整实现书本选择、条目 CRUD、全局设置、导入导出、搜索过滤
class WorldInfoScreen extends StatefulWidget {
  const WorldInfoScreen({super.key});

  @override
  State<WorldInfoScreen> createState() => _WorldInfoScreenState();
}

class _WorldInfoScreenState extends State<WorldInfoScreen> {
  final WorldInfoRepository _repo = WorldInfoRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ──────────── 状态 ────────────
  List<Map<String, dynamic>> _books = []; // {id, name, description}
  String? _selectedBookId;
  WorldInfoBook? _currentBook;
  List<WorldInfoEntry> _entries = [];
  String _searchQuery = '';
  bool _loading = true;
  bool _globalSettingsExpanded = false;

  // 全局设置（对标 SillyTavern world_info_* settings）
  int _globalScanDepth = 2;
  int _globalContextBudget = 25;
  bool _globalRecursiveScan = false;
  bool _globalCaseSensitive = false;
  bool _globalMatchWholeWords = false;
  bool _globalUseGroupScoring = false;

  // 条目展开状态（延迟加载）
  final Set<String> _expandedEntryUids = {};

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ──────────── 数据加载 ────────────

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      _books = await _repo.getAllBooks();
      if (_books.isNotEmpty && _selectedBookId == null) {
        _selectedBookId = _books.first['id'] as String;
      }
      if (_selectedBookId != null) {
        await _loadCurrentBook();
      } else {
        _currentBook = null;
        _entries = [];
      }
    } catch (e) {
      _showError('加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCurrentBook() async {
    if (_selectedBookId == null) return;
    try {
      _currentBook = await _repo.getBook(_selectedBookId!);
      _entries = _currentBook?.entries ?? [];
      // 从书本设置恢复全局值
      if (_currentBook != null) {
        _globalScanDepth =
            int.tryParse(_currentBook!.scanDepth ?? '') ?? _globalScanDepth;
        _globalRecursiveScan =
            _currentBook!.recursiveScanning == 'true' ||
                _currentBook!.recursiveScanning == '1';
      }
    } catch (e) {
      _showError('加载条目失败: $e');
    }
  }

  // ──────────── 书本 CRUD ────────────

  Future<void> _createBook() async {
    final name = await _showTextInputDialog(
      title: '创建世界观',
      label: '世界观名称',
      hint: '输入世界观名称',
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      final id = await _repo.createBook(name: name.trim());
      setState(() => _selectedBookId = id);
      await _loadBooks();
    } catch (e) {
      _showError('创建失败: $e');
    }
  }

  Future<void> _renameBook() async {
    if (_selectedBookId == null || _currentBook == null) return;
    final name = await _showTextInputDialog(
      title: '重命名世界观',
      label: '新名称',
      initialValue: _currentBook!.name,
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await _repo.updateBook(_selectedBookId!, name: name.trim());
      await _loadBooks();
    } catch (e) {
      _showError('重命名失败: $e');
    }
  }

  Future<void> _deleteBook() async {
    if (_selectedBookId == null) return;
    final confirmed = await _showConfirmDialog(
      title: '删除世界观',
      message: '确定要删除「${_currentBook?.name ?? ""}」吗？所有条目将一并删除，此操作不可撤销。',
    );
    if (!confirmed) return;

    try {
      await _repo.deleteBook(_selectedBookId!);
      _selectedBookId = null;
      await _loadBooks();
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  Future<void> _importBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择世界观 JSON 文件',
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final id = await _repo.importBookFromJson(json);
      setState(() => _selectedBookId = id);
      await _loadBooks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入成功')),
        );
      }
    } catch (e) {
      _showError('导入失败: $e');
    }
  }

  Future<void> _exportBook() async {
    if (_selectedBookId == null) return;
    try {
      final json = await _repo.exportBookToJson(_selectedBookId!);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(json);

      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出世界观',
        fileName: '${_currentBook?.name ?? "world_info"}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null) return;

      await File(result).writeAsString(jsonStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到: $result')),
        );
      }
    } catch (e) {
      _showError('导出失败: $e');
    }
  }

  // ──────────── 条目 CRUD ────────────

  Future<void> _createEntry() async {
    if (_selectedBookId == null) return;
    try {
      await _repo.createEntry(bookId: _selectedBookId!);
      await _loadCurrentBook();
      if (mounted) setState(() {});
    } catch (e) {
      _showError('创建条目失败: $e');
    }
  }

  Future<void> _duplicateEntry(WorldInfoEntry entry) async {
    if (_selectedBookId == null) return;
    try {
      await _repo.createEntry(
        bookId: _selectedBookId!,
        comment: '${entry.comment} (副本)',
        content: entry.content,
        key: List<String>.from(entry.key),
        keysecondary: List<String>.from(entry.keysecondary),
        constant: entry.constant,
        vectorized: entry.vectorized,
        selective: entry.selective,
        disable: entry.disable,
        position: entry.position,
        depth: entry.depth,
        order: entry.order,
        probability: entry.probability,
        useGroupScoring: entry.useGroupScoring,
        scanDepth: entry.scanDepth,
        caseSensitive: entry.caseSensitive,
        matchWholeWords: entry.matchWholeWords,
        excludeRecursion: entry.excludeRecursion,
        preventRecursion: entry.preventRecursion,
        delayUntilRecursion: entry.delayUntilRecursion,
        sticky: entry.sticky,
        cooldown: entry.cooldown,
        delay: entry.delay,
        outletName: entry.outletName,
        role: entry.role,
        entryLogicType: entry.entryLogicType,
        triggers: entry.triggers,
        automationId: entry.automationId,
      );
      await _loadCurrentBook();
      if (mounted) setState(() {});
    } catch (e) {
      _showError('复制条目失败: $e');
    }
  }

  Future<void> _deleteEntry(WorldInfoEntry entry) async {
    final confirmed = await _showConfirmDialog(
      title: '删除条目',
      message: '确定要删除条目「${entry.comment.isEmpty ? "(无备注)" : entry.comment}」吗？',
    );
    if (!confirmed) return;

    try {
      await _repo.deleteEntry(entry.uid);
      _expandedEntryUids.remove(entry.uid);
      await _loadCurrentBook();
      if (mounted) setState(() {});
    } catch (e) {
      _showError('删除条目失败: $e');
    }
  }

  Future<void> _updateEntry(WorldInfoEntry entry) async {
    try {
      await _repo.updateEntry(entry.uid, entry);
      // 刷新本地列表中的对应条目
      final idx = _entries.indexWhere((e) => e.uid == entry.uid);
      if (idx >= 0) {
        setState(() => _entries[idx] = entry);
      }
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  void _reorderEntries(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _entries.removeAt(oldIndex);
      _entries.insert(newIndex, item);
      // 更新排序
      for (int i = 0; i < _entries.length; i++) {
        final e = _entries[i];
        final updated = WorldInfoEntry(
          uid: e.uid,
          comment: e.comment,
          content: e.content,
          key: e.key,
          keysecondary: e.keysecondary,
          constant: e.constant,
          vectorized: e.vectorized,
          selective: e.selective,
          disable: e.disable,
          position: e.position,
          depth: e.depth,
          order: i * 100,
          probability: e.probability,
          useGroupScoring: e.useGroupScoring,
          scanDepth: e.scanDepth,
          caseSensitive: e.caseSensitive,
          matchWholeWords: e.matchWholeWords,
          excludeRecursion: e.excludeRecursion,
          preventRecursion: e.preventRecursion,
          delayUntilRecursion: e.delayUntilRecursion,
          sticky: e.sticky,
          cooldown: e.cooldown,
          delay: e.delay,
          outletName: e.outletName,
          role: e.role,
          entryLogicType: e.entryLogicType,
          triggers: e.triggers,
          automationId: e.automationId,
        );
        _entries[i] = updated;
        _repo.updateEntry(updated.uid, updated);
      }
    });
  }

  // ──────────── 过滤条目 ────────────

  List<WorldInfoEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries.where((e) {
      return e.comment.toLowerCase().contains(q) ||
          e.key.any((k) => k.toLowerCase().contains(q)) ||
          e.keysecondary.any((k) => k.toLowerCase().contains(q)) ||
          e.content.toLowerCase().contains(q);
    }).toList();
  }

  // ──────────── Build ────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('世界观管理'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          if (_selectedBookId != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建条目',
              onPressed: _createEntry,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBookSelector(colorScheme),
                if (_selectedBookId != null) ...[
                  _buildSearchBar(colorScheme),
                  _buildGlobalSettings(colorScheme),
                  Expanded(child: _buildEntryList(colorScheme)),
                ] else
                  Expanded(child: _buildEmptyState(colorScheme)),
              ],
            ),
    );
  }

  // ──────────── Book Selector ────────────

  Widget _buildBookSelector(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _books.isEmpty
                ? Text(
                    '暂无世界观，点击创建',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 15,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    value: _selectedBookId,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      isDense: true,
                    ),
                    items: _books.map((book) {
                      return DropdownMenuItem<String>(
                        value: book['id'] as String,
                        child: Text(
                          book['name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _selectedBookId = value;
                        _expandedEntryUids.clear();
                      });
                      await _loadCurrentBook();
                      if (mounted) setState(() {});
                    },
                  ),
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            icon: Icons.add_circle_outline,
            tooltip: '创建',
            onPressed: _createBook,
            colorScheme: colorScheme,
          ),
          if (_selectedBookId != null) ...[
            _buildIconButton(
              icon: Icons.edit_outlined,
              tooltip: '重命名',
              onPressed: _renameBook,
              colorScheme: colorScheme,
            ),
            _buildIconButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              onPressed: _deleteBook,
              colorScheme: colorScheme,
            ),
          ],
          _buildIconButton(
            icon: Icons.file_upload_outlined,
            tooltip: '导入',
            onPressed: _importBook,
            colorScheme: colorScheme,
          ),
          if (_selectedBookId != null)
            _buildIconButton(
              icon: Icons.file_download_outlined,
              tooltip: '导出',
              onPressed: _exportBook,
              colorScheme: colorScheme,
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }

  // ──────────── Search Bar ────────────

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索条目（备注/关键词/内容）',
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.4),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  // ──────────── Global Settings ────────────

  Widget _buildGlobalSettings(ColorScheme colorScheme) {
    return ExpansionTile(
      title: Text(
        '全局设置',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      leading: Icon(Icons.tune, color: colorScheme.primary, size: 22),
      initiallyExpanded: _globalSettingsExpanded,
      onExpansionChanged: (expanded) {
        setState(() => _globalSettingsExpanded = expanded);
      },
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _buildSliderSetting(
          label: '扫描深度 (Scan Depth)',
          value: _globalScanDepth.toDouble(),
          min: 0,
          max: 1000,
          divisions: 100,
          displayValue: '$_globalScanDepth',
          onChanged: (v) => setState(() => _globalScanDepth = v.round()),
          colorScheme: colorScheme,
        ),
        _buildSliderSetting(
          label: '上下文预算 (Context Budget)',
          value: _globalContextBudget.toDouble(),
          min: 1,
          max: 100,
          divisions: 100,
          displayValue: '$_globalContextBudget%',
          onChanged: (v) =>
              setState(() => _globalContextBudget = v.round()),
          colorScheme: colorScheme,
        ),
        _buildCheckboxSetting(
          label: '递归扫描 (Recursive Scan)',
          value: _globalRecursiveScan,
          onChanged: (v) => setState(() => _globalRecursiveScan = v ?? false),
          colorScheme: colorScheme,
        ),
        _buildCheckboxSetting(
          label: '区分大小写 (Case-Sensitive)',
          value: _globalCaseSensitive,
          onChanged: (v) =>
              setState(() => _globalCaseSensitive = v ?? false),
          colorScheme: colorScheme,
        ),
        _buildCheckboxSetting(
          label: '全词匹配 (Match Whole Words)',
          value: _globalMatchWholeWords,
          onChanged: (v) =>
              setState(() => _globalMatchWholeWords = v ?? false),
          colorScheme: colorScheme,
        ),
        _buildCheckboxSetting(
          label: '使用分组评分 (Group Scoring)',
          value: _globalUseGroupScoring,
          onChanged: (v) =>
              setState(() => _globalUseGroupScoring = v ?? false),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildSliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.outline.withOpacity(0.2),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withOpacity(0.1),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxSetting({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required ColorScheme colorScheme,
  }) {
    return SizedBox(
      height: 40,
      child: CheckboxListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: colorScheme.primary,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }

  // ──────────── Empty State ────────────

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无世界观',
            style: TextStyle(
              fontSize: 17,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击上方 + 按钮创建一个世界观',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createBook,
            icon: const Icon(Icons.add),
            label: const Text('创建世界观'),
          ),
        ],
      ),
    );
  }

  // ──────────── Entry List ────────────

  Widget _buildEntryList(ColorScheme colorScheme) {
    final filtered = _filteredEntries;

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 48,
              color: colorScheme.onSurface.withOpacity(0.2),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无条目',
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _createEntry,
              child: const Text('新建条目'),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的条目',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      scrollController: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: filtered.length,
      onReorder: _reorderEntries,
      itemBuilder: (context, index) {
        final entry = filtered[index];
        return _buildEntryTile(entry, index, colorScheme);
      },
    );
  }

  // ──────────── Entry Tile ────────────

  Widget _buildEntryTile(
    WorldInfoEntry entry,
    int index,
    ColorScheme colorScheme,
  ) {
    final isExpanded = _expandedEntryUids.contains(entry.uid);
    final displayName = entry.comment.isEmpty ? '(无备注)' : entry.comment;
    final truncatedName = displayName.length > 40
        ? '${displayName.substring(0, 40)}...'
        : displayName;

    return Card(
      key: ValueKey(entry.uid),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 0,
      color: entry.disable
          ? colorScheme.surfaceContainerHighest.withOpacity(0.3)
          : colorScheme.surface,
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedEntryUids.add(entry.uid);
            } else {
              _expandedEntryUids.remove(entry.uid);
            }
          });
        },
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(
            Icons.drag_handle,
            color: colorScheme.onSurface.withOpacity(0.4),
            size: 22,
          ),
        ),
        title: Row(
          children: [
            // Kill switch
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: !entry.disable,
                onChanged: (value) {
                  _updateEntry(WorldInfoEntry(
                    uid: entry.uid,
                    comment: entry.comment,
                    content: entry.content,
                    key: entry.key,
                    keysecondary: entry.keysecondary,
                    constant: entry.constant,
                    vectorized: entry.vectorized,
                    selective: entry.selective,
                    disable: !value,
                    position: entry.position,
                    depth: entry.depth,
                    order: entry.order,
                    probability: entry.probability,
                    useGroupScoring: entry.useGroupScoring,
                    scanDepth: entry.scanDepth,
                    caseSensitive: entry.caseSensitive,
                    matchWholeWords: entry.matchWholeWords,
                    excludeRecursion: entry.excludeRecursion,
                    preventRecursion: entry.preventRecursion,
                    delayUntilRecursion: entry.delayUntilRecursion,
                    sticky: entry.sticky,
                    cooldown: entry.cooldown,
                    delay: entry.delay,
                    outletName: entry.outletName,
                    role: entry.role,
                    entryLogicType: entry.entryLogicType,
                    triggers: entry.triggers,
                    automationId: entry.automationId,
                  ));
                },
                activeColor: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            // Comment text
            Expanded(
              child: Text(
                truncatedName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: entry.disable
                      ? colorScheme.onSurface.withOpacity(0.4)
                      : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 52, top: 2, bottom: 2),
          child: Row(
            children: [
              // Entry state indicator
              _buildStateChip(entry, colorScheme),
              const SizedBox(width: 6),
              // Position dropdown
              _buildCompactPositionDropdown(entry, colorScheme),
              const SizedBox(width: 6),
              // Depth (only when atDepth)
              if (entry.position == 4)
                _buildCompactNumberInput(
                  label: '深度',
                  value: entry.depth,
                  onChanged: (v) => _updateEntryField(entry, depth: v),
                  colorScheme: colorScheme,
                  width: 50,
                ),
              // Order
              _buildCompactNumberInput(
                label: '排序',
                value: entry.order,
                onChanged: (v) => _updateEntryField(entry, order: v),
                colorScheme: colorScheme,
                width: 50,
              ),
              // Probability
              _buildCompactNumberInput(
                label: '概率',
                value: entry.probability,
                suffix: '%',
                onChanged: (v) => _updateEntryField(entry, probability: v),
                colorScheme: colorScheme,
                width: 55,
              ),
              const Spacer(),
              // Duplicate
              IconButton(
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                tooltip: '复制',
                onPressed: () => _duplicateEntry(entry),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              // Delete
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: colorScheme.error.withOpacity(0.7),
                ),
                tooltip: '删除',
                onPressed: () => _deleteEntry(entry),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ),
        children: [
          if (isExpanded) _buildEntryExpandedContent(entry, colorScheme),
        ],
      ),
    );
  }

  // ──────────── Entry State Chip ────────────

  Widget _buildStateChip(WorldInfoEntry entry, ColorScheme colorScheme) {
    Color chipColor;
    String label;
    if (entry.constant) {
      chipColor = Colors.blue;
      label = '常驻';
    } else if (entry.vectorized) {
      chipColor = Colors.purple;
      label = '向量';
    } else {
      chipColor = Colors.green;
      label = '普通';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: chipColor,
        ),
      ),
    );
  }

  // ──────────── Compact Position Dropdown ────────────

  Widget _buildCompactPositionDropdown(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    const positionLabels = {
      0: '角色前',
      1: '角色后',
      2: 'AN顶',
      3: 'AN底',
      4: '深度',
      5: 'EM顶',
      6: 'EM底',
      7: '出口',
    };

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: entry.position,
          isDense: true,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
          items: positionLabels.entries.map((e) {
            return DropdownMenuItem<int>(
              value: e.key,
              child: Text(e.value),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) _updateEntryField(entry, position: v);
          },
        ),
      ),
    );
  }

  // ──────────── Compact Number Input ────────────

  Widget _buildCompactNumberInput({
    required String label,
    required int value,
    String? suffix,
    required ValueChanged<int> onChanged,
    required ColorScheme colorScheme,
    double width = 50,
  }) {
    return SizedBox(
      width: width,
      height: 26,
      child: TextField(
        controller: TextEditingController(
          text: suffix != null ? '$value$suffix' : '$value',
        ),
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurface.withOpacity(0.8),
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: colorScheme.outline.withOpacity(0.2),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: colorScheme.outline.withOpacity(0.2),
            ),
          ),
        ),
        keyboardType: TextInputType.number,
        onSubmitted: (text) {
          final cleaned = text.replaceAll(RegExp(r'[^0-9\-]'), '');
          final parsed = int.tryParse(cleaned);
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }

  // ──────────── Entry Expanded Content ────────────

  Widget _buildEntryExpandedContent(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: colorScheme.outline.withOpacity(0.1)),
          // Row 1: Keywords
          _buildKeywordsSection(entry, colorScheme),
          const SizedBox(height: 16),
          // Row 2: Content
          _buildContentSection(entry, colorScheme),
          const SizedBox(height: 16),
          // Row 3: Timed Effects
          _buildTimedEffectsSection(entry, colorScheme),
          const SizedBox(height: 16),
          // Row 4: Overrides
          _buildOverridesSection(entry, colorScheme),
          const SizedBox(height: 16),
          // Row 5: Generation Triggers
          _buildTriggersSection(entry, colorScheme),
        ],
      ),
    );
  }

  // ──────────── Row 1: Keywords ────────────

  Widget _buildKeywordsSection(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    const logicLabels = {
      0: 'AND ANY',
      1: 'NOT ALL',
      2: 'NOT ANY',
      3: 'AND ALL',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('关键词', colorScheme),
        const SizedBox(height: 8),
        // Primary Keywords
        _buildTextField(
          label: '主关键词（逗号分隔）',
          value: entry.key.join(', '),
          onChanged: (text) {
            final keys = text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            _updateEntryField(entry, key: keys);
          },
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 8),
        // Logic dropdown
        Row(
          children: [
            Text(
              '匹配逻辑:',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: entry.entryLogicType,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                  items: logicLabels.entries.map((e) {
                    return DropdownMenuItem<int>(
                      value: e.key,
                      child: Text(e.value),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _updateEntryField(entry, entryLogicType: v);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Secondary Keywords
        _buildTextField(
          label: '次关键词（逗号分隔）',
          value: entry.keysecondary.join(', '),
          onChanged: (text) {
            final keys = text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            _updateEntryField(entry, keysecondary: keys);
          },
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  // ──────────── Row 2: Content ────────────

  Widget _buildContentSection(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('内容', colorScheme),
        const SizedBox(height: 8),
        _buildTextField(
          label: '注入内容',
          value: entry.content,
          maxLines: 6,
          onChanged: (text) => _updateEntryField(entry, content: text),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _buildCompactCheckbox(
              label: '排除递归 (excludeRecursion)',
              value: entry.excludeRecursion,
              onChanged: (v) =>
                  _updateEntryField(entry, excludeRecursion: v ?? false),
              colorScheme: colorScheme,
            ),
            _buildCompactCheckbox(
              label: '阻止递归 (preventRecursion)',
              value: entry.preventRecursion,
              onChanged: (v) =>
                  _updateEntryField(entry, preventRecursion: v ?? false),
              colorScheme: colorScheme,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '递归延迟:',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              height: 30,
              child: TextField(
                controller: TextEditingController(
                  text: '${entry.delayUntilRecursion}',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (text) {
                  final v = int.tryParse(text);
                  if (v != null) {
                    _updateEntryField(entry, delayUntilRecursion: v);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────── Row 3: Timed Effects ────────────

  Widget _buildTimedEffectsSection(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('定时效果', colorScheme),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildNumberField(
                label: 'Sticky',
                value: entry.sticky,
                hint: '默认',
                onChanged: (v) => _updateEntryField(entry, sticky: v),
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildNumberField(
                label: 'Cooldown',
                value: entry.cooldown,
                hint: '默认',
                onChanged: (v) => _updateEntryField(entry, cooldown: v),
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildNumberField(
                label: 'Delay',
                value: entry.delay,
                hint: '默认',
                onChanged: (v) => _updateEntryField(entry, delay: v),
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────── Row 4: Overrides ────────────

  Widget _buildOverridesSection(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('覆盖设置', colorScheme),
        const SizedBox(height: 8),
        // Outlet Name
        _buildTextField(
          label: '出口名称 (Outlet Name)',
          value: entry.outletName ?? '',
          onChanged: (text) => _updateEntryField(
            entry,
            outletName: text.isEmpty ? null : text,
          ),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Scan Depth
            Expanded(
              child: _buildNumberField(
                label: '扫描深度',
                value: entry.scanDepth == 0 ? null : entry.scanDepth,
                hint: '使用全局',
                onChanged: (v) =>
                    _updateEntryField(entry, scanDepth: v ?? 0),
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            // Automation ID
            Expanded(
              child: _buildTextField(
                label: '自动化 ID',
                value: entry.automationId ?? '',
                onChanged: (text) => _updateEntryField(
                  entry,
                  automationId: text.isEmpty ? null : text,
                ),
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Tri-state checkboxes
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _buildTriStateSetting(
              label: '区分大小写',
              value: entry.caseSensitive,
              onChanged: (v) =>
                  _updateEntryField(entry, caseSensitive: v),
              colorScheme: colorScheme,
            ),
            _buildTriStateSetting(
              label: '全词匹配',
              value: entry.matchWholeWords,
              onChanged: (v) =>
                  _updateEntryField(entry, matchWholeWords: v),
              colorScheme: colorScheme,
            ),
            _buildTriStateSetting(
              label: '分组评分',
              value: entry.useGroupScoring,
              onChanged: (v) =>
                  _updateEntryField(entry, useGroupScoring: v),
              colorScheme: colorScheme,
            ),
          ],
        ),
      ],
    );
  }

  // ──────────── Row 5: Generation Triggers ────────────

  Widget _buildTriggersSection(
    WorldInfoEntry entry,
    ColorScheme colorScheme,
  ) {
    const triggerOptions = [
      ('normal', '普通'),
      ('continue', '继续'),
      ('impersonate', '角色扮演'),
      ('swipe', '滑动'),
      ('regenerate', '重新生成'),
      ('quiet', '静默'),
    ];

    final currentTriggers = entry.triggers ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('生成触发器', colorScheme),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: triggerOptions.map((opt) {
            final isSelected = currentTriggers.contains(opt.$1);
            return FilterChip(
              label: Text(
                opt.$2,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                List<String> newTriggers = List.from(currentTriggers);
                if (selected) {
                  newTriggers.add(opt.$1);
                } else {
                  newTriggers.remove(opt.$1);
                }
                _updateEntryField(
                  entry,
                  triggers: newTriggers.isEmpty ? null : newTriggers,
                );
              },
              selectedColor: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest
                  .withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }

  // ──────────── Entry Field Update Helper ────────────

  /// 创建新的 WorldInfoEntry 实例并保存（对标 SillyTavern saveWorldInfoEntry）
  void _updateEntryField(
    WorldInfoEntry entry, {
    String? comment,
    String? content,
    List<String>? key,
    List<String>? keysecondary,
    bool? constant,
    bool? vectorized,
    bool? selective,
    bool? disable,
    int? position,
    int? depth,
    int? order,
    int? probability,
    bool? useGroupScoring,
    int? scanDepth,
    bool? caseSensitive,
    bool? matchWholeWords,
    bool? excludeRecursion,
    bool? preventRecursion,
    int? delayUntilRecursion,
    int? sticky,
    int? cooldown,
    int? delay,
    String? outletName,
    int? role,
    int? entryLogicType,
    List<String>? triggers,
    String? automationId,
  }) {
    final updated = WorldInfoEntry(
      uid: entry.uid,
      comment: comment ?? entry.comment,
      content: content ?? entry.content,
      key: key ?? entry.key,
      keysecondary: keysecondary ?? entry.keysecondary,
      constant: constant ?? entry.constant,
      vectorized: vectorized ?? entry.vectorized,
      selective: selective ?? entry.selective,
      disable: disable ?? entry.disable,
      position: position ?? entry.position,
      depth: depth ?? entry.depth,
      order: order ?? entry.order,
      probability: probability ?? entry.probability,
      useGroupScoring: useGroupScoring ?? entry.useGroupScoring,
      scanDepth: scanDepth ?? entry.scanDepth,
      caseSensitive: caseSensitive ?? entry.caseSensitive,
      matchWholeWords: matchWholeWords ?? entry.matchWholeWords,
      excludeRecursion: excludeRecursion ?? entry.excludeRecursion,
      preventRecursion: preventRecursion ?? entry.preventRecursion,
      delayUntilRecursion: delayUntilRecursion ?? entry.delayUntilRecursion,
      sticky: sticky ?? entry.sticky,
      cooldown: cooldown ?? entry.cooldown,
      delay: delay ?? entry.delay,
      outletName: outletName ?? entry.outletName,
      role: role ?? entry.role,
      entryLogicType: entryLogicType ?? entry.entryLogicType,
      triggers: triggers ?? entry.triggers,
      automationId: automationId ?? entry.automationId,
    );
    _updateEntry(updated);
  }

  // ──────────── Shared Widget Builders ────────────

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    int maxLines = 1,
    required ValueChanged<String> onChanged,
    required ColorScheme colorScheme,
  }) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      maxLines: maxLines,
      style: TextStyle(
        fontSize: 13,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField({
    required String label,
    required int? value,
    required String hint,
    required ValueChanged<int?> onChanged,
    required ColorScheme colorScheme,
  }) {
    return TextField(
      controller: TextEditingController(
        text: value != null ? '$value' : '',
      ),
      style: TextStyle(
        fontSize: 13,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withOpacity(0.3),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
      keyboardType: TextInputType.number,
      onSubmitted: (text) {
        if (text.isEmpty) {
          onChanged(null);
          return;
        }
        final parsed = int.tryParse(text);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _buildCompactCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required ColorScheme colorScheme,
  }) {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 三态复选框（对标 SillyTavern tri-state：使用全局 / 是 / 否）
  Widget _buildTriStateSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme colorScheme,
  }) {
    // 使用 PopupMenuButton 模拟三态选择
    return InkWell(
      onTap: () async {
        final selected = await showMenu<int>(
          context: context,
          position: RelativeRect.fill,
          items: [
            const PopupMenuItem(value: 0, child: Text('使用全局')),
            const PopupMenuItem(value: 1, child: Text('是')),
            const PopupMenuItem(value: 2, child: Text('否')),
          ],
        );
        if (selected != null) {
          if (selected == 0) {
            // 全局值：由上层决定，这里用默认
            onChanged(false);
          } else if (selected == 1) {
            onChanged(true);
          } else {
            onChanged(false);
          }
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: value
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────── Dialog Helpers ────────────

  Future<String?> _showTextInputDialog({
    required String title,
    required String label,
    String? initialValue,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (value) =>
                Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
