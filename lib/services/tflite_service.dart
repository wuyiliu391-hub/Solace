import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/model_config.dart';

class TFLiteService {
  static final TFLiteService _instance = TFLiteService._();
  factory TFLiteService() => _instance;
  TFLiteService._();

  bool _isLoaded = false;
  bool _isLoading = false;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  Future<void> loadModel() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      // TFLite 模型加载需要 tflite_flutter 包
      // 当前为占位实现，待添加依赖后启用
      debugPrint('TFLite 模型加载跳过（缺少 tflite_flutter 依赖）');
      _isLoaded = false;
    } catch (e) {
      debugPrint('TFLite 模型加载失败: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<List<ClassificationResult>> classifyImage(String imagePath) async {
    if (!_isLoaded) {
      return [];
    }

    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) return [];

      final resized = img.copyResize(image,
          width: ModelConfig.classificationImageSize,
          height: ModelConfig.classificationImageSize);

      // TFLite 推理需要 tflite_flutter 包
      // 当前为占位实现
      debugPrint('TFLite 推理跳过（缺少 tflite_flutter 依赖）');
      return [];
    } catch (e) {
      debugPrint('TFLite 推理失败: $e');
      return [];
    }
  }

  void dispose() {
    _isLoaded = false;
    _isLoading = false;
  }
}

class ClassificationResult {
  final String label;
  final double confidence;
  final int index;

  ClassificationResult({
    required this.label,
    required this.confidence,
    required this.index,
  });
}
