import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/ai_character.dart';
import '../../models/pet/pet_character_config.dart';
import '../../repositories/local_storage_repository.dart';
import '../../repositories/pet_character_repository.dart';
import '../../services/live2d_service.dart';
import '../../utils/avatar_resolver.dart';

/// 崽崽管理页面（头像即崽崽版本）
///
/// 用户从所有 AI 角色中选择一个，把他的头像作为全局悬浮窗崽崽形象。
/// 支持显示/隐藏悬浮窗、切换头像框样式。
class Live2DManagerScreen extends StatefulWidget {
  const Live2DManagerScreen({super.key});

  @override
  State<Live2DManagerScreen> createState() => _Live2DManagerScreenState();
}

class _Live2DManagerScreenState extends State<Live2DManagerScreen>
    with WidgetsBindingObserver {
  bool _isOverlayRunning = false;
  bool _hasPermission = false;
  bool _loading = false;
  bool _loadingCharacters = true;

  List<AICharacter> _characters = [];
  PetCharacterConfig _currentPet = PetCharacterConfig.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkStatus();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loadingCharacters = true);
    try {
      // 优先从 RepositoryProvider 拿已初始化的实例；fallback 直接 new
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final characters = await storage.getAllAICharacters();
      final currentPet = await PetCharacterRepository.instance.getCurrentPet();
      final running = await Live2DService.isOverlayRunning();
      final permission = await Live2DService.checkOverlayPermission();
      // 如果悬浮窗已经在运行，重新同步当前配置（防止 EventChannel 事件丢失）
      if (running) {
        await Live2DService.syncPetCharacter(currentPet);
      }

      if (mounted) {
        setState(() {
          _characters = characters;
          _currentPet = currentPet;
          _isOverlayRunning = running;
          _hasPermission = permission;
          _loadingCharacters = false;
        });
      }
    } catch (e) {
      debugPrint('Live2D manager load failed: $e');
      if (mounted) {
        setState(() => _loadingCharacters = false);
      }
    }
  }

  Future<void> _selectCharacter(AICharacter character) async {
    final repo = PetCharacterRepository.instance;
    var config = repo.configFromAiCharacter(character);
    // 保留当前样式设置
    config = config.copyWith(
      frameStyle: _currentPet.frameStyle,
      bubbleStyle: _currentPet.bubbleStyle,
      enableIdleBubble: _currentPet.enableIdleBubble,
      idleBubbleIntervalSeconds: _currentPet.idleBubbleIntervalSeconds,
    );
    await repo.setCurrentPet(config);

    setState(() => _currentPet = config);

    // 如果悬浮窗正在运行，实时同步
    if (_isOverlayRunning) {
      await Live2DService.syncPetCharacter(config);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${character.name} 已经成为你的崽崽啦～')),
      );
    }
  }

  Future<void> _updateFrameStyle(String style) async {
    final config = _currentPet.copyWith(frameStyle: style);
    await PetCharacterRepository.instance.setCurrentPet(config);
    setState(() => _currentPet = config);
    if (_isOverlayRunning) {
      await Live2DService.syncPetCharacter(config);
    }
  }

  Future<void> _toggleOverlay() async {
    if (!_hasPermission && !_isOverlayRunning) {
      await Live2DService.requestOverlayPermission();
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isOverlayRunning) {
        await Live2DService.hideOverlay();
      } else {
        // 启动前同步当前崽崽配置
        await Live2DService.syncPetCharacter(_currentPet);
        await Live2DService.showOverlay();
      }
      await Future.delayed(const Duration(milliseconds: 300));
      await _checkStatus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkStatus() async {
    final running = await Live2DService.isOverlayRunning();
    final permission = await Live2DService.checkOverlayPermission();
    if (mounted) {
      setState(() {
        _isOverlayRunning = running;
        _hasPermission = permission;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : colorScheme.surface,
      appBar: AppBar(
        title: const Text('我的崽崽', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _toggleOverlay,
                child: Text(_isOverlayRunning ? '隐藏' : '显示'),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrentPetPreview(colorScheme, isDark),
          _buildFrameStyleSelector(colorScheme),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '选择角色',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: _loadingCharacters
                ? const Center(child: CircularProgressIndicator())
                : _characters.isEmpty
                    ? const Center(child: Text('还没有角色，先去创建一个吧～'))
                    : _buildCharacterList(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPetPreview(ColorScheme colorScheme, bool isDark) {
    final avatar = AvatarResolver.imageWidget(
      _currentPet.avatarUrl,
      width: 90,
      height: 90,
      fit: BoxFit.cover,
    );
    final frameImage = _frameImagePath(_currentPet.frameStyle);

    return Container(
      height: 180,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (frameImage != null)
                  Image.asset(
                    frameImage,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: frameImage == null
                        ? Border.all(
                            color: _frameColor(_currentPet.frameStyle).withOpacity(0.9),
                            width: 4,
                          )
                        : null,
                    boxShadow: frameImage == null
                        ? [
                            BoxShadow(
                              color: _frameColor(_currentPet.frameStyle).withOpacity(0.3),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipOval(
                    child: avatar ??
                        Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.person, size: 40, color: Colors.white),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentPet.name.isNotEmpty ? _currentPet.name : '未选择崽崽',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (_currentPet.name.isNotEmpty)
            Text(
              _isOverlayRunning ? '正在桌面上陪伴你' : '点击右上角显示到桌面',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  /// 所有可用头像框：颜色框 + 图片框
  static const List<({String id, String label, Color? color, String? imagePath})> _frames = [
    (id: 'gold', label: '金边', color: Colors.amber, imagePath: null),
    (id: 'pink', label: '粉框', color: Colors.pink, imagePath: null),
    (id: 'blue', label: '蓝框', color: Colors.blue, imagePath: null),
    (id: 'purple', label: '紫框', color: Colors.purple, imagePath: null),
    (id: 'neon', label: '霓虹', color: Colors.tealAccent, imagePath: null),
    (id: 'pink_floral', label: '花环', color: null, imagePath: 'assets/live2d/_frame_previews_doubao/frame_11_pink_floral.png'),
    (id: 'ink_floral', label: '墨藤', color: null, imagePath: 'assets/live2d/_frame_previews_doubao/frame_12_ink_floral.png'),
  ];

  String? _frameImagePath(String style) {
    for (final f in _frames) {
      if (f.id == style) return f.imagePath;
    }
    return null;
  }

  Widget _buildFrameStyleSelector(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('头像框', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _frames.map((f) {
              final selected = _currentPet.frameStyle == f.id;
              final color = f.color ?? colorScheme.primary;
              return InkWell(
                onTap: () => _updateFrameStyle(f.id),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.15),
                    border: Border.all(
                      color: selected ? color : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: f.imagePath != null
                        ? ClipOval(
                            child: Image.asset(
                              f.imagePath!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image,
                                size: 20,
                                color: color.withOpacity(0.6),
                              ),
                            ),
                          )
                        : Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        final character = _characters[index];
        final isSelected = _currentPet.characterId.isNotEmpty &&
            _currentPet.characterId == character.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.5)
              : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _buildCharacterAvatar(character),
            title: Text(character.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              character.personality.isNotEmpty
                  ? (character.personality.length > 30
                      ? '${character.personality.substring(0, 30)}...'
                      : character.personality)
                  : '暂无简介',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: colorScheme.primary)
                : const Icon(Icons.chevron_right),
            onTap: () => _selectCharacter(character),
          ),
        );
      },
    );
  }

  Widget _buildCharacterAvatar(AICharacter character) {
    final image = AvatarResolver.imageWidget(
      character.avatarUrl,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
    );
    return ClipOval(
      child: image ??
          Container(
            width: 48,
            height: 48,
            color: Colors.grey.shade300,
            child: const Icon(Icons.person, size: 24, color: Colors.white),
          ),
    );
  }

  Color _frameColor(String style) {
    switch (style) {
      case 'pink':
        return Colors.pink.shade300;
      case 'blue':
        return Colors.blue.shade300;
      case 'purple':
        return Colors.purple.shade300;
      case 'neon':
        return Colors.tealAccent;
      case 'gold':
      default:
        return Colors.amber.shade400;
    }
  }
}
