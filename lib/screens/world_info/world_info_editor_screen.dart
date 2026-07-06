// 【对标来源：SillyTavern-1.18.0 — public/scripts/world-info.js 世界观编辑器】
// 1:1 转译自 SillyTavern World Info 编辑 UI 为 Flutter 页面

import "package:flutter/material.dart";
import "../../models/character_card_v2.dart";
import "../../repositories/world_info_repository.dart";

/// 世界观编辑页面（对标 SillyTavern World Info 编辑器）
class WorldInfoEditorScreen extends StatefulWidget {
  final String? bookId;
  final String? characterId;

  const WorldInfoEditorScreen({super.key, this.bookId, this.characterId});

  @override
  State<WorldInfoEditorScreen> createState() => _WorldInfoEditorScreenState();
}

class _WorldInfoEditorScreenState extends State<WorldInfoEditorScreen> {
  final WorldInfoRepository _wiRepo = WorldInfoRepository.instance;

  List<WorldInfoEntry> _entries = [];
  String _bookName = '';
  String _bookDescription = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (widget.bookId == null) {
      setState(() => _loading = false);
      return;
    }
    final entries = await _wiRepo.getEntries(widget.bookId!);
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('世界观编辑'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addEntry),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveBook),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 书本信息
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(labelText: '书本名称', border: OutlineInputBorder()),
                        onChanged: (v) => _bookName = v,
                        controller: TextEditingController(text: _bookName),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder()),
                        onChanged: (v) => _bookDescription = v,
                        controller: TextEditingController(text: _bookDescription),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                // 条目列表
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(child: Text('暂无条目，点击右上角 + 添加'))
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) => _buildEntryCard(index),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEntryCard(int index) {
    final entry = _entries[index];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        title: Row(
          children: [
            if (entry.constant)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(4)),
                child: const Text('常驻', style: TextStyle(fontSize: 10)),
              ),
            if (entry.disable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(4)),
                child: const Text('禁用', style: TextStyle(fontSize: 10)),
              ),
            Expanded(
              child: Text(entry.comment.isEmpty ? '条目 ${index + 1}' : entry.comment, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text(
          entry.key.join(', '),
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 备注
                TextField(
                  decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder()),
                  controller: TextEditingController(text: entry.comment),
                  onChanged: (v) => _entries[index] = WorldInfoEntry(
                    uid: entry.uid, comment: v, content: entry.content,
                    key: entry.key, keysecondary: entry.keysecondary,
                    constant: entry.constant, disable: entry.disable,
                    position: entry.position, depth: entry.depth,
                    order: entry.order, probability: entry.probability,
                  ),
                ),
                const SizedBox(height: 8),
                // 主关键词
                TextField(
                  decoration: const InputDecoration(labelText: '主关键词（逗号分隔）', border: OutlineInputBorder()),
                  controller: TextEditingController(text: entry.key.join(', ')),
                  onChanged: (v) => _entries[index] = WorldInfoEntry(
                    uid: entry.uid, comment: entry.comment, content: entry.content,
                    key: v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                    keysecondary: entry.keysecondary,
                    constant: entry.constant, disable: entry.disable,
                    position: entry.position, depth: entry.depth,
                    order: entry.order, probability: entry.probability,
                  ),
                ),
                const SizedBox(height: 8),
                // 内容
                TextField(
                  decoration: const InputDecoration(labelText: '内容', border: OutlineInputBorder()),
                  controller: TextEditingController(text: entry.content),
                  onChanged: (v) => _entries[index] = WorldInfoEntry(
                    uid: entry.uid, comment: entry.comment, content: v,
                    key: entry.key, keysecondary: entry.keysecondary,
                    constant: entry.constant, disable: entry.disable,
                    position: entry.position, depth: entry.depth,
                    order: entry.order, probability: entry.probability,
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 8),
                // 开关行
                Row(
                  children: [
                    _buildToggle('常驻', entry.constant, (v) => _updateEntry(index, constant: v)),
                    _buildToggle('禁用', entry.disable, (v) => _updateEntry(index, disable: v)),
                    _buildToggle('选择性', entry.selective, (v) => _updateEntry(index, selective: v)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteEntry(index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ],
    );
  }

  void _updateEntry(int index, {bool? constant, bool? disable, bool? selective}) {
    final entry = _entries[index];
    setState(() {
      _entries[index] = WorldInfoEntry(
        uid: entry.uid, comment: entry.comment, content: entry.content,
        key: entry.key, keysecondary: entry.keysecondary,
        constant: constant ?? entry.constant,
        disable: disable ?? entry.disable,
        selective: selective ?? entry.selective,
        position: entry.position, depth: entry.depth,
        order: entry.order, probability: entry.probability,
      );
    });
  }

  void _addEntry() {
    setState(() {
      _entries.add(const WorldInfoEntry(comment: '', content: '', key: []));
    });
  }

  void _deleteEntry(int index) {
    setState(() => _entries.removeAt(index));
  }

  Future<void> _saveBook() async {
    if (widget.bookId != null) {
      await _wiRepo.updateBook(widget.bookId!, name: _bookName, description: _bookDescription);
      for (final entry in _entries) {
        // TODO: update existing entries
      }
    }
    if (mounted) Navigator.pop(context);
  }
}

