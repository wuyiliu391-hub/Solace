// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _StickerPickerSheet extends StatefulWidget {
  final Function(String) onEmojiSelected;
  final Function(String) onStickerSelected;
  final Function(String)? onImageStickerSelected;
  final LocalStorageRepository storage;

  const _StickerPickerSheet({
    required this.onEmojiSelected,
    required this.onStickerSelected,
    this.onImageStickerSelected,
    required this.storage,
  });

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}


class _StickerPickerSheetState extends State<_StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  BuiltinStickerPack? _pack;
  List<StickerPack> _customPacks = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStickers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    try {
      final pack = await BuiltinStickerService.loadDefaultPack();
      final customPacks = await widget.storage.getAllStickerPacks();
      if (mounted) {
        setState(() {
          _pack = pack;
          _customPacks = customPacks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onDeleteSticker(StickerItem sticker) async {
    // Find which pack this sticker belongs to
    String? packId;
    for (final pack in _customPacks) {
      if (pack.stickers.any((s) => s.id == sticker.id)) {
        packId = pack.id;
        break;
      }
    }
    if (packId == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此表情', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete_one'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('删除整个表情包', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete_pack'),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    final service = StickerPackService(widget.storage);
    if (action == 'delete_one') {
      await service.removeStickerFromPack(
          packId: packId, stickerId: sticker.id);
      // If pack is now empty, delete it entirely
      final pack = await service.getStickerPack(packId);
      if (pack != null && pack.stickers.isEmpty) {
        await service.deleteStickerPack(packId);
      }
    } else if (action == 'delete_pack') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: const Text('将删除该表情包中的所有表情，且无法恢复。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await service.deleteStickerPack(packId);
      }
    }

    await _loadStickers();
  }

  Future<void> _addCustomSticker() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty) return;

      final service = StickerPackService(widget.storage);

      // 创建新表情包或添加到最近的自定义包
      StickerPack targetPack;
      if (_customPacks.isEmpty) {
        targetPack = await service.createStickerPack(
          name: '我的表情包',
          initialImagePaths: images.map((f) => f.path).toList(),
        );
      } else {
        targetPack = _customPacks.last;
        for (final img in images) {
          await service.addStickerToPack(
            packId: targetPack.id,
            imagePath: img.path,
          );
        }
        targetPack = (await service.getStickerPack(targetPack.id))!;
      }

      await _loadStickers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加${images.length} 个表情'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Tab 栏 + 添加按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor:
                        colorScheme.onSurface.withOpacity(0.5),
                    indicatorColor: colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    dividerHeight: 0,
                    tabs: const [
                      Tab(text: '默认表情'),
                      Tab(text: '我的表情'),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      color: colorScheme.primary, size: 22),
                  tooltip: '添加自定义表情',
                  onPressed: _addCustomSticker,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 默认表情 Tab
                  _buildBuiltinTab(),
                  // 自定义表情 Tab
                  _buildCustomTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBuiltinTab() {
    if (_pack == null || _pack!.stickers.isEmpty) {
      return const Center(child: Text('暂无默认表情'));
    }
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _pack!.stickers.length,
      itemBuilder: (context, index) {
        final sticker = _pack!.stickers[index];
        return GestureDetector(
          onTap: () => widget.onStickerSelected(sticker.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              BuiltinStickerService.getStickerAssetPath(sticker.file),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image, color: cs.outline),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomTab() {
    final cs = Theme.of(context).colorScheme;
    if (_customPacks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural,
                size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text('还没有自定义表情',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addCustomSticker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('从相册添加'),
            ),
          ],
        ),
      );
    }

    // 收集所有自定义表情
    final allStickers = <StickerItem>[];
    for (final pack in _customPacks) {
      allStickers.addAll(pack.stickers);
    }

    if (allStickers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural,
                size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text('表情包是空的',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addCustomSticker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加表情'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: allStickers.length,
      itemBuilder: (context, index) {
        final sticker = allStickers[index];
        return GestureDetector(
          onTap: () => widget.onImageStickerSelected?.call(sticker.imagePath),
          onLongPress: () => _onDeleteSticker(sticker),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(sticker.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image, color: cs.outline),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 流式输出气泡 - 实时显示AI正在生成的文字，思考内容用倾斜字体
