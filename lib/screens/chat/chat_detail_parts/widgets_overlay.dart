// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _MoreActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MoreActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}


class _FullScreenImage extends StatefulWidget {
  final String imagePath;
  const _FullScreenImage({required this.imagePath});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}


class _FullScreenImageState extends State<_FullScreenImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late AnimationController _animController;

  double _scale = 1.0;
  double _minScale = 0.5;
  double _maxScale = 4.0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    _scale = (_scale * 1.5).clamp(_minScale, _maxScale);
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  void _zoomOut() {
    _scale = (_scale / 1.5).clamp(_minScale, _maxScale);
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  void _resetZoom() {
    _scale = 1.0;
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  Future<void> _saveToGallery() async {
    // Android 10+ 使用 MediaStore API 保存，确保真实出现在系统相册
    if (Platform.isAndroid) {
      try {
        final channel = MethodChannel('com.solace.solace/gallery');
        final result = await channel.invokeMethod<bool>('saveImageToGallery', {
          'filePath': widget.imagePath,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result == true ? '已保存到系统相册' : '保存失败，请尝试截图'),
              backgroundColor: result == true ? Colors.green : Colors.red,
            ),
          );
        }
        return;
      } catch (e) {
        debugPrint('[FullScreenImage] MethodChannel 保存失败: $e');
        // 回退到文件方案
      }
    }

    // 备选方案：直接复制文件到公共目录
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片文件不存在')),
          );
        }
        return;
      }

      final dir = Directory('/storage/emulated/0/DCIM/Solace');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final fileName = 'solace_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = '${dir.path}/$fileName';
      await file.copy(destPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到 DCIM/Solace/ 目录，请手动刷新相册'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[FullScreenImage] 保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请尝试截图')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 主图片预览
          GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: _minScale,
              maxScale: _maxScale,
              constrained: false,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    size: 64, color: Colors.white54),
              ),
            ),
          ),

          // 顶部栏（返回 + 文件名）
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      '角色图片',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // 平衡布局
                  ],
                ),
              ),
            ),
          ),

          // 底部工具栏（缩放 + 保存）
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 缩小
                        _ToolButton(
                          icon: Icons.zoom_out,
                          label: '缩小',
                          onTap: _zoomOut,
                        ),
                        const SizedBox(width: 8),
                        // 重置
                        _ToolButton(
                          icon: Icons.aspect_ratio,
                          label: '重置',
                          onTap: _resetZoom,
                        ),
                        const SizedBox(width: 8),
                        // 放大
                        _ToolButton(
                          icon: Icons.zoom_in,
                          label: '放大',
                          onTap: _zoomIn,
                        ),
                        const SizedBox(width: 8),
                        // 保存
                        _ToolButton(
                          icon: Icons.download_rounded,
                          label: '保存',
                          color: Colors.greenAccent,
                          onTap: _saveToGallery,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 缩放比例指示
          if (_scale != 1.0 && _showControls)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(_scale * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 全屏预览底部工具按钮
