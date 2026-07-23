import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/avatar/avatar_config.dart';
import '../models/pet/pet_character_config.dart';

/// Live2D 桌宠控制服务
///
/// 封装 Android 原生悬浮窗的 MethodChannel 调用。
class Live2DService {
  static const MethodChannel _channel =
      MethodChannel('com.solace.solace/live2d');
  static const EventChannel _eventChannel =
      EventChannel('com.solace.solace/live2d_events');

  static Stream<Map<dynamic, dynamic>?>? _eventStream;

  /// 检查悬浮窗权限
  static Future<bool> checkOverlayPermission() async {
    try {
      return await _channel.invokeMethod('checkOverlayPermission') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 请求悬浮窗权限
  static Future<void> requestOverlayPermission() async {
    await _channel.invokeMethod('requestOverlayPermission');
  }

  /// 显示桌宠悬浮窗
  static Future<bool> showOverlay() async {
    try {
      return await _channel.invokeMethod('showOverlay') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 隐藏桌宠悬浮窗
  static Future<bool> hideOverlay() async {
    try {
      return await _channel.invokeMethod('hideOverlay') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 悬浮窗是否运行中
  static Future<bool> isOverlayRunning() async {
    try {
      return await _channel.invokeMethod('isOverlayRunning') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 同步整套 Avatar 配置到悬浮窗
  static Future<void> syncAvatarConfig(AvatarConfig config) async {
    await _channel.invokeMethod('syncAvatarConfig', {
      'config': jsonEncode(config.toJson()),
    });
  }

  /// 同步崽崽角色配置到悬浮窗（头像即崽崽新架构）
  static Future<void> syncPetCharacter(PetCharacterConfig config) async {
    await _channel.invokeMethod('syncPetCharacter', {
      'config': jsonEncode(config.toJson()),
    });
  }

  /// 设置部位显隐（兼容旧接口）
  static Future<void> setPartVisible(String part, bool visible) async {
    await _channel.invokeMethod('setPartVisible', {
      'part': part,
      'visible': visible,
    });
  }

  /// 监听桌宠状态流
  static Stream<Map<dynamic, dynamic>?> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as Map?);
    return _eventStream!;
  }
}
