import 'dart:io';
import 'package:flutter/foundation.dart';
import 'multimodal_service.dart';

class ImageUnderstandingService {
  static final ImageUnderstandingService _instance = ImageUnderstandingService._();
  factory ImageUnderstandingService() => _instance;
  ImageUnderstandingService._();

  Future<String> describeImage(String imagePath) async {
    try {
      if (!await File(imagePath).exists()) {
        debugPrint('[ERR] [图片理解] 图片文件不存在 $imagePath');
        return '';
      }

      debugPrint('[SYNC] [图片理解] 调用云端多模态模型...');
      final result = await MultimodalService().describeImage(imagePath);

      if (result.isNotEmpty) {
        debugPrint('[OK] [图片理解] 成功，${result.length} 字符');
      }
      return result;
    } catch (e) {
      debugPrint('[ERR] [图片理解] 异常: $e');
      return '';
    }
  }

  Future<String> describeMultipleImages(List<String> imagePaths) async {
    if (imagePaths.isEmpty) return '';
    if (imagePaths.length == 1) return describeImage(imagePaths[0]);
    try {
      debugPrint('[SYNC] [图片理解] 批处理 ${imagePaths.length} 张图片...');
      final result = await MultimodalService().describeImages(imagePaths);
      if (result.isNotEmpty) {
        debugPrint('[OK] [图片理解] 批处理成功，${result.length} 字符');
      }
      return result;
    } catch (e) {
      debugPrint('[ERR] [图片理解] 批处理异常: $e');
      return '';
    }
  }

  Future<String> describeImageCompact(String imagePath) async {
    return describeImage(imagePath);
  }
}