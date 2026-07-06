import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/forum_service.dart';
import '../../models/forum_post.dart';

/// 虚拟日记 — Lofter 风格信息流
///
/// 功能：
/// - 帖子列表（支持下拉刷新）
/// - 发帖（标题 + 内容 + 匿名 + @AI 提及）
/// - 帖子详情（评论列表 + 回复输入）
/// - 点赞动画
/// - AI 帖子特殊标识
class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final Uuid _uuid = const Uuid();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openComposeScreen(context),
        backgroundColor: const Color(0xFFFF6B6B),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: _ForumBody(
        uuid: _uuid,
        onRefresh: () => setState(() {}),
      ),
    );
  }

  void _openComposeScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ComposePostScreen(uuid: _uuid),
      ),
    ).then((result) {
      if (result == true) setState(() {});
    });
  }
}

/// 帖子列表主体
class _ForumBody extends StatefulWidget {
  final Uuid uuid;
  final VoidCallback onRefresh;

  const _ForumBody({required this.uuid, required this.onRefresh});

  @override
  State<_ForumBody> createState() => _ForumBodyState();
}

class _ForumBodyState extends State<_ForumBody> {
  List<ForumPost> _posts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );
      final posts = await forumService.getPosts(limit: 50);
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );
      final posts = await forumService.getPosts(limit: 50);
      setState(() {
        _posts = posts;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有帖子',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮发第一篇帖子',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFF6B6B),
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return _ForumPostCard(
            post: post,
            onLikeChanged: (updatedPost) {
              setState(() {
                _posts[index] = updatedPost;
              });
            },
          );
        },
      ),
    );
  }
}

/// 帖子卡片
class _ForumPostCard extends StatefulWidget {
  final ForumPost post;
  final ValueChanged<ForumPost> onLikeChanged;

  const _ForumPostCard({
    required this.post,
    required this.onLikeChanged,
  });

  @override
  State<_ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<_ForumPostCard>
    with SingleTickerProviderStateMixin {
  bool _isAnimatingLike = false;

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}月${time.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final post = widget.post;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ForumDetailScreen(post: post),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：头像 + 作者 + 时间
              Row(
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    backgroundImage: post.authorAvatar != null
                        ? NetworkImage(post.authorAvatar!)
                        : null,
                    child: post.authorAvatar == null
                        ? (post.isAnonymous
                            ? const Icon(Icons.theater_comedy, size: 16)
                            : Text(
                                post.authorName.isNotEmpty
                                    ? post.authorName[0]
                                    : '?',
                                style: const TextStyle(fontSize: 16),
                              ))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  // 作者名
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.isAnonymous ? '匿名用户' : post.authorName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (post.isFromAI) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B6B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 时间
                  Text(
                    _formatTime(post.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 标题
              Text(
                post.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // 内容预览
              Text(
                post.content,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // 标签
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: post.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$tag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF6B6B),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 12),

              // 底部：点赞 + 评论
              Row(
                children: [
                  // 点赞按钮
                  GestureDetector(
                    onTap: _toggleLike,
                    child: Row(
                      children: [
                        AnimatedScale(
                          scale: _isAnimatingLike ? 1.3 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            post.likes.contains('current_user')
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 20,
                            color: post.likes.contains('current_user')
                                ? const Color(0xFFFF6B6B)
                                : colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likes.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // 评论数
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '0',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike() async {
    setState(() => _isAnimatingLike = true);

    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );
      final updated = await forumService.toggleLike(
        postId: widget.post.id,
        userId: 'current_user',
      );
      widget.onLikeChanged(updated);
    } catch (e) {
      debugPrint('点赞失败: $e');
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isAnimatingLike = false);
    });
  }
}

/// 帖子详情页
class ForumDetailScreen extends StatefulWidget {
  final ForumPost post;

  const ForumDetailScreen({super.key, required this.post});

  @override
  State<ForumDetailScreen> createState() => _ForumDetailScreenState();
}

class _ForumDetailScreenState extends State<ForumDetailScreen> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  List<ForumComment> _comments = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );
      final comments = await forumService.getComments(widget.post.id);
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );
      await forumService.createComment(
        postId: widget.post.id,
        authorId: 'current_user',
        authorName: '我',
        content: content,
      );
      _replyController.clear();
      _replyFocus.unfocus();
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}月${time.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('帖子详情'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 帖子内容 + 评论列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // 帖子主体
                _buildPostContent(colorScheme),
                const Divider(height: 32),

                // 评论列表
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '暂无评论，来抢沙发吧',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_comments.length, (index) {
                    return _buildCommentItem(_comments[index], colorScheme);
                  }),

                const SizedBox(height: 80),
              ],
            ),
          ),

          // 底部输入栏
          _buildReplyBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildPostContent(ColorScheme colorScheme) {
    final post = widget.post;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者信息
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: post.authorAvatar != null
                    ? NetworkImage(post.authorAvatar!)
                    : null,
                child: post.authorAvatar == null
                    ? (post.isAnonymous
                        ? const Icon(Icons.theater_comedy, size: 18)
                        : Text(
                            post.authorName.isNotEmpty
                                ? post.authorName[0]
                                : '?',
                            style: const TextStyle(fontSize: 18),
                          ))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          post.isAnonymous ? '匿名用户' : post.authorName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (post.isFromAI) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B6B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 标题
          Text(
            post.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),

          // 内容
          Text(
            post.content,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurface.withOpacity(0.8),
              height: 1.6,
            ),
          ),

          // 标签
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: post.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFFF6B6B),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),

          // 点赞数
          Row(
            children: [
              Icon(
                post.likes.contains('current_user')
                    ? Icons.favorite
                    : Icons.favorite_border,
                size: 20,
                color: post.likes.contains('current_user')
                    ? const Color(0xFFFF6B6B)
                    : colorScheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(width: 6),
              Text(
                '${post.likes.length} 人喜欢',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(ForumComment comment, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.surfaceContainerHighest,
            backgroundImage: comment.authorAvatar != null
                ? NetworkImage(comment.authorAvatar!)
                : null,
            child: comment.authorAvatar == null
                ? (comment.isAnonymous
                    ? const Icon(Icons.theater_comedy, size: 14)
                    : Text(
                        comment.authorName.isNotEmpty
                            ? comment.authorName[0]
                            : '?',
                        style: const TextStyle(fontSize: 14),
                      ))
                : null,
          ),
          const SizedBox(width: 10),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.isAnonymous ? '匿名用户' : comment.authorName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (comment.isFromAI) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B6B),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
                if (comment.replyToName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '回复 @${comment.replyToName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              focusNode: _replyFocus,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: '写评论...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSubmitting ? null : _submitReply,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.send,
                    color: Color(0xFFFF6B6B),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 发帖界面
class _ComposePostScreen extends StatefulWidget {
  final Uuid uuid;

  const _ComposePostScreen({required this.uuid});

  @override
  State<_ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<_ComposePostScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocus = FocusNode();
  bool _isAnonymous = false;
  bool _mentionAI = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入帖子标题')),
      );
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入帖子内容')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final forumService = ForumService(
        RepositoryProvider.of<LocalStorageRepository>(context),
      );

      final finalContent = _mentionAI ? '$content\n\n@AI 角色' : content;

      await forumService.createPost(
        authorId: 'current_user',
        authorName: '我',
        title: title,
        content: finalContent,
        isAnonymous: _isAnonymous,
        tags: _mentionAI ? ['AI互动'] : [],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('帖子发布成功')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖'),
        centerTitle: true,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSubmitting ? null : _submitPost,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '发布',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B6B),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 16),

          // 标题输入
          TextField(
            controller: _titleController,
            maxLength: 50,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: '标题',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.2),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              border: InputBorder.none,
              counterStyle: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ),
          Divider(color: colorScheme.outline.withOpacity(0.1)),

          // 内容输入
          TextField(
            controller: _contentController,
            focusNode: _contentFocus,
            maxLines: null,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 15, height: 1.6),
            decoration: InputDecoration(
              hintText: '分享你的想法...',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.2),
              ),
              border: InputBorder.none,
            ),
          ),
          Divider(color: colorScheme.outline.withOpacity(0.1)),
          const SizedBox(height: 16),

          // 匿名开关
          Row(
            children: [
              Icon(
                Icons.theater_comedy_outlined,
                size: 20,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 10),
              const Text('匿名发布', style: TextStyle(fontSize: 15)),
              const Spacer(),
              Switch(
                value: _isAnonymous,
                onChanged: (value) => setState(() => _isAnonymous = value),
                activeColor: const Color(0xFFFF6B6B),
              ),
            ],
          ),
          Divider(color: colorScheme.outline.withOpacity(0.1)),
          const SizedBox(height: 8),

          // @AI 提及开关
          Row(
            children: [
              const Icon(Icons.smart_toy, size: 18),
              const SizedBox(width: 10),
              const Text('@AI 角色', style: TextStyle(fontSize: 15)),
              const Spacer(),
              Switch(
                value: _mentionAI,
                onChanged: (value) => setState(() => _mentionAI = value),
                activeColor: const Color(0xFFFF6B6B),
              ),
            ],
          ),
          if (_mentionAI) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AI 角色可能会看到你的帖子并发表评论',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
