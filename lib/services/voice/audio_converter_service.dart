// 音频格式转换服务：把 mp3/m4a/aac/ogg/flac 等压缩音频解码成 48kHz 双声道 wav，
// 供音色克隆当参考音频使用（MOSS codec encode 输入要求 48kHz 双声道）。
//
// 实现走 Android 原生 MediaExtractor + MediaCodec（系统自带解码器，零额外体积），
// 输出 wav 保存到公共下载目录 Download/Solace/（有权限时）或应用外部缓存目录（兜底）。
// 非 Android 平台不支持。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioConverterService {
  AudioConverterService._();
  static final AudioConverterService instance = AudioConverterService._();

  static const MethodChannel _channel = MethodChannel('com.solace.solace/audio');

  /// 目标文件是否为可直接使用的 wav（无需转换）。
  static bool isWav(String path) =>
      path.toLowerCase().endsWith('.wav');

  /// 是否为受支持的可转换音频格式。
  static bool isSupportedAudio(String path) {
    final lower = path.toLowerCase();
    return const ['.wav', '.mp3', '.m4a', '.aac', '.ogg', '.flac']
        .any(lower.endsWith);
  }

  /// 把 [inputPath] 解码为 16-bit 单声道 PCM wav，保存到公共目录。
  /// 返回输出 wav 的绝对路径。
  Future<String> convertToWav(String inputPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('音频转换当前仅支持 Android');
    }
    if (isWav(inputPath)) return inputPath;

    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>('convertToWav', {
      'inputPath': inputPath,
    });

    final path = result?['path'];
    if (path is String && path.isNotEmpty) {
      return path;
    }
    final error = result?['error'];
    throw Exception(error is String ? error : '音频转换失败');
  }

  /// 参考音频规范化（音色克隆专用）：任意 mp3/wav 输入 → 24kHz 单声道
  /// 16-bit wav，切头部静音后截取前 [maxSeconds] 秒。
  ///
  /// MiMo voiceclone 官方仅推荐「短至几秒」的参考音频；超长/立体声样本
  /// 会令克隆音色偏移、人机感重。返回规范化后的 wav 绝对路径。
  Future<String> normalizeReferenceAudio(
    String inputPath, {
    int maxSeconds = 6,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('音频转换当前仅支持 Android');
    }
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>('normalizeReferenceAudio', {
      'inputPath': inputPath,
      'maxSeconds': maxSeconds,
    });

    final path = result?['path'];
    if (path is String && path.isNotEmpty) {
      return path;
    }
    final error = result?['error'];
    throw Exception(error is String ? error : '音频规范化失败');
  }

  /// 音色相似度（0~1）：对比参考音频与合成音频的频带能量分布。
  /// B 方案：合成后检测漂移，低于阈值视为不合格（需重合成）。
  /// 非 Android 平台返回 1.0（不阻塞，跳过检测）。
  Future<double> voiceSimilarity(String refPath, String synPath) async {
    if (!Platform.isAndroid) return 1.0;
    try {
      final result = await _channel
          .invokeMethod<num>('voiceSimilarity', {
        'refPath': refPath,
        'synPath': synPath,
      });
      return (result?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('[AudioConvert] voiceSimilarity 失败，跳过检测: $e');
      return 1.0;
    }
  }
}
