import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/moment.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_moment_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/safe_widget.dart';
import 'create_moment_screen.dart';
import 'moment_detail_screen.dart';
import 'x/x_moments_feed_screen.dart';

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  List<Moment> _moments = [];
  bool _isLoading = true;
  bool _isTriggeringAI = false;
  bool _disposed = false;
  String? _backgroundImagePath;

  @override
  void initState() {
    super.initState();
    _loadBackground();
    _loadMoments();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _loadBackground() {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    setState(() {
      _backgroundImagePath = storage.getMomentsBackgroundImage();
    });
    storage.setLastMomentsViewTime(DateTime.now());
  }

  Future<void> _loadMoments({bool triggerAI = true}) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final moments = await storage.getAllMoments();
      if (mounted) {
        setState(() {
          _moments = moments;
          _isLoading = false;
        });
      }
      if (triggerAI && !_isTriggeringAI) {
        _triggerAIMoments(storage);
      }
    } catch (e) {
      debugPrint('加载朋友圈失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _triggerAIMoments(LocalStorageRepository storage) async {
    if (_isTriggeringAI || _disposed) return;
    _isTriggeringAI = true;
    try {
      final aiMomentService = AIMomentService(storage);
      await aiMomentService.scheduleAIMomentsForAllCharacters();
      if (_disposed) { _isTriggeringAI = false; return; }

      // 前台兜底：AI 互动近期用户动态（WorkManager 可能被系统杀死）
      await _triggerUserMomentInteraction(aiMomentService, storage);
      if (_disposed) { _isTriggeringAI = false; return; }

      if (mounted) {
        final updatedMoments = await storage.getAllMoments();
        if (_disposed) { _isTriggeringAI = false; return; }
        setState(() {
          _moments = updatedMoments;
          _isTriggeringAI = false;
        });
      } else {
        _isTriggeringAI = false;
      }
    } catch (e) {
      debugPrint('触发 AI 朋友圈失败: $e');
      if (mounted && !_disposed) {
        setState(() => _isTriggeringAI = false);
      } else {
        _isTriggeringAI = false;
      }
    }
  }

  /// 前台触发 AI 互动用户动态 — WorkManager 兜底
  Future<void> _triggerUserMomentInteraction(
    AIMomentService aiMomentService,
    LocalStorageRepository storage,
  ) async {
    try {
      final characters =
          await aiMomentService.getCharactersWithMomentInteractionEnabled();
      if (characters.isEmpty) return;

      final allMoments = await storage.getAllMoments();
      // 只处理最近 24 小时内的用户动态
      final recentUserMoments = allMoments
          .where((m) =>
              !m.isFromAI &&
              DateTime.now().difference(m.createdAt).inHours < 24)
          .toList();

      if (recentUserMoments.isEmpty) return;

      for (final character in characters) {
        if (!character.isOnline) continue;
        final sessions =
            await storage.getChatSessionsByCharacterId(character.id);
        final intimacyLevel =
            sessions.isNotEmpty ? sessions.first.intimacyLevel : 50;

        for (final moment in recentUserMoments) {
          if (!aiMomentService.canAISeeMoment(moment, intimacyLevel)) continue;
          // 检查是否已经互动过（避免重复）
          final alreadyLiked =
              moment.likes.any((l) => l.userId == character.id);
          final alreadyCommented =
              moment.comments.any((c) => c.userId == character.id);
          if (alreadyLiked && alreadyCommented) continue;

          await aiMomentService.aiInteractWithUserMoment(
            moment: moment,
            character: character,
            intimacyLevel: intimacyLevel,
            forceComment: true,
          );
        }
      }
    } catch (e) {
      debugPrint('前台 AI 互动用户动态失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            forceElevated: false,
            title: Hero(
              tag: 'app_icon_moments',
              child: Text(
                '动态',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            centerTitle: true,
            actions: [
              // X 推特风格切换按钮
              IconButton(
                icon: Text(
                  '𝕏',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                tooltip: '切换到 X 风格',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const XMomentsFeedScreen(),
                    ),
                  ).then((_) => _loadMoments(triggerAI: false));
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                onPressed: () {},
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.settings_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
                offset: const Offset(0, 40),
                color: colorScheme.surface,
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'change',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library,
                            color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('更换背景',
                            style: TextStyle(
                                color: colorScheme.onSurface, fontSize: 14)),
                      ],
                    ),
                  ),
                  if (_backgroundImagePath != null)
                    PopupMenuItem(
                      value: 'reset',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restore,
                              color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('重置默认',
                              style: TextStyle(
                                  color: colorScheme.onSurface, fontSize: 14)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'publish',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('发布动态',
                            style: TextStyle(
                                color: colorScheme.onSurface, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'change') {
                    await _pickBackgroundImage();
                  } else if (value == 'reset') {
                    await _resetBackgroundImage();
                  } else if (value == 'publish') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateMomentScreen(),
                      ),
                    ).then((_) => _loadMoments()).catchError(
                        (e) => debugPrint('Moments reload failed: $e'));
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_backgroundImagePath != null) _buildBackgroundImage(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withOpacity(
                              _backgroundImagePath != null ? 0.3 : 0.5),
                          colorScheme.primary.withOpacity(
                              _backgroundImagePath != null ? 0.2 : 0.4),
                          colorScheme.primaryContainer.withOpacity(
                              _backgroundImagePath != null ? 0.15 : 0.3),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.8, 0.3),
                          radius: 1.2,
                          colors: [
                            colorScheme.brightness == Brightness.light
                                ? Colors.white.withOpacity(0.2)
                                : Colors.black.withOpacity(0.1),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Row(
                      children: [
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            String? userName;
                            if (state is AuthAuthenticated) {
                              userName = state.user.nickname;
                            }
                            return Text(
                              userName ?? '我',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: colorScheme.brightness ==
                                            Brightness.light
                                        ? Colors.black54
                                        : Colors.black87,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            String? avatarUrl;
                            if (state is AuthAuthenticated) {
                              avatarUrl = state.user.avatarUrl;
                            }
                            return Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.surfaceContainerHighest
                                      .withOpacity(0.9),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.shadow.withOpacity(
                                        colorScheme.brightness ==
                                                Brightness.light
                                            ? 0.1
                                            : 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: _buildAvatarImage(avatarUrl),
                                    )
                                  : Icon(
                                      Icons.person,
                                      color:
                                          colorScheme.primary.withOpacity(0.5),
                                    ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      },
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _moments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(120, 120),
                          painter: HeartPainter(),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '暂无动态',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '记录美好瞬间，和朋友分享每一刻',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _moments.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _moments.length) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height,
                        child: Container(),
                      );
                    }
                    final moment = _moments[index];
                    return _MomentCard(
                      moment: moment,
                      onTapDetail: () => _openDetail(moment),
                      onLike: () => _toggleLike(moment),
                      onComment: () => _showCommentDialog(moment),
                      onRefresh: _loadMoments,
                    );
                  },
                ),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeWidget(
        builder: (_) => _backgroundImagePath != null
            ? Stack(
                children: [
                  Positioned.fill(child: _buildBackgroundImage()),
                  content,
                ],
              )
            : content,
      ),
    );
  }

  Widget _buildAvatarImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.person, color: Colors.grey[400]),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.person, color: Colors.grey[400]),
    );
  }

  Widget _buildBackgroundImage() {
    final path = _backgroundImagePath!;
    if (path.startsWith('http')) {
      return Image.network(path,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox());
    }
    return Image.file(File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox());
  }

  Future<void> _pickBackgroundImage() async {
    if (!await PermissionService.requestStoragePermission()) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      final cachePath = await _copyToCache(picked.path);
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.setMomentsBackgroundImage(cachePath ?? picked.path);
      setState(() {
        _backgroundImagePath = cachePath ?? picked.path;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('背景已更换'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('选择背景图片失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<String?> _copyToCache(String sourcePath) async {
    try {
      final dir = Directory.systemTemp;
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final dest =
          '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(sourcePath).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('复制图片到缓存失败: $e');
      return null;
    }
  }

  Future<void> _resetBackgroundImage() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.clearMomentsBackgroundImage();
    setState(() {
      _backgroundImagePath = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已恢复默认背景'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _openDetail(Moment moment) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MomentDetailScreen(moment: moment)),
    )
        .then((_) => _loadMoments(triggerAI: false))
        .catchError((e) => debugPrint('Moment detail reload failed: $e'));
  }

  Future<void> _toggleLike(Moment moment) async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;

      final user = authState.user;
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      final isLiked = moment.likes.any((like) => like.userId == user.id);

      List<MomentLike> updatedLikes;
      if (isLiked) {
        updatedLikes =
            moment.likes.where((like) => like.userId != user.id).toList();
      } else {
        updatedLikes = [
          ...moment.likes,
          MomentLike(
            userId: user.id,
            userName: user.nickname,
            createdAt: DateTime.now(),
          ),
        ];
      }

      final updatedMoment = moment.copyWith(likes: updatedLikes);
      await storage.saveMoment(updatedMoment);
      await _loadMoments(triggerAI: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isLiked ? '已取消点赞' : '已点赞'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('点赞失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('点赞失败: $e')),
        );
      }
    }
  }

  void _showCommentDialog(Moment moment) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final user = authState.user;
    final textController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(
                  colorScheme.brightness == Brightness.light ? 0.05 : 0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                color: colorScheme.primary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '说点什么...',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colorScheme.primary, width: 1),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send, color: colorScheme.onPrimary),
                    onPressed: () async {
                      if (textController.text.trim().isEmpty) return;

                      try {
                        final storage =
                            RepositoryProvider.of<LocalStorageRepository>(
                                context);
                        final comment = MomentComment(
                          id: 'comment_${DateTime.now().millisecondsSinceEpoch}',
                          userId: user.id,
                          userName: user.nickname,
                          content: textController.text.trim(),
                          createdAt: DateTime.now(),
                        );

                        final updatedMoment = moment.copyWith(
                          comments: [...moment.comments, comment],
                        );

                        await storage.saveMoment(updatedMoment);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }

                        if (moment.isFromAI) {
                          final aiCharacter =
                              await storage.getAICharacter(moment.userId);
                          if (aiCharacter != null) {
                            final sessions = await storage
                                .getChatSessionsByCharacterId(aiCharacter.id);
                            final intimacyLevel = sessions.isNotEmpty
                                ? sessions.first.intimacyLevel
                                : 70;
                            final aiMomentService = AIMomentService(storage);
                            await aiMomentService.scheduleAICommentReply(
                              moment: updatedMoment,
                              userComment: comment,
                              character: aiCharacter,
                              intimacyLevel: intimacyLevel,
                            );
                          }
                        }

                        await _loadMoments(triggerAI: false);
                      } catch (e) {
                        debugPrint('评论失败: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('评论失败: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HeartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B9D).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = size.width / 100;

    path.moveTo(centerX, centerY + 10 * scale);

    path.cubicTo(
      centerX - 15 * scale,
      centerY - 5 * scale,
      centerX - 30 * scale,
      centerY - 5 * scale,
      centerX - 30 * scale,
      centerY + 15 * scale,
    );

    path.cubicTo(
      centerX - 30 * scale,
      centerY + 35 * scale,
      centerX - 10 * scale,
      centerY + 50 * scale,
      centerX,
      centerY + 65 * scale,
    );

    path.cubicTo(
      centerX + 10 * scale,
      centerY + 50 * scale,
      centerX + 30 * scale,
      centerY + 35 * scale,
      centerX + 30 * scale,
      centerY + 15 * scale,
    );

    path.cubicTo(
      centerX + 30 * scale,
      centerY - 5 * scale,
      centerX + 15 * scale,
      centerY - 5 * scale,
      centerX,
      centerY + 10 * scale,
    );

    path.close();

    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..color = const Color(0xFFFF6B9D).withOpacity(0.08)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MomentCard extends StatelessWidget {
  final Moment moment;
  final VoidCallback onTapDetail;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRefresh;

  const _MomentCard({
    required this.moment,
    required this.onTapDetail,
    required this.onLike,
    required this.onComment,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTapDetail,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(context, colorScheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moment.userName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    moment.content,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (moment.images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildImageGrid(context, moment.images),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _formatTime(moment.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      _buildActionButton(context, colorScheme),
                    ],
                  ),
                  if (moment.likes.isNotEmpty ||
                      moment.comments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildLikesAndComments(colorScheme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext ctx, ColorScheme colorScheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: (moment.userAvatar?.isNotEmpty) == true
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child:
                    _buildSafeImage(ctx, moment.userAvatar ?? '', BoxFit.cover),
              )
            : Center(
                child: Text(
                  moment.userName.isNotEmpty
                      ? moment.userName.substring(0, 1)
                      : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, ColorScheme colorScheme) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState is AuthAuthenticated ? authState.user : null;
        final isLiked =
            user != null && moment.likes.any((like) => like.userId == user.id);
        final canDelete = user != null;

        final items = <PopupMenuEntry<String>>[
          PopupMenuItem(
            value: 'like',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isLiked ? '取消' : '赞',
                  style: TextStyle(
                    color:
                        isLiked ? colorScheme.primary : colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'comment',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.comment_outlined,
                    color: colorScheme.onSurfaceVariant, size: 18),
                const SizedBox(width: 8),
                Text('评论',
                    style:
                        TextStyle(color: colorScheme.onSurface, fontSize: 14)),
              ],
            ),
          ),
          if (canDelete)
            PopupMenuItem(
              value: 'delete',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline,
                      color: colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('删除',
                      style:
                          TextStyle(color: colorScheme.primary, fontSize: 14)),
                ],
              ),
            ),
        ];

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: PopupMenuButton<String>(
            offset: const Offset(0, -80),
            color: colorScheme.surface,
            elevation: 8,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => items,
            onSelected: (value) {
              if (value == 'like') {
                onLike();
              } else if (value == 'comment') {
                onComment();
              } else if (value == 'delete') {
                _showDeleteConfirmDialog(context);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Icon(
                Icons.more_horiz,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '删除动态',
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          moment.isFromAI
              ? '确定要删除 ${moment.userName} 的这条动态吗？'
              : '确定要删除这条动态吗？此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteMoment(context);
            },
            style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMoment(BuildContext context) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.deleteMoment(moment.id);
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已删除'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('删除失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Widget _buildLikesAndComments(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerLowest,
            colorScheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (moment.likes.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.favorite,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    moment.likes.map((l) => l.userName).join('，'),
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (moment.likes.isNotEmpty && moment.comments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(
              height: 1,
              color: colorScheme.primary.withOpacity(0.1),
            ),
            const SizedBox(height: 6),
          ],
          if (moment.comments.isNotEmpty) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: moment.comments.map((comment) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: comment.userName,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (comment.replyToUserName != null) ...[
                          TextSpan(
                            text: ' 回复 ',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextSpan(
                            text: comment.replyToUserName,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const TextSpan(text: '：'),
                        TextSpan(text: comment.content),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, List<String> images) {
    final maxWidth = MediaQuery.of(context).size.width - 16 * 2 - 44 - 12;

    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxWidth * 0.65,
            maxHeight: 220,
          ),
          child: _buildSafeImage(context, images[0], BoxFit.cover),
        ),
      );
    }

    final crossAxisCount = (images.length == 2 || images.length == 4) ? 2 : 3;
    final spacing = 4.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final itemSize = (maxWidth - totalSpacing) / crossAxisCount;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: images.map((img) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: itemSize,
            height: itemSize,
            child: _buildSafeImage(context, img, BoxFit.cover),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSafeImage(BuildContext ctx, String path, BoxFit fit) {
    final colorScheme = Theme.of(ctx).colorScheme;
    final placeholder = Container(
      color: colorScheme.surfaceContainerLowest,
      child:
          Center(child: Icon(Icons.broken_image, color: colorScheme.outline)),
    );
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final total = loadingProgress.expectedTotalBytes ?? 1;
          final progress = loadingProgress.cumulativeBytesLoaded / total;
          return Container(
            color: colorScheme.surfaceContainerLowest,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    color: colorScheme.primary),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(time);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '昨天 ${DateFormat('HH:mm').format(time)}';
    } else if (now.difference(time).inDays < 7) {
      return DateFormat('E HH:mm', 'zh_CN').format(time);
    } else {
      return DateFormat('MM月dd日').format(time);
    }
  }
}
