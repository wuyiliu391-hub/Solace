import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solace/models/avatar/avatar_config.dart';

/// Avatar 配置仓库
///
/// 负责加载、保存内置装扮/捏脸/化妆配置。
class AvatarRepository {
  static const String _key = 'solace_avatar_config';
  static final Map<String, String> _templateCache = {};

  /// 从本地加载，若不存在则返回默认配置
  static Future<AvatarConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json == null) return AvatarConfig.defaultConfig;
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AvatarConfig.fromJson(map);
    } catch (e) {
      return AvatarConfig.defaultConfig;
    }
  }

  /// 保存到本地
  static Future<void> save(AvatarConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  /// 读取内置变体配置（JSON 描述），未来可扩展为部位属性表
  static Future<Map> loadVariantCatalog(String part) async {
    try {
      final json = await rootBundle.loadString(
        'assets/live2d/catalogs/$part.json',
      );
      return jsonDecode(json) as Map;
    } catch (e) {
      return {};
    }
  }
}
