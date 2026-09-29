import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/circular_avatar.dart';
import '../../../widgets/moments/identity_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// X 推特风格发帖页面（新帖/回复/引用转发）
class XComposeMomentScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;
  final Moment? replyToMoment;
  final Moment? quoteMoment;

  const XComposeMomentScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.replyToMoment,
    this.quoteMoment,
  });

  @override
  State<XComposeMomentScreen> createState() => _XComposeMomentScreenState();
}

class _XComposeMomentScreenState extends State<XComposeMomentScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _images = [];
  int _charCount = 0;
  static const int _maxChars = 280;
  late PostIdentity _identity;

  // 自定义计数
  final _replyCountCtrl = TextEditingController(text: '0');
  final _retweetCountCtrl = TextEditingController(text: '0');
  final _likeCountCtrl = TextEditingController(text: '0');
  final _viewCountCtrl = TextEditingController(text: '0');
  bool _showCountEditor = false;

  bool get isReply => widget.replyToMoment != null;
  bool get isQuote => widget.quoteMoment != null;

  @override
  void initState() {
    super.initState();
    _identity = PostIdentity(
      name: widget.userName,
      handle: widget.userName,
      avatarPath: widget.userAvatar,
    );
    _controller.addListener(() {
      setState(() => _charCount = _controller.text.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _replyCountCtrl.dispose();
    _retweetCountCtrl.dispose();
    _likeCountCtrl.dispose();
    _viewCountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              color: MomentsTheme.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        title: Text(
          isReply
              ? '回复'
              : isQuote
                  ? '引用'
                  : '发布动态',
          style: TextStyle(
            color: MomentsTheme.textPrimary(context),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: MomentsTheme.primary(context),
                disabledBackgroundColor:
                    MomentsTheme.primary(context).withOpacity(0.45),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                minimumSize: const Size(70, 34),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: Text(
                isReply ? '回复' : '发布',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: MomentsTheme.divider(context)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 身份选择器
                  IdentityPicker(
                    currentIdentity: _identity,
                    onIdentityChanged: (id) {
                      setState(() => _identity = id);
                    },
                  ),
                  const SizedBox(height: 12),
                  // 回复预览
                  if (isReply) ...[
                    _replyPreview(),
                    const SizedBox(height: 12),
                  ],
                  // 输入区
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircularAvatar(
                        avatarPath: _identity.avatarPath,
                        name: _identity.name,
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          minLines: 4,
                          maxLength: _maxChars,
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.35,
                            letterSpacing: -0.2,
                            color: MomentsTheme.textPrimary(context),
                          ),
                          decoration: InputDecoration(
                            hintText: _hintText,
                            hintStyle: TextStyle(
                              color: MomentsTheme.textSecondary(context),
                              fontSize: 20,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 引用转发预览
                  if (isQuote) ...[
                    const SizedBox(height: 12),
                    _quotePreview(),
                  ],
                  // 图片预览
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _imagePreview(),
                  ],
                  // 自定义计数编辑器
                  const SizedBox(height: 12),
                  _countEditor(),
                ],
              ),
            ),
          ),
          // 底部工具栏
          _bottomBar(),
        ],
      ),
    );
  }

  String get _hintText {
    if (isReply) return '发布你的回复';
    if (isQuote) return '添加评论';
    return '有什么新鲜事？';
  }

  bool get _canSubmit {
    final hasContent = _controller.text.trim().isNotEmpty || _images.isNotEmpty;
    final withinLimit = _charCount <= _maxChars;
    return hasContent && withinLimit;
  }

  Widget _replyPreview() {
    final m = widget.replyToMoment!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: MomentsTheme.divider(context),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircularAvatar(
                  avatarPath: m.userAvatar, name: m.userName, radius: 12),
              const SizedBox(width: 8),
              Text(m.userName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: MomentsTheme.textPrimary(context),
                  )),
              const SizedBox(width: 4),
              Text(m.userHandle ?? '@${m.userName}',
                  style: TextStyle(
                    fontSize: 14,
                    color: MomentsTheme.textSecondary(context),
                  )),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, color: MomentsTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _quotePreview() {
    final m = widget.quoteMoment!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: MomentsTheme.divider(context), width: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircularAvatar(
                  avatarPath: m.userAvatar, name: m.userName, radius: 10),
              const SizedBox(width: 6),
              Text(m.userName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: MomentsTheme.textPrimary(context),
                  )),
              const SizedBox(width: 4),
              Text(m.userHandle ?? '@${m.userName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: MomentsTheme.textSecondary(context),
                  )),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, color: MomentsTheme.textPrimary(context)),
          ),
        ],
      ),
    );
  }

  Widget _imagePreview() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_images[i]),
                  width: 100, height: 100, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 100, height: 100,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, size: 32),
                  )),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _images.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countEditor() {
    return GestureDetector(
      onTap: () => setState(() => _showCountEditor = !_showCountEditor),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MomentsTheme.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: MomentsTheme.divider(context),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune,
                    size: 18, color: MomentsTheme.primary(context)),
                const SizedBox(width: 8),
                Text(
                  '自定义互动数据',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: MomentsTheme.textPrimary(context),
                  ),
                ),
                const Spacer(),
                Icon(
                  _showCountEditor
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: MomentsTheme.textSecondary(context),
                ),
              ],
            ),
            if (_showCountEditor) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _countField(
                      '回复', _replyCountCtrl, MomentsTheme.replyColor(context)),
                  const SizedBox(width: 8),
                  _countField('转发', _retweetCountCtrl,
                      MomentsTheme.retweetColor(context)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _countField('点赞', _likeCountCtrl, MomentsTheme.like(context)),
                  const SizedBox(width: 8),
                  _countField('浏览', _viewCountCtrl,
                      MomentsTheme.textSecondary(context)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _countField(String label, TextEditingController ctrl, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: MomentsTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MomentsTheme.divider(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MomentsTheme.primary(context)),
              ),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final progress = (_charCount / _maxChars).clamp(0.0, 1.0);
    final progressColor = _charCount > _maxChars
        ? MomentsTheme.like(context)
        : _charCount > _maxChars * 0.85
            ? const Color(0xFFFFD400)
            : MomentsTheme.primary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: MomentsTheme.divider(context), width: 0.5),
        ),
        color: MomentsTheme.cardBackground(context),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _toolbarButton(Icons.image_outlined, _pickImage),
            _toolbarButton(Icons.camera_alt_outlined, _pickCamera),
            _toolbarButton(Icons.gif_box_outlined, () {}),
            _toolbarButton(Icons.poll_outlined, () {}),
            _toolbarButton(Icons.alternate_email, _insertMention),
            _toolbarButton(Icons.tag, _insertHashtag),
            const Spacer(),
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    backgroundColor: MomentsTheme.divider(context),
                    color: progressColor,
                  ),
                  if (_charCount > _maxChars * 0.85)
                    Text(
                      '${_maxChars - _charCount}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: progressColor,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      splashRadius: 20,
      icon: Icon(icon, color: MomentsTheme.primary(context), size: 22),
      onPressed: onTap,
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null && _images.length < 9) {
      setState(() => _images.add(picked.path));
    }
  }

  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null && _images.length < 9) {
      setState(() => _images.add(picked.path));
    }
  }

  void _insertMention() {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '@');
    _controller.text = newText;
    _controller.selection =
        TextSelection.collapsed(offset: selection.start + 1);
    _focusNode.requestFocus();
  }

  void _insertHashtag() {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '#');
    _controller.text = newText;
    _controller.selection =
        TextSelection.collapsed(offset: selection.start + 1);
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final storage = context.read<LocalStorageRepository>();
    final content = _controller.text.trim();

    // 提取话题标签
    final tags = <String>[];
    final hashtagRegex = RegExp(r'#(\w+)');
    for (final match in hashtagRegex.allMatches(content)) {
      tags.add(match.group(1)!);
    }

    // 提取 @提及
    final mentions = <String>[];
    final mentionRegex = RegExp(r'@(\w+)');
    for (final match in mentionRegex.allMatches(content)) {
      mentions.add(match.group(1)!);
    }

    final moment = Moment(
      id: const Uuid().v4(),
      userId: widget.userId,
      userName: _identity.name,
      userAvatar: _identity.avatarPath,
      content: content,
      images: _images,
      type: _images.isEmpty
          ? MomentType.text
          : _images.length == 1
              ? MomentType.image
              : MomentType.mixed,
      createdAt: DateTime.now(),
      source: MomentSource.x,
      parentKey: widget.replyToMoment?.id,
      quoteKey: widget.quoteMoment?.id,
      tags: tags,
      userHandle: '@${_identity.handle}',
      userGender: _identity.gender,
      userVerified: _identity.isVerified,
      replyCount: int.tryParse(_replyCountCtrl.text) ?? 0,
      retweetCount: int.tryParse(_retweetCountCtrl.text) ?? 0,
      customLikeCount: int.tryParse(_likeCountCtrl.text) ?? 0,
      viewCount: int.tryParse(_viewCountCtrl.text) ?? 0,
    );

    await storage.saveMoment(moment);

    // 更新话题趋势
    if (tags.isNotEmpty) {
      await storage.updateTrendingTags(tags);
    }

    // 递增父帖回复计数
    if (isReply) {
      await storage.incrementReplyCount(widget.replyToMoment!.id);
    }

    if (mounted) Navigator.pop(context);
  }
}
