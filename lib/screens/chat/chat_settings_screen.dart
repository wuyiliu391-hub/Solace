import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/tts_config.dart';
import '../../models/ai_character.dart';
import '../../models/ai_wallet.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';

import '../../services/memory_engine.dart';
import '../../services/voice_clone_service.dart';
import '../../services/tts_service.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/permission_service.dart';
import '../../widgets/ai_wallet_card.dart';
import 'interaction_settings_screen.dart';

class ChatSettingsScreen extends StatefulWidget {
  final ChatSession session;
  final AICharacter? character;

  const ChatSettingsScreen({
    super.key,
    required this.session,
    this.character,
  });

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late bool _isMuted;
  late bool _isPinned;
  String? _backgroundImage;

  AICharacter? _character;

  late ChatSession _localSession;
  bool _hasChanges = false;
  late bool _aiIsOnline;
  late String? _aiCurrentStatus;
  TextEditingController? _statusController;
  late bool _isBlockedByUser;
  AIWallet? _aiWallet;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _localSession = widget.session;
    _isMuted = _localSession.isMuted;
    _isPinned = _localSession.isPinned;
    _backgroundImage = _localSession.backgroundImage;
    _isBlockedByUser =
        _localSession.isBlocked && _localSession.blockedBy == BlockedBy.user;
    _loadAIStatus();
    _loadAIWallet();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _statusController?.dispose();
    super.dispose();
  }

  /// 当输入框获得焦点时，自动滚动到可见区域
  void _onFocusChange() {
    if (!_scrollController.hasClients) return;
    // 延迟一帧等待键盘动画完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadAIStatus() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final character =
          await storage.getAICharacter(widget.session.aiCharacterId);
      if (character != null && mounted) {
        setState(() {
          _character = character;
          _aiIsOnline = character.isOnline;
          _aiCurrentStatus = character.currentStatus;
          _statusController =
              TextEditingController(text: character.currentStatus ?? '');
        });
      }
    } catch (e) {
      debugPrint('加载AI状态失败: $e');
    }
  }

  Future<void> _loadAIWallet() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final wallet =
          await storage.getOrCreateAIWallet(widget.session.aiCharacterId);
      if (mounted) {
        setState(() {
          _aiWallet = wallet;
        });
      }
    } catch (e) {
      debugPrint('加载AI钱包失败: $e');
    }
  }

  Future<void> _updateSession() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    debugPrint(
        '保存会话设置 - backgroundImage: $_backgroundImage, lastMessage: ${_localSession.lastMessage}');
    final updatedSession = _localSession.copyWith(
      isMuted: _isMuted,
      isPinned: _isPinned,
      backgroundImage: _backgroundImage,
      updatedAt: DateTime.now(),
    );
    _localSession = updatedSession;
    await storage.saveChatSession(updatedSession);
    _hasChanges = true;
    debugPrint('会话设置保存完成 - lastMessage: ${updatedSession.lastMessage}');
  }

  Future<void> _autoSave() async {
    if (mounted) {
      try {
        await _updateSession();
      } catch (e) {
        debugPrint('自动保存失败: $e');
      }
    }
  }

  Future<void> _pickBackgroundImage() async {
    try {
      bool hasPermission = await PermissionService.hasStoragePermission();
      if (!hasPermission) {
        hasPermission = await PermissionService.requestStoragePermission();
      }

      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要存储权限才能选择图片')),
          );
        }
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // 复制到持久化目录，避免临时文件被系统清理导致闪退
        final dir = await getApplicationDocumentsDirectory();
        final bgDir = Directory('${dir.path}/chat_backgrounds');
        if (!await bgDir.exists()) await bgDir.create(recursive: true);
        final ext = pickedFile.path.contains('.')
            ? pickedFile.path.split('.').last
            : 'jpg';
        final destPath = '${bgDir.path}/${widget.session.id}.$ext';
        await File(pickedFile.path).copy(destPath);

        setState(() {
          _backgroundImage = destPath;
        });
        await _autoSave();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  void _showClearChatConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text(
          '确定要清空当前聊天记录吗？这只会删除聊天消息，不会重置 AI 记忆、情感状态或长期记忆。此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearChatMessages();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _showClearMemoryConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置 AI 记忆'),
        content: const Text(
          '确定要重置 AI 对你的记忆和情感状态吗？聊天记录不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearMemories();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChatMessages() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.clearChatMessages(_localSession.id);

      await storage.updateChatSessionLastMessage(
        _localSession.id,
        null,
        null,
      );

      final updatedSession = _localSession.copyWith(
        lastMessage: null,
        lastMessageTime: null,
        unreadCount: 0,
        updatedAt: DateTime.now(),
      );
      _localSession = updatedSession;
      _hasChanges = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天记录已清空')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e')),
        );
      }
    }
  }

  Future<void> _clearMemories() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.clearMemories(
        _localSession.aiCharacterId,
        _localSession.userId,
      );
      await storage.clearEmotionState(
        _localSession.aiCharacterId,
        _localSession.userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 记忆已重置')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重置失败: $e')),
        );
      }
    }
  }

  void _showForbiddenPhrasesManager() {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final phrases = storage.getForbiddenPhrases();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '禁止短语管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI 回复中包含以下词语时会被自动过滤',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  // 添加新短语
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: '输入要禁止的短语',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final text = controller.text.trim();
                          if (text.length >= 2 && text.length <= 30) {
                            await storage.addForbiddenPhrase(text);
                            controller.clear();
                            setSheetState(() {});
                          }
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 短语列表
                  if (phrases.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '暂无禁止短语\n你可以告诉 AI "不许说XXX" 来添加',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: phrases.length,
                        itemBuilder: (_, index) {
                          final phrase = phrases[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.block,
                                size: 20, color: Colors.redAccent),
                            title: Text(phrase),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                await storage.removeForbiddenPhrase(phrase);
                                setSheetState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveAIStatus() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      final statusText = _statusController?.text.trim() ?? '';

      final updatedSession = _localSession.copyWith(
        aiIsOnline: _aiIsOnline,
        aiCurrentStatus: statusText.isNotEmpty ? statusText : null,
        updatedAt: DateTime.now(),
      );
      _localSession = updatedSession;
      await storage.saveChatSession(updatedSession);
      _hasChanges = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI 状态已更新'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存状态失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showReportDialog() {
    final reasons = [
      '发送垃圾信息',
      '骚扰行为',
      '不当内容',
      '虚假身份',
      '其他问题',
    ];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('举报'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '举报 ${widget.session.aiCharacterName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('请选择举报原因：'),
              const SizedBox(height: 8),
              ...reasons.map((reason) => RadioListTile<String>(
                    title: Text(reason),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setState(() {
                        selectedReason = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _submitReport(selectedReason!);
                    },
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
  }

  void _submitReport(String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('举报已提交，我们会尽快处理')),
    );
  }

  void _showEditAliasDialog({
    required String title,
    required String hint,
    required String? currentValue,
    required Future<void> Function(String) onSave,
    int maxLines = 1,
  }) {
    final controller = TextEditingController(text: currentValue ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          if (currentValue != null && currentValue.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onSave('');
              },
              child: Text('清除', style: TextStyle(color: Colors.red[400])),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onSave(controller.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToCharacterProfile() async {
    var currentCharacter = _character ?? widget.character;
    if (currentCharacter == null) {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      currentCharacter =
          await storage.getAICharacter(_localSession.aiCharacterId);
      if (currentCharacter != null && mounted) {
        setState(() => _character = currentCharacter);
      }
    }

    if (currentCharacter == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法加载角色资料')),
      );
      return;
    }

    final AICharacter profileCharacter = currentCharacter;

    final result = await showModalBottomSheet<AICharacter>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CharacterProfileSheet(
          character: profileCharacter,
          scrollController: scrollController,
          onCharacterUpdated: (updated) {
            _applyCharacterUpdate(updated);
          },
        ),
      ),
    );

    if (result != null && mounted) {
      // 更新会话中的头像信息
      await _applyCharacterUpdate(result);
    }
  }

  Future<void> _applyCharacterUpdate(AICharacter updated) async {
    if (!mounted) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final updatedSession = _localSession.copyWith(
      aiCharacterAvatar: updated.avatarUrl,
      aiCharacterName: updated.name,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _character = updated;
      _localSession = updatedSession;
      _aiIsOnline = updated.isOnline;
      _aiCurrentStatus = updated.currentStatus;
      _statusController?.text = updated.currentStatus ?? '';
      _hasChanges = true;
    });

    await storage.saveChatSession(updatedSession);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          title: const Text('聊天设置'),
          centerTitle: true,
          elevation: 0,
        ),
        body: ListView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 600),
          children: [
            _buildProfileSection(context),
            const Divider(height: 32),
            _buildAIStatusSection(context),
            const Divider(height: 32),
            _buildWalletSection(context),
            const Divider(height: 32),
            _buildSettingsSection(context),
            const Divider(height: 32),
            _buildBackgroundSection(context),
            const Divider(height: 32),
            _buildDangerZone(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.purple.shade300, Colors.purple.shade500],
              ),
            ),
            child: _localSession.aiCharacterAvatar != null
                ? ClipOval(
                    child: _buildAvatarImage(_localSession.aiCharacterAvatar!),
                  )
                : Center(
                    child: Text(
                      _localSession.aiCharacterName.isNotEmpty
                          ? _localSession.aiCharacterName[0]
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localSession.aiCharacterName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '亲密度 Lv.${_localSession.intimacyLevel}',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(String avatarUrl) {
    if (avatarUrl.startsWith('/') ||
        avatarUrl.startsWith('C:') ||
        avatarUrl.startsWith('\\')) {
      final file = File(avatarUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.purple.shade300,
          ),
        );
      }
    }
    return Image.network(
      avatarUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.purple.shade300,
      ),
    );
  }

  Widget _buildAIStatusSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayStatus = _aiIsOnline
        ? (_aiCurrentStatus != null && _aiCurrentStatus!.isNotEmpty
            ? '在线 · $_aiCurrentStatus'
            : '在线')
        : (_aiCurrentStatus != null && _aiCurrentStatus!.isNotEmpty
            ? '离线 · $_aiCurrentStatus'
            : '离线');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'AI 状态设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _aiIsOnline ? const Color(0xFF4CAF50) : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '当前：$displayStatus',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SettingsToggle(
          icon: Icons.circle_outlined,
          title: '在线状态',
          subtitle: _aiIsOnline ? '当前在线' : '当前离线',
          value: _aiIsOnline,
          onChanged: (value) {
            setState(() {
              _aiIsOnline = value;
            });
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自定义状态文字',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _statusController ?? TextEditingController(),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: '例如：正在听音乐、休息中...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                  filled: true,
                  fillColor:
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _saveAIStatus,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存状态'),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildWalletSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'AI 钱包',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_aiWallet != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AIWalletCard(
              wallet: _aiWallet!,
              character: widget.character,
              onTap: () => _showTransferToAIDialog(),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    '正在加载钱包信息...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _aiWallet != null ? _showTransferToAIDialog : null,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('转账给TA'),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _showTransferToAIDialog() {
    final amountController = TextEditingController();
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转账给AI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当前余额：${_localSession.intimacyLevel > 0 ? '加载中...' : '0'} 金币',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '转账金额',
                hintText: '请输入金额',
                border: OutlineInputBorder(),
                suffixText: '金币',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: '留言（可选）',
                hintText: '说点什么...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final amount = int.tryParse(amountController.text) ?? 0;
              if (amount > 0) {
                Navigator.pop(context);
                _executeTransfer(amount, messageController.text);
              }
            },
            child: const Text('转账'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeTransfer(int amount, String message) async {
    if (!mounted) return;

    // 返回转账数据给聊天界面，由聊天界面处理转账逻辑
    Navigator.pop(context, {
      'pendingTransfer': {
        'amount': amount,
        'message': message,
      },
    });
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '聊天设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsItem(
          icon: Icons.person_outline,
          title: '查看TA的资料',
          onTap: _navigateToCharacterProfile,
        ),
        _SettingsItem(
          icon: Icons.settings_applications_outlined,
          title: '互动设置',
          subtitle: '问候、主动消息、回复行为等',
          onTap: () {
            if (_character != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InteractionSettingsScreen(
                    character: _character!,
                    sessionId: _localSession.id,
                  ),
                ),
              );
            }
          },
        ),
        if (_character != null) ...[
          _SettingsItem(
            icon: Icons.badge_outlined,
            title: '角色原名',
            subtitle: _character!.name,
            onTap: () => _showEditAliasDialog(
              title: '修改角色原名',
              hint: '输入新的角色名',
              currentValue: _character!.name,
              onSave: (value) async {
                final newName = value.trim();
                if (newName.isEmpty) return;
                final updated = _character!.copyWith(
                  name: newName,
                  updatedAt: DateTime.now(),
                );
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.saveAICharacter(updated);
                await _applyCharacterUpdate(updated);
              },
            ),
          ),
          _SettingsItem(
            icon: Icons.edit_note,
            title: '我的备注',
            subtitle: _character!.userAlias ?? '点击设置你对TA的称呼',
            onTap: () => _showEditAliasDialog(
              title: '我的备注',
              hint: '你对TA的称呼（如：老婆、宝宝）',
              currentValue: _character!.userAlias,
              onSave: (value) async {
                final updated = _character!.copyWith(
                  userAlias: value.trim().isEmpty ? null : value.trim(),
                  clearUserAlias: value.trim().isEmpty,
                  updatedAt: DateTime.now(),
                );
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.saveAICharacter(updated);
                await _applyCharacterUpdate(updated);
              },
            ),
          ),
          _SettingsItem(
            icon: Icons.record_voice_over_outlined,
            title: 'TA对我的称呼',
            subtitle: _character!.userNickname ?? '点击设置TA对你的称呼',
            onTap: () => _showEditAliasDialog(
              title: 'TA对我的称呼',
              hint: 'TA怎么叫你（如：小宝贝、亲爱的）',
              currentValue: _character!.userNickname,
              onSave: (value) async {
                final updated = _character!.copyWith(
                  userNickname: value.trim().isEmpty ? null : value.trim(),
                  clearUserNickname: value.trim().isEmpty,
                  updatedAt: DateTime.now(),
                );
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.saveAICharacter(updated);
                await _applyCharacterUpdate(updated);
              },
            ),
          ),
          _SettingsItem(
            icon: Icons.person_outline,
            title: '你的人设',
            subtitle: _character!.userPersona ?? '让TA认识真实的你',
            onTap: () => _showEditAliasDialog(
              title: '你的人设',
              hint: '你在TA眼中是什么样的？例如：一个喜欢画画的大学生',
              currentValue: _character!.userPersona,
              maxLines: 3,
              onSave: (value) async {
                final updated = _character!.copyWith(
                  userPersona: value.trim().isEmpty ? null : value.trim(),
                  clearUserPersona: value.trim().isEmpty,
                  updatedAt: DateTime.now(),
                );
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.saveAICharacter(updated);
                await _applyCharacterUpdate(updated);
              },
            ),
          ),
        ],
        
        _SettingsToggle(
          icon: Icons.notifications_off_outlined,
          title: '消息免打扰',
          subtitle: '开启后将不会收到消息提醒',
          value: _isMuted,
          onChanged: (value) async {
            setState(() {
              _isMuted = value;
            });
            await _autoSave();
          },
        ),
        _SettingsToggle(
          icon: Icons.push_pin_outlined,
          title: '置顶聊天',
          value: _isPinned,
          onChanged: (value) async {
            setState(() {
              _isPinned = value;
            });
            await _autoSave();
          },
        ),
        _SettingsToggle(
          icon: Icons.block,
          title: '拉黑',
          subtitle: _isBlockedByUser ? '已拉黑，对方无法收到你的消息' : '拉黑后对方无法收到你的消息',
          value: _isBlockedByUser,
          onChanged: (value) async {
            final storage =
                RepositoryProvider.of<LocalStorageRepository>(context);
            if (value) {
              await storage.blockSession(
                  _localSession.id, BlockedBy.user, 'user_initiated');
            } else {
              await storage.unblockSession(_localSession.id);
            }
            setState(() {
              _isBlockedByUser = value;
              _localSession = _localSession.copyWith(
                isBlocked: value,
                blockedBy: value ? BlockedBy.user : BlockedBy.none,
                blockedAt: value ? DateTime.now() : null,
                blockReason: value ? 'user_initiated' : null,
                clearBlock: !value,
              );
            });
            _hasChanges = true;
          },
        ),
      ],
    );
  }

  Widget _buildBackgroundSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '聊天背景',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              image: _backgroundImage != null && _backgroundImage!.isNotEmpty
                  ? DecorationImage(
                      image: _backgroundImage!.startsWith('/') &&
                              File(_backgroundImage!).existsSync()
                          ? FileImage(File(_backgroundImage!)) as ImageProvider
                          : NetworkImage(_backgroundImage!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _backgroundImage == null || _backgroundImage!.isEmpty
                ? Icon(Icons.image, color: Colors.grey[400])
                : null,
          ),
          title: const Text('设置聊天背景'),
          subtitle: Text(
            _backgroundImage != null ? '已设置自定义背景' : '使用默认背景',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickBackgroundImage,
        ),
        if (_backgroundImage != null && _backgroundImage!.isNotEmpty)
          ListTile(
            leading:
                Icon(Icons.restore, color: Theme.of(context).colorScheme.error),
            title: Text(
              '恢复默认背景',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              setState(() {
                _backgroundImage = '';
              });
              await _autoSave();
            },
          ),
      ],
    );
  }

  Widget _buildDangerZone(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '其他',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsItem(
          icon: Icons.delete_outline,
          title: '清空聊天记录',
          titleColor: Theme.of(context).colorScheme.error,
          onTap: _showClearChatConfirm,
        ),
        _SettingsItem(
          icon: Icons.block_outlined,
          title: '禁止短语管理',
          subtitle: '管理 AI 不允许说的词语',
          onTap: _showForbiddenPhrasesManager,
        ),
        _SettingsItem(
          icon: Icons.psychology_outlined,
          title: '重置 AI 记忆',
          titleColor: Theme.of(context).colorScheme.error,
          onTap: _showClearMemoryConfirm,
        ),
        _SettingsItem(
          icon: Icons.flag_outlined,
          title: '举报',
          onTap: _showReportDialog,
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: titleColor ?? Theme.of(context).colorScheme.primary),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            )
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

class _CharacterProfileSheet extends StatefulWidget {
  final AICharacter character;
  final ScrollController scrollController;
  final Function(AICharacter)? onCharacterUpdated;

  const _CharacterProfileSheet({
    required this.character,
    required this.scrollController,
    this.onCharacterUpdated,
  });

  @override
  State<_CharacterProfileSheet> createState() => _CharacterProfileSheetState();
}

class _CharacterProfileSheetState extends State<_CharacterProfileSheet> {
  late TextEditingController _personalityController;
  late TextEditingController _backgroundStoryController;
  late TextEditingController _coreDesireController;
  late TextEditingController _moralBoundaryController;
  late TextEditingController _worldSettingController;
  late TextEditingController _languageStyleController;
  late TextEditingController _tabooTopicsController;
  late TextEditingController _characterTagController;
  late TextEditingController _hobbiesController;
  late TextEditingController _routineController;
  late TextEditingController _quirksController;

  late AICharacter _character;
  bool _isEditing = false;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _evolutionEnabled = true;
  bool _qualitativeEvolutionEnabled = false;
  String? _newAvatarPath;

  int? _editingSection;
  final _editingScrollController = ScrollController();

  void _enterEditMode(int section) {
    if (_editingSection != section) {
      setState(() => _editingSection = section);
    }
  }

  void _exitEditMode() {
    if (_editingSection != null) {
      FocusScope.of(context).unfocus();
      setState(() => _editingSection = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _character = widget.character;
    _initControllers();
    _checkTtsApiKey();
  }

  Future<void> _checkTtsApiKey() async {
    final hasKey = await TTSConfig.hasApiKey();
    if (mounted) setState(() => _hasTtsApiKey = hasKey);
  }

  void _initControllers() {
    _personalityController =
        TextEditingController(text: _character.personality);
    _backgroundStoryController =
        TextEditingController(text: _character.backgroundStory ?? '');
    _coreDesireController = TextEditingController(text: _character.coreDesire);
    _moralBoundaryController =
        TextEditingController(text: _character.moralBoundary);
    _worldSettingController =
        TextEditingController(text: _character.worldSetting ?? '');
    _languageStyleController =
        TextEditingController(text: _character.languageStyle ?? '');
    _tabooTopicsController =
        TextEditingController(text: _character.tabooTopics ?? '');
    _characterTagController =
        TextEditingController(text: _character.characterTag ?? '');
    // 结构化特征：从 JSON 解析到文本控制器
    Map<String, dynamic> _traits = {};
    if (_character.structuredTraits != null &&
        _character.structuredTraits!.isNotEmpty) {
      try {
        _traits =
            jsonDecode(_character.structuredTraits!) as Map<String, dynamic>;
      } catch (_) {}
    }
    _hobbiesController = TextEditingController(
        text: (_traits['hobbies'] as List?)?.cast<String>().join('、') ?? '');
    final routineStr = StringBuffer();
    (_traits['routine'] as Map?)?.forEach((k, v) {
      if (routineStr.isNotEmpty) routineStr.write('\n');
      routineStr.write('$k: $v');
    });
    _routineController = TextEditingController(text: routineStr.toString());
    _quirksController = TextEditingController(
        text: (_traits['quirks'] as List?)?.cast<String>().join('；') ?? '');
    _evolutionEnabled = _character.evolutionEnabled;
    _qualitativeEvolutionEnabled = _character.qualitativeEvolutionEnabled;
  }

  @override
  void dispose() {
    _previewCompleteSub?.cancel();
    _previewPlayer?.dispose();
    _personalityController.dispose();
    _backgroundStoryController.dispose();
    _coreDesireController.dispose();
    _moralBoundaryController.dispose();
    _worldSettingController.dispose();
    _languageStyleController.dispose();
    _tabooTopicsController.dispose();
    _characterTagController.dispose();
    _hobbiesController.dispose();
    _routineController.dispose();
    _quirksController.dispose();
    _editingScrollController.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  /// 输入框获焦时滚动到底部
  void _onFocusChange() {
    if (!widget.scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _pickAvatar() async {
    try {
      bool hasPermission = await PermissionService.hasStoragePermission();
      if (!hasPermission) {
        hasPermission = await PermissionService.requestStoragePermission();
      }

      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要存储权限才能选择图片')),
          );
        }
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final persistentPath = await _copyToPersistentPath(pickedFile.path);
        setState(() {
          _newAvatarPath = persistentPath;
          _hasChanges = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<String> _copyToPersistentPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/ai_avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final destPath = '${avatarDir.path}/${_character.id}.$ext';
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      return sourcePath;
    }
  }

  /// 构建结构化特征 JSON 字符串（兴趣、作息、口癖、时区）
  String? _buildStructuredTraitsJson() {
    final hobbiesRaw = _hobbiesController.text.trim();
    final routineRaw = _routineController.text.trim();
    final quirksRaw = _quirksController.text.trim();

    final hobbies = hobbiesRaw
        .split(RegExp(r'[、,，\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final routine = <String, String>{};
    for (final line in routineRaw.split('\n')) {
      final parts = line.split(RegExp(r'[:：]'));
      if (parts.length >= 2 && parts[0].trim().isNotEmpty) {
        routine[parts[0].trim()] = parts.sublist(1).join(':').trim();
      }
    }

    final quirks = quirksRaw
        .split(RegExp(r'[；;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (hobbies.isEmpty && routine.isEmpty && quirks.isEmpty) {
      return null;
    }

    final traits = <String, dynamic>{
      'hobbies': hobbies,
      'routine': routine,
      'quirks': quirks,
      'timezone': _detectUserTimezone(),
    };
    return jsonEncode(traits);
  }

  /// 检测用户当前时区（简体中文标签）
  static String _detectUserTimezone() {
    final offset = DateTime.now().timeZoneOffset.inHours;
    const labels = {
      8: 'Asia/Shanghai (UTC+8)',
      9: 'Asia/Tokyo (UTC+9)',
      7: 'Asia/Bangkok (UTC+7)',
      0: 'Europe/London (UTC+0)',
      -5: 'America/New_York (UTC-5)',
      -8: 'America/Los_Angeles (UTC-8)',
    };
    return labels[offset] ?? 'UTC$offset';
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      final backgroundStory = _backgroundStoryController.text.trim();
      final worldSetting = _worldSettingController.text.trim();
      final languageStyle = _languageStyleController.text.trim();
      final tabooTopics = _tabooTopicsController.text.trim();
      final characterTag = _characterTagController.text.trim();

      final freshCharacter = await storage.getAICharacter(_character.id);
      final baseCharacter = freshCharacter ?? _character;
      final updatedCharacter = baseCharacter.copyWith(
        avatarUrl: _newAvatarPath ?? _character.avatarUrl,
        personality: _personalityController.text.trim(),
        backgroundStory: backgroundStory.isEmpty ? null : backgroundStory,
        clearBackgroundStory: backgroundStory.isEmpty,
        coreDesire: _coreDesireController.text.trim(),
        moralBoundary: _moralBoundaryController.text.trim(),
        worldSetting: worldSetting.isEmpty ? null : worldSetting,
        clearWorldSetting: worldSetting.isEmpty,
        languageStyle: languageStyle.isEmpty ? null : languageStyle,
        clearLanguageStyle: languageStyle.isEmpty,
        tabooTopics: tabooTopics.isEmpty ? null : tabooTopics,
        clearTabooTopics: tabooTopics.isEmpty,
        characterTag: characterTag.isEmpty ? null : characterTag,
        clearCharacterTag: characterTag.isEmpty,
        evolutionEnabled: _evolutionEnabled,
        qualitativeEvolutionEnabled: _qualitativeEvolutionEnabled,
        structuredTraits: _buildStructuredTraitsJson(),
        updatedAt: DateTime.now(),
      );

      await storage.saveAICharacter(updatedCharacter);

      if (mounted) {
        _character = updatedCharacter;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功！AI将立即遵循新的设定'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isEditing = false;
          _hasChanges = false;
          _newAvatarPath = null;
        });
        widget.onCharacterUpdated?.call(updatedCharacter);
        Navigator.pop(context, updatedCharacter);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  static const _sectionTitles = [
    '性格',
    '故事',
    'TA的心愿',
    'TA的原则',
    '世界观',
    '语言风格',
    '禁忌话题',
    '外貌设定',
    '生活习惯与特征',
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditingSection = _editingSection != null;

    if (isEditingSection) {
      return _buildSectionEditMode(context, _editingSection!);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: widget.scrollController,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildEditToggleButton(context),
          const SizedBox(height: 12),
          if (_isEditing) ...[
            _buildCollapsibleEditableSection(context, '性格',
                Icons.psychology_outlined, _personalityController, '描述TA的性格特点',
                sectionIndex: 0),
            _buildCollapsibleEditableSection(
                context,
                '故事',
                Icons.auto_stories_outlined,
                _backgroundStoryController,
                '描述TA的背景故事',
                sectionIndex: 1),
            _buildCollapsibleEditableSection(context, 'TA的心愿',
                Icons.favorite_outline, _coreDesireController, '描述TA内心深处的渴望',
                sectionIndex: 2),
            _buildCollapsibleEditableSection(context, 'TA的原则',
                Icons.shield_outlined, _moralBoundaryController, '描述TA坚守的原则和底线',
                sectionIndex: 3),
            _buildCollapsibleEditableSection(context, '世界观',
                Icons.public_outlined, _worldSettingController, '描述TA的世界观设定',
                sectionIndex: 4),
            _buildCollapsibleEditableSection(
                context,
                '语言风格',
                Icons.chat_bubble_outline,
                _languageStyleController,
                '描述TA的说话风格',
                sectionIndex: 5),
            _buildCollapsibleEditableSection(context, '禁忌话题',
                Icons.block_outlined, _tabooTopicsController, '描述TA不会讨论的话题',
                sectionIndex: 6),
            _buildCollapsibleEditableSection(
                context,
                '外貌设定',
                Icons.face_outlined,
                _characterTagController,
                '描述TA的外貌特征：发色、瞳色、脸型、体型、服饰等',
                sectionIndex: 7),
            _buildCollapsibleEditableSection(
                context,
                '生活习惯与特征',
                Icons.spa_outlined,
                null,
                '兴趣爱好、日常作息、口癖，让AI更有真实的生活气息',
                sectionIndex: 8),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用日常人格进化'),
              subtitle: const Text('普通长期互动下，角色会缓慢微调表达与部分核心特质'),
              value: _evolutionEnabled,
              onChanged: (value) {
                setState(() {
                  _evolutionEnabled = value;
                  _hasChanges = true;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许重大事件人格质变'),
              subtitle: const Text('默认关闭。开启后，重大剧情事件下角色可能发生更深层蜕变'),
              value: _qualitativeEvolutionEnabled,
              onChanged: (value) {
                if (value) {
                  _confirmEnableQualitativeEvolution();
                  return;
                }
                setState(() {
                  _qualitativeEvolutionEnabled = false;
                  _hasChanges = true;
                });
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _restoreInitialPersona,
                icon: const Icon(Icons.restore),
                label: const Text('恢复初始人设'),
              ),
            ),
            const SizedBox(height: 16),
            _buildSaveButton(context),
          ] else ...[
            _buildCollapsibleInfoSection(context, '性格',
                Icons.psychology_outlined, _character.personality,
                initiallyExpanded: true),
            if ((_character.backgroundStory?.isNotEmpty) == true)
              _buildCollapsibleInfoSection(
                  context,
                  '故事',
                  Icons.auto_stories_outlined,
                  _character.backgroundStory ?? ''),
            _buildCollapsibleInfoSection(context, 'TA的心愿',
                Icons.favorite_outline, _character.coreDesire),
            _buildCollapsibleInfoSection(context, 'TA的原则',
                Icons.shield_outlined, _character.moralBoundary),
            if ((_character.worldSetting?.isNotEmpty) == true)
              _buildCollapsibleInfoSection(context, '世界观',
                  Icons.public_outlined, _character.worldSetting ?? ''),
            if ((_character.languageStyle?.isNotEmpty) == true)
              _buildCollapsibleInfoSection(context, '语言风格',
                  Icons.chat_bubble_outline, _character.languageStyle ?? ''),
            if ((_character.tabooTopics?.isNotEmpty) == true)
              _buildCollapsibleInfoSection(context, '禁忌话题',
                  Icons.block_outlined, _character.tabooTopics ?? ''),
            // 外貌设定始终显示，空时提示用户填写
            _buildCollapsibleInfoSection(
              context,
              '外貌设定',
              Icons.face_outlined,
              (_character.characterTag?.isNotEmpty == true)
                  ? _character.characterTag!
                  : '尚未设置外貌特征\n\n点击右上角「编辑」→ 展开「外貌设定」→ 填写发色、瞳色等外貌信息。',
              initiallyExpanded: _character.characterTag?.isNotEmpty != true,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用日常人格进化'),
              subtitle: const Text('普通长期互动下，角色会缓慢微调表达与部分核心特质'),
              value: _evolutionEnabled,
              onChanged: (value) async {
                setState(() {
                  _evolutionEnabled = value;
                  _hasChanges = true;
                });
                await _saveChanges();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(value ? '已开启日常人格进化' : '已关闭日常人格进化'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许重大事件人格质变'),
              subtitle: const Text('默认关闭。开启后，重大剧情事件下角色可能发生更深层蜕变'),
              value: _qualitativeEvolutionEnabled,
              onChanged: (value) async {
                if (value) {
                  await _confirmEnableQualitativeEvolution();
                } else {
                  setState(() {
                    _qualitativeEvolutionEnabled = false;
                    _hasChanges = true;
                  });
                }
                if (mounted) {
                  await _saveChanges();
                }
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _restoreInitialPersona,
                icon: const Icon(Icons.restore),
                label: const Text('恢复初始人设'),
              ),
            ),
            _buildEvolutionHistorySection(context),
            _buildVoiceSampleSection(context),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayAvatarPath = _newAvatarPath ?? _character.avatarUrl;
    final hasValidAvatar =
        displayAvatarPath != null && File(displayAvatarPath).existsSync();

    return Row(
      children: [
        GestureDetector(
          onTap: _isEditing ? _pickAvatar : null,
          child: Stack(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasValidAvatar
                      ? null
                      : LinearGradient(
                          colors: [
                            Colors.purple.shade300,
                            Colors.purple.shade500
                          ],
                        ),
                ),
                child: hasValidAvatar
                    ? ClipOval(
                        child: Image.file(
                          File(displayAvatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                        ),
                      )
                    : _buildDefaultAvatar(),
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _character.userAlias ?? _character.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_character.userAlias != null) ...[
                const SizedBox(height: 4),
                Text(
                  '原名：${_character.name}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
              if (_character.userNickname != null) ...[
                const SizedBox(height: 4),
                Text(
                  '称呼你为：${_character.userNickname}',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmEnableQualitativeEvolution() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认开启人格质变'),
        content: const Text(
          '开启后，角色在重大剧情事件下可能发生更深层的人格蜕变，例如核心攻击性、信任方式、克制程度被长期重塑。\n\n这会显著提升拟真度，但也可能让角色慢慢偏离最初的样子。你之后仍可通过“恢复初始人设”一键回退。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认开启'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _qualitativeEvolutionEnabled = true;
        _hasChanges = true;
      });
    }
  }

  Future<void> _restoreInitialPersona() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('人设恢复功能暂时不可用'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Widget _buildEvolutionHistorySection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _buildCollapsibleInfoSection(
        context,
        '成长记录',
        Icons.timeline,
        '成长记录功能暂时不可用。',
      ),
    );
  }

  bool _hasTtsApiKey = false;

  Widget _buildVoiceSampleSection(BuildContext context) {
    final voiceClone = VoiceCloneService();
    final hasVoice = voiceClone.hasVoice(_character.id);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCollapsibleInfoSection(
            context,
            '音色克隆',
            Icons.record_voice_over,
            hasVoice
                ? '已设置音色样本。可试听或重新上传。'
                : '上传音频后，AI 回复可朗读为语音。\n支持 mp3/wav 格式，最大 10MB。',
          ),
          if (!_hasTtsApiKey)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '未配置 TTS API Key，试听和语音合成功能不可用。请在设置 → 语音 → TTS API Key 中配置。',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _uploadVoiceSample(voiceClone),
                  icon: Icon(hasVoice ? Icons.refresh : Icons.upload_file,
                      size: 18),
                  label: Text(hasVoice ? '更换音色' : '上传音色样本'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                ),
                if (hasVoice) ...[
                  ElevatedButton.icon(
                    onPressed: _isPreviewPlaying
                        ? null
                        : () => _playPreview(voiceClone),
                    icon: Icon(
                        _isPreviewPlaying ? Icons.stop : Icons.play_arrow,
                        size: 18),
                    label: Text(_isPreviewPlaying ? '播放中...' : '试听'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteVoiceSample(voiceClone),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isPreviewPlaying = false;
  AudioPlayer? _previewPlayer;
  StreamSubscription? _previewCompleteSub;

  Future<void> _playPreview(VoiceCloneService voiceClone) async {
    if (!_hasTtsApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先配置 TTS API Key'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isPreviewPlaying = true);
    try {
      final path = await voiceClone.generatePreview(_character.id);
      if (path != null && mounted) {
        _previewCompleteSub?.cancel();
        _previewPlayer?.dispose();
        _previewPlayer = AudioPlayer();
        await _previewPlayer!.play(DeviceFileSource(path));
        _previewCompleteSub = _previewPlayer!.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _isPreviewPlaying = false);
        });
        return;
      }
    } catch (e) {
      debugPrint('试听失败: $e');
    }
    if (mounted) {
      setState(() => _isPreviewPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('试听失败，可能被限流，请稍后重试'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadVoiceSample(VoiceCloneService voiceClone) async {
    try {
      final previewText = '你好，我是${_character.name}。';
      final result = await voiceClone.pickAndSaveVoice(
        _character.id,
        previewText: previewText,
      );
      if (result != null && mounted) {
        // 立即刷新 UI，显示试听按钮
        setState(() {});
        // 检查 API Key 状态
        _checkTtsApiKey();
        // 自动播放试听
        if (result.previewPath != null) {
          _previewCompleteSub?.cancel();
          _previewPlayer?.dispose();
          _previewPlayer = AudioPlayer();
          await _previewPlayer!.play(DeviceFileSource(result.previewPath!));
          setState(() => _isPreviewPlaying = true);
          _previewCompleteSub = _previewPlayer!.onPlayerComplete.listen((_) {
            if (mounted) setState(() => _isPreviewPlaying = false);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('音色已上传，正在试听'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('音色已上传，但试听失败（可能未配置 API Key 或被限流）'),
                backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteVoiceSample(VoiceCloneService voiceClone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除音色样本'),
        content: const Text('确定删除该角色的音色样本吗？删除后将无法朗读语音。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );

    if (confirmed == true) {
      await voiceClone.deleteVoice(_character.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音色样本已删除')),
        );
      }
    }
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Colors.purple.shade300, Colors.purple.shade500],
        ),
      ),
      child: Center(
        child: Text(
          _character.name.isNotEmpty ? _character.name[0] : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEditToggleButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_hasChanges && _isEditing)
          TextButton(
            onPressed: _isSaving ? null : _saveChanges,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _isEditing = !_isEditing;
              if (!_isEditing && _hasChanges) {
                _initControllers();
                _hasChanges = false;
                _newAvatarPath = null;
              }
            });
          },
          icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
          label: Text(_isEditing ? '查看模式' : '编辑'),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  /// 分栏编辑模式：只显示当前模块，铺满键盘上方
  Widget _buildSectionEditMode(BuildContext context, int section) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget content;

    switch (section) {
      case 0: // 性格
        content = TextFormField(
          controller: _personalityController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '性格',
            hintText: '描述TA的性格特点',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 1: // 故事
        content = TextFormField(
          controller: _backgroundStoryController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '故事',
            hintText: '描述TA的背景故事',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 2: // 心愿
        content = TextFormField(
          controller: _coreDesireController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'TA的心愿',
            hintText: '描述TA内心深处的渴望',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 3: // 原则
        content = TextFormField(
          controller: _moralBoundaryController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'TA的原则',
            hintText: '描述TA坚守的原则和底线',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 4: // 世界观
        content = TextFormField(
          controller: _worldSettingController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '世界观',
            hintText: '描述TA的世界观设定',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 5: // 语言风格
        content = TextFormField(
          controller: _languageStyleController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '语言风格',
            hintText: '描述TA的说话风格',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 6: // 禁忌话题
        content = TextFormField(
          controller: _tabooTopicsController,
          autofocus: true,
          maxLines: null,
          onChanged: (_) => _onContentChanged(),
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '禁忌话题',
            hintText: '描述TA不会讨论的话题',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 7: // 外貌设定
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '外貌设定',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '详细描述TA的外貌特征',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _characterTagController,
              autofocus: true,
              maxLines: null,
              onChanged: (_) => _onContentChanged(),
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '外貌特征',
                hintText: '如：银色长发、紫色瞳孔、瓜子脸、身材高挑、穿白色连衣裙、戴银色耳环',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '填写建议',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 发色/发型：如黑色短发、金色双马尾、棕色波浪卷\n'
                    '• 瞳色：如蓝色眼睛、琥珀色瞳孔\n'
                    '• 脸型/五官：如瓜子脸、高鼻梁、薄唇\n'
                    '• 体型：如纤细、高挑、娇小\n'
                    '• 标志配饰：如红色发带、银色耳环、黑框眼镜\n'
                    '• 基础穿搭：如白色衬衫牛仔裤、黑色连衣裙',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        break;
      case 8: // 生活习惯与特征
        content = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '兴趣爱好',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用、分隔多个爱好，会让 AI 自然地谈论和回复相关话题',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _hobbiesController,
                autofocus: true,
                maxLines: null,
                onChanged: (_) => _onContentChanged(),
                decoration: InputDecoration(
                  hintText: '如：钢琴、推理小说、看电影、烘焙',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '日常作息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '每行一条，格式: 时段: 活动（"周练琴不回消息"等行程会影响活跃时段）',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _routineController,
                autofocus: true,
                maxLines: null,
                onChanged: (_) => _onContentChanged(),
                decoration: InputDecoration(
                  hintText:
                      '早上7-8点: 起床准备\n工作日9-18点: 在公司\n周三下午: 练琴不回消息\n深夜1-2点: 经常失眠刷手机',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '小习惯 / 口癖',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '用；分隔，这些口癖会让 AI 回复更有个人色彩',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _quirksController,
                autofocus: true,
                maxLines: null,
                onChanged: (_) => _onContentChanged(),
                decoration: InputDecoration(
                  hintText: '如：习惯先说"诶"；生气时会突然很安静；喜欢反复翻看朋友圈',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '提示',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '结构化特征比在"性格"里堆文字更具体——AI 会在相关场景自然带出这些细节，'
                      '让对话有真实的生活气息。时区会自动基于你的设备检测。',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        break;
      default:
        content = const SizedBox.shrink();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _exitEditMode,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回设定列表'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _hasChanges && !_isSaving ? _saveChanges : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _editingScrollController,
            padding: const EdgeInsets.all(20),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsibleEditableSection(
    BuildContext context,
    String title,
    IconData icon,
    TextEditingController? controller,
    String hint, {
    int sectionIndex = 0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outline.withOpacity(0.15)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, color: colorScheme.primary, size: 20),
          title: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          iconColor: colorScheme.primary,
          collapsedIconColor: colorScheme.onSurface.withOpacity(0.4),
          children: [
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
              ),
              child: controller == null
                  ? ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      title: Text(
                        hint,
                        style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.6)),
                      ),
                      trailing: Icon(Icons.chevron_right,
                          size: 20, color: colorScheme.onSurface.withOpacity(0.4)),
                      onTap: () => _enterEditMode(sectionIndex),
                    )
                  : TextField(
                      controller: controller,
                      maxLines: 4,
                      onChanged: (_) => _onContentChanged(),
                      onTap: () => _enterEditMode(sectionIndex),
                      style: const TextStyle(fontSize: 14, height: 1.5),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.4),
                            fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: _hasChanges && !_isSaving ? _saveChanges : null,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('保存修改'),
    );
  }

  Widget _buildCollapsibleInfoSection(
    BuildContext context,
    String title,
    IconData icon,
    String content, {
    bool initiallyExpanded = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outline.withOpacity(0.15)),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, color: colorScheme.primary, size: 20),
          title: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          iconColor: colorScheme.primary,
          collapsedIconColor: colorScheme.onSurface.withOpacity(0.4),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(content,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
