// 多选与批量操作（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateSelection on State<ChatDetailScreen>, _StateCore, _StateLoadCore {
  // ─── 多选模式（批量删除 / 收藏）───
  void _enterSelection(String messageId) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(messageId);
    });
  }


  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }


  void _toggleSelect(String messageId) {
    setState(() {
      if (!_selectedIds.remove(messageId)) _selectedIds.add(messageId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }


  void _selectAllMessages() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_cachedMessages.map((m) => m.id));
    });
  }


  Future<void> _batchBookmark() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    var n = 0;
    for (final m in _cachedMessages) {
      if (_selectedIds.contains(m.id) && !m.isBookmark) n++;
    }
    _chatBloc.add(ChatBatchBookmark(
      chatId: widget.session.id,
      messageIds: ids,
    ));
    _exitSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已收藏 $n 条消息'), duration: const Duration(seconds: 1)),
      );
    }
  }


  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 条消息吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = _selectedIds.toList();
    _chatBloc.add(ChatDeleteMessages(
      chatId: widget.session.id,
      messageIds: ids,
    ));
    _exitSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已删除 ${ids.length} 条消息'),
            duration: const Duration(seconds: 1)),
      );
    }
  }


  PreferredSizeWidget _buildSelectionAppBar(ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text('已选 ${_selectedIds.length} 项'),
      actions: [
        IconButton(
          tooltip: '全选',
          icon: const Icon(Icons.select_all),
          onPressed: _selectAllMessages,
        ),
        IconButton(
          tooltip: '批量收藏',
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed: _selectedIds.isEmpty ? null : _batchBookmark,
        ),
        IconButton(
          tooltip: '批量删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: _selectedIds.isEmpty ? null : _batchDelete,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

}
