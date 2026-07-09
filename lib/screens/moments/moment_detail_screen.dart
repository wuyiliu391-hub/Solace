import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/moment.dart';
import '../../repositories/local_storage_repository.dart';


class MomentDetailScreen extends StatefulWidget {
  final Moment moment;

  const MomentDetailScreen({super.key, required this.moment});

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen> {
  late Moment _moment;

  @override
  void initState() {
    super.initState();
    _moment = widget.moment;
  }

  Future<void> _refresh() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final all = await storage.getAllMoments();
      final updated = all.where((m) => m.id == _moment.id).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _moment = updated);
      }
    } catch (e) {
      debugPrint('刷新朋友圈详情失败: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (_moment.source != MomentSource.normal) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);

    final isLiked = _moment.likes.any((l) => l.userId == user.id);
    final updatedLikes = isLiked
        ? _moment.likes.where((l) => l.userId != user.id).toList()
        : [
            ..._moment.likes,
            MomentLike(
                userId: user.id,
                userName: user.nickname,
                createdAt: DateTime.now())
          ];

    final updated = _moment.copyWith(likes: updatedLikes);
    await storage.saveMoment(updated);
    await _refresh();
  }

  void _showCommentDialog() async {
    if (_moment.source != MomentSource.normal) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;
    final textController = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
          left: 16,
          right: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '评论...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (textController.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (textController.text.trim().isEmpty) return;
                    Navigator.pop(ctx, true);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result != true || textController.text.trim().isEmpty) return;

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final comment = MomentComment(
        id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        userName: user.nickname,
        content: textController.text.trim(),
        createdAt: DateTime.now(),
      );

      final updatedMoment = _moment.copyWith(
        comments: [..._moment.comments, comment],
      );
      await storage.saveMoment(updatedMoment);

      await _refresh();
    } catch (e) {
      debugPrint('评论失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    final isLiked =
        user != null && _moment.likes.any((l) => l.userId == user.id);
    final canDelete = user != null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('详情'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(colorScheme),
                const SizedBox(height: 12),
                Text(_moment.content,
                    style: const TextStyle(fontSize: 16, height: 1.5)),
                if (_moment.images.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildImageGrid(context),
                ],
                const SizedBox(height: 8),
                Text(
                  _formatTime(_moment.createdAt),
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5)),
                ),
                const SizedBox(height: 16),
                _buildActions(colorScheme, isLiked, canDelete),
                const Divider(),
                if (_moment.likes.isNotEmpty) _buildLikes(colorScheme),
                if (_moment.likes.isNotEmpty && _moment.comments.isNotEmpty)
                  Divider(
                      height: 1, color: colorScheme.outline.withOpacity(0.15)),
                if (_moment.comments.isNotEmpty) _buildComments(colorScheme),
              ],
            ),
          ),
          _buildBottomBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        _buildAvatar(colorScheme),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_moment.userName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary)),
            const SizedBox(height: 2),
            Text(_formatTime(_moment.createdAt),
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.5))),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          colorScheme.primary.withOpacity(0.8),
          colorScheme.secondary.withOpacity(0.6)
        ]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: (_moment.userAvatar?.isNotEmpty) == true
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildSafeImage(_moment.userAvatar ?? '', BoxFit.cover),
            )
          : Center(
              child: Text(
                  _moment.userName.isNotEmpty
                      ? _moment.userName.substring(0, 1)
                      : '?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.surface))),
    );
  }

  Widget _buildImageGrid(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width - 32;
    if (_moment.images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints:
              BoxConstraints(maxWidth: maxWidth * 0.65, maxHeight: 220),
          child: _buildSafeImage(_moment.images[0], BoxFit.cover),
        ),
      );
    }
    final crossAxisCount = _moment.images.length == 2 ? 2 : 3;
    final spacing = 4.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final itemSize = (maxWidth - totalSpacing) / crossAxisCount;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: _moment.images
          .map((img) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                    width: itemSize,
                    height: itemSize,
                    child: _buildSafeImage(img, BoxFit.cover)),
              ))
          .toList(),
    );
  }

  Widget _buildSafeImage(String path, BoxFit fit) {
    if (path.startsWith('http')) {
      return Image.network(path,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[200],
              child: Icon(Icons.broken_image, color: Colors.grey[400])));
    }
    return Image.file(File(path),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[200],
            child: Icon(Icons.broken_image, color: Colors.grey[400])));
  }

  Widget _buildActions(ColorScheme colorScheme, bool isLiked, bool canDelete) {
    return Row(
      children: [
        InkWell(
          onTap: _toggleLike,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                  color: isLiked
                      ? Colors.red
                      : colorScheme.onSurface.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text(isLiked ? '取消' : '赞',
                  style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
        const SizedBox(width: 24),
        InkWell(
          onTap: _showCommentDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.comment_outlined,
                  size: 20, color: colorScheme.onSurface.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text('评论',
                  style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
        const Spacer(),
        if (canDelete)
          InkWell(
            onTap: () => _deleteMoment(),
            child: Icon(Icons.delete_outline,
                size: 20, color: colorScheme.onSurface.withOpacity(0.4)),
          ),
      ],
    );
  }

  Future<void> _deleteMoment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: Text(
          _moment.isFromAI
              ? '确定要删除 ${_moment.userName} 的这条动态吗？'
              : '确定要删除这条动态吗？此操作不可恢复。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final storage = RepositoryProvider.of<LocalStorageRepository>(context);
        await storage.deleteMoment(_moment.id);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('删除失败: $e');
      }
    }
  }

  Widget _buildLikes(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite,
              size: 16, color: colorScheme.primary.withOpacity(0.8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_moment.likes.map((l) => l.userName).join('，'),
                style: TextStyle(
                    fontSize: 14, color: colorScheme.primary.withOpacity(0.9))),
          ),
        ],
      ),
    );
  }

  Widget _buildComments(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _moment.comments.map((comment) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.85),
                  height: 1.4),
              children: [
                TextSpan(
                  text: comment.userName,
                  style: TextStyle(
                      color: colorScheme.primary.withOpacity(0.9),
                      fontWeight: FontWeight.w500),
                ),
                if (comment.replyToUserName != null) ...[
                  TextSpan(
                      text: ' 回复 ',
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6))),
                  TextSpan(
                    text: comment.replyToUserName,
                    style: TextStyle(
                        color: colorScheme.primary.withOpacity(0.9),
                        fontWeight: FontWeight.w500),
                  ),
                ],
                TextSpan(text: '：${comment.content}'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -1))
        ],
      ),
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showCommentDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('写评论...',
                    style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.4))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    if (messageDate == today) return DateFormat('HH:mm').format(time);
    if (messageDate == today.subtract(const Duration(days: 1)))
      return '昨天 ${DateFormat('HH:mm').format(time)}';
    if (now.difference(time).inDays < 7)
      return DateFormat('E HH:mm', 'zh_CN').format(time);
    return DateFormat('MM月dd日').format(time);
  }
}
