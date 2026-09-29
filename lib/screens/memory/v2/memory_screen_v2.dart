// 【对标来源：Muice-Chatbot-1.4 — llm/faiss_memory.py 记忆管理界面】
// 转译自 Muice 记忆检索逻辑为 Flutter 记忆展示页面

import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "../../../models/emotion_memory_entry.dart";
import "../../../blocs/memory/memory_bloc.dart";

/// 记忆页面 V2（对标 Muice FAISS 记忆管理）
class MemoryScreenV2 extends StatefulWidget {
  final String characterId;
  final String userId;

  const MemoryScreenV2({
    super.key,
    required this.characterId,
    required this.userId,
  });

  @override
  State<MemoryScreenV2> createState() => _MemoryScreenV2State();
}

class _MemoryScreenV2State extends State<MemoryScreenV2> {
  final TextEditingController _searchController = TextEditingController();
  String? _filterEmotion;

  @override
  void initState() {
    super.initState();
    context.read<MemoryBloc>().add(
      LoadMemories(widget.characterId, widget.userId),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filterEmotion = value == 'all' ? null : value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('全部')),
              const PopupMenuItem(value: 'happy', child: Text('开心')),
              const PopupMenuItem(value: 'sad', child: Text('悲伤')),
              const PopupMenuItem(value: 'angry', child: Text('愤怒')),
              const PopupMenuItem(value: 'love', child: Text('爱意')),
              const PopupMenuItem(value: 'neutral', child: Text('平静')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索记忆...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    context.read<MemoryBloc>().add(
                      LoadMemories(widget.characterId, widget.userId),
                    );
                  },
                ),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  context.read<MemoryBloc>().add(SearchMemories(
                    query: value,
                    characterId: widget.characterId,
                    userId: widget.userId,
                    emotionTag: _filterEmotion,
                  ));
                }
              },
            ),
          ),

          // 记忆列表
          Expanded(
            child: BlocBuilder<MemoryBloc, MemoryState>(
              builder: (context, state) {
                if (state is MemoryLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is MemoryError) {
                  return Center(child: Text(state.message));
                }
                if (state is MemoriesLoaded) {
                  return _buildMemoryList(state.memories, state.totalCount, cs);
                }
                if (state is MemoriesSearched) {
                  return _buildMemoryList(state.results, state.results.length, cs);
                }
                return const Center(child: Text('暂无记忆'));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryList(List<EmotionMemoryEntry> memories, int total, ColorScheme cs) {
    if (memories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text('暂无记忆', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 统计信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('共 $total 条记忆', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: memories.length,
            itemBuilder: (context, index) => _buildMemoryCard(memories[index], cs),
          ),
        ),
      ],
    );
  }

  Widget _buildMemoryCard(EmotionMemoryEntry entry, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 情绪标签 + 时间
            Row(
              children: [
                if (entry.emotionTag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getEmotionColor(entry.emotionTag!).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getEmotionLabel(entry.emotionTag!),
                      style: TextStyle(
                        fontSize: 11,
                        color: _getEmotionColor(entry.emotionTag!),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  _formatTime(entry.timestamp),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            if (entry.input.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('用户: ${entry.input}', style: const TextStyle(fontSize: 13)),
            ],
            if (entry.output.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('AI: ${entry.output}', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
            // 权重指示器
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.fitness_center, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '权重: ${entry.weight.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getEmotionColor(String emotion) {
    switch (emotion) {
      case 'happy': return Colors.amber;
      case 'sad': return Colors.blue;
      case 'angry': return Colors.red;
      case 'love': return Colors.pink;
      case 'neutral': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _getEmotionLabel(String emotion) {
    switch (emotion) {
      case 'happy': return '开心';
      case 'sad': return '悲伤';
      case 'angry': return '愤怒';
      case 'love': return '爱意';
      case 'neutral': return '平静';
      default: return emotion;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${time.month}/${time.day}';
  }
}
