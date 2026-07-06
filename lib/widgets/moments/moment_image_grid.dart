import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/moments_theme.dart';

/// 推文图片网格（1-9图自适应）
class MomentImageGrid extends StatelessWidget {
  final List<String> images;
  final ValueChanged<int>? onImageTap;

  const MomentImageGrid({
    super.key,
    required this.images,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _buildGrid(context),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final count = images.length.clamp(1, 9);
    if (count == 1) return _singleImage(context);
    if (count == 2) return _twoImages(context);
    if (count == 3) return _threeImages(context);
    return _multiImages(context, count);
  }

  Widget _singleImage(BuildContext context) {
    return GestureDetector(
      onTap: () => onImageTap?.call(0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: _imageWidget(context, 0, width: double.infinity, fit: BoxFit.cover),
      ),
    );
  }

  Widget _twoImages(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onImageTap?.call(0),
              child: _imageWidget(context, 0, height: 200, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: GestureDetector(
              onTap: () => onImageTap?.call(1),
              child: _imageWidget(context, 1, height: 200, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _threeImages(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onImageTap?.call(0),
              child: _imageWidget(context, 0, height: 200, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onImageTap?.call(1),
                    child: _imageWidget(context, 1, width: double.infinity, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onImageTap?.call(2),
                    child: _imageWidget(context, 2, width: double.infinity, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _multiImages(BuildContext context, int count) {
    final cols = count <= 4 ? 2 : 3;
    final displayCount = count.clamp(1, 9);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: displayCount,
      itemBuilder: (ctx, i) => GestureDetector(
        onTap: () => onImageTap?.call(i),
        child: _imageWidget(context, i, fit: BoxFit.cover),
      ),
    );
  }

  Widget _imageWidget(BuildContext context, int index,
      {double? width, double? height, BoxFit? fit}) {
    if (index >= images.length) return const SizedBox.shrink();
    final path = images[index];
    final borderColor = MomentsTheme.divider(context);

    Widget image;
    if (path.startsWith('http')) {
      image = Image.network(path,
          width: width, height: height, fit: fit ?? BoxFit.cover,
          errorBuilder: (_, __, ___) => _errorPlaceholder(context));
    } else {
      final file = File(path);
      if (file.existsSync()) {
        image = Image.file(file,
            width: width, height: height, fit: fit ?? BoxFit.cover,
            errorBuilder: (_, __, ___) => _errorPlaceholder(context));
      } else {
        image = _errorPlaceholder(context);
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor.withOpacity(0.3), width: 0.5),
      ),
      child: image,
    );
  }

  Widget _errorPlaceholder(BuildContext context) {
    return Container(
      color: MomentsTheme.surface(context),
      child: Center(
        child: Icon(Icons.broken_image,
            color: MomentsTheme.textSecondary(context), size: 32),
      ),
    );
  }
}
