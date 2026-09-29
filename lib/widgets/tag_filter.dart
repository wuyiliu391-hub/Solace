// 【对标来源：SillyTavern-1.18.0 — filters.js 标签过滤】
// 1:1 转译自 SillyTavern 角色标签过滤逻辑
// 参考文件：public/scripts/filters.js

import 'package:flutter/material.dart';

/// 标签过滤组件（对标 SillyTavern filters.js）
/// 提供角色标签的多选过滤功能
class TagFilter extends StatefulWidget {
  /// 所有可用标签
  final List<String> allTags;

  /// 当前选中的标签
  final List<String> selectedTags;

  /// 标签选择变化回调
  final ValueChanged<List<String>>? onTagsChanged;

  /// 是否允许多选
  final bool multiSelect;

  /// 是否显示搜索框
  final bool showSearch;

  /// 是否显示计数
  final bool showCount;

  /// 标签计数映射（标签 → 使用该标签的角色数）
  final Map<String, int>? tagCounts;

  /// 是否显示"全部"选项
  final bool showAllOption;

  /// 占位文本
  final String hintText;

  const TagFilter({
    super.key,
    required this.allTags,
    this.selectedTags = const [],
    this.onTagsChanged,
    this.multiSelect = true,
    this.showSearch = true,
    this.showCount = false,
    this.tagCounts,
    this.showAllOption = true,
    this.hintText = '搜索标签...',
  });

  @override
  State<TagFilter> createState() => _TagFilterState();
}

class _TagFilterState extends State<TagFilter> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredTags {
    if (_searchQuery.isEmpty) return widget.allTags;
    return widget.allTags
        .where((tag) => tag.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  bool get _isAllSelected =>
      widget.selectedTags.isEmpty ||
      (widget.selectedTags.length == widget.allTags.length);

  void _toggleTag(String tag) {
    if (widget.onTagsChanged == null) return;

    final newTags = List<String>.from(widget.selectedTags);
    if (widget.multiSelect) {
      if (newTags.contains(tag)) {
        newTags.remove(tag);
      } else {
        newTags.add(tag);
      }
    } else {
      if (newTags.contains(tag)) {
        newTags.clear();
      } else {
        newTags
          ..clear()
          ..add(tag);
      }
    }
    widget.onTagsChanged!(newTags);
  }

  void _selectAll() {
    if (widget.onTagsChanged == null) return;
    widget.onTagsChanged!([]);
  }

  void _clearAll() {
    if (widget.onTagsChanged == null) return;
    widget.onTagsChanged!([]);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 搜索框（对标 SillyTavern 标签搜索）
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

        // 标签列表
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // "全部"选项
              if (widget.showAllOption)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: const Text('全部'),
                    selected: _isAllSelected,
                    onSelected: (_) => _selectAll(),
                    selectedColor: colorScheme.primary.withOpacity(0.2),
                    checkmarkColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: _isAllSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ),

              // 标签列表
              ..._filteredTags.map((tag) {
                final isSelected = widget.selectedTags.contains(tag);
                final count = widget.tagCounts?[tag];

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tag),
                        if (widget.showCount && count != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '($count)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? colorScheme.primary.withOpacity(0.7)
                                  : colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) => _toggleTag(tag),
                    selectedColor: colorScheme.primary.withOpacity(0.2),
                    checkmarkColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

/// 标签显示组件（只读，用于显示角色标签）
class TagDisplay extends StatelessWidget {
  final List<String> tags;
  final double spacing;
  final double runSpacing;
  final EdgeInsets padding;

  const TagDisplay({
    super.key,
    required this.tags,
    this.spacing = 4,
    this.runSpacing = 4,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: tags.map((tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.primary,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
