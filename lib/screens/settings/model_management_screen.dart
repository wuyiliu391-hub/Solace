import 'package:flutter/material.dart';
import '../../services/tflite_service.dart';
import '../../services/image_understanding_service.dart';
import '../../services/multimodal_service.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  final _tflite = TFLiteService();
  bool _hasMultimodalModels = false;

  @override
  void initState() {
    super.initState();
    if (!_tflite.isLoaded && !_tflite.isLoading) {
      _tflite.loadModel().then((_) {
        if (mounted) setState(() {});
      }).catchError((e) {
        debugPrint('TFLite 模型加载失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI 模型加载失败，部分功能不可用')),
          );
        }
      });
    }
    _checkMultimodalStatus();
  }

  Future<void> _checkMultimodalStatus() async {
    final ready = MultimodalService().isReady;
    if (mounted) {
      setState(() {
        _hasMultimodalModels = ready;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片识别模型'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.memory,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MobileNet V2',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold)),
                            Text('图像分类模型',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                      _buildStatusBadge(theme),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('识别图片中的物体、场景和内容，增强 AI 对图片的理解能力。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('模型大小: ~3.5 MB | 已内置在应用中',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline)),
                  const SizedBox(height: 16),
                  if (_tflite.isLoading)
                    const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('系统状态',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildStatusRow(
                    'TFLite 服务',
                    _tflite.isLoaded,
                    theme,
                  ),
                  const SizedBox(height: 8),
                  _buildStatusRow(
                    '多模态模型',
                    _hasMultimodalModels,
                    theme,
                  ),
                  const SizedBox(height: 8),
                  _buildStatusRow(
                    '多模态引擎',
                    MultimodalService().isReady,
                    theme,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '基础模型已内置，无需下载。'
                    '多模态模型需在设置中下载，安装后 AI 可真正"看懂"图片。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isReady, ThemeData theme) {
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.hourglass_empty,
          size: 18,
          color: isReady ? Colors.green : theme.colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildStatusBadge(ThemeData theme) {
    if (_tflite.isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('加载中',
            style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.blue, fontWeight: FontWeight.w500)),
      );
    }
    if (_tflite.isLoaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('就绪',
            style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green, fontWeight: FontWeight.w500)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('未加载',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline)),
    );
  }
}
