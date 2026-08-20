import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';

/// 白名单联系人条目。
class WxContactEntry {
  /// 微信侧联系人 ID（iLink from.id）
  final String wxId;

  /// 用户自定义备注名（用于会话展示与通知）
  final String displayName;

  const WxContactEntry({required this.wxId, required this.displayName});

  Map<String, dynamic> toMap() => {'wxId': wxId, 'displayName': displayName};

  static WxContactEntry fromMap(Map<String, dynamic> map) => WxContactEntry(
        wxId: map['wxId'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
      );
}

/// 待审批联系人（白名单外发来消息时记录，等用户批准）。
class WxPendingEntry {
  final String wxId;
  final String fromName;
  final String lastText;
  final DateTime receivedAt;

  const WxPendingEntry({
    required this.wxId,
    required this.fromName,
    required this.lastText,
    required this.receivedAt,
  });

  Map<String, dynamic> toMap() => {
        'wxId': wxId,
        'fromName': fromName,
        'lastText': lastText,
        'receivedAt': receivedAt.toIso8601String(),
      };

  static WxPendingEntry fromMap(Map<String, dynamic> map) => WxPendingEntry(
        wxId: map['wxId'] as String? ?? '',
        fromName: map['fromName'] as String? ?? '',
        lastText: map['lastText'] as String? ?? '',
        receivedAt: DateTime.tryParse(map['receivedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 微信机器人本地配置存储。
///
/// 存储先例照 MiMoTtsConfigStore（SharedPreferences 直存，项目惯例）。
/// 后台 isolate（workmanager）同样可读。
class WeChatBotStore {
  WeChatBotStore._();

  /// 官方 iLink 网关默认域名（登录响应的 baseurl 可覆盖）
  static const String defaultBaseUrl = 'https://ilinkai.weixin.qq.com';

  // ────────────── 登录态 ──────────────

  static Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(PrefKeys.wxBotToken) ?? '';
    return token.isEmpty ? null : token;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.wxBotToken, token.trim());
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.wxBotToken);
    await prefs.remove(PrefKeys.wxUpdatesBuf);
    await prefs.remove(PrefKeys.wxContextTokens);
    await prefs.remove(PrefKeys.wxIlinkBotId);
    await prefs.remove(PrefKeys.wxIlinkUserId);
  }

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(PrefKeys.wxBaseUrl) ?? '';
    return url.isEmpty ? defaultBaseUrl : url;
  }

  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.wxBaseUrl, url.trim());
  }

  /// 登录确认时服务端返回的 bot 自身 ID 与扫码者 iLink 用户 ID
  static Future<void> saveAccountInfo(
      {String? ilinkBotId, String? ilinkUserId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (ilinkBotId != null && ilinkBotId.isNotEmpty) {
      await prefs.setString(PrefKeys.wxIlinkBotId, ilinkBotId);
    }
    if (ilinkUserId != null && ilinkUserId.isNotEmpty) {
      await prefs.setString(PrefKeys.wxIlinkUserId, ilinkUserId);
    }
  }

  // ────────────── 同步游标与上下文令牌 ──────────────

  /// getUpdates 游标（官方 get_updates_buf），首次空串
  static Future<String> loadUpdatesBuf() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.wxUpdatesBuf) ?? '';
  }

  static Future<void> saveUpdatesBuf(String buf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.wxUpdatesBuf, buf);
  }

  /// 按联系人缓存 context_token（回复必须回传）
  static Future<String?> loadContextToken(String fromUserId) async {
    final map = await _loadContextTokenMap();
    return map[fromUserId];
  }

  static Future<void> saveContextToken(
      String fromUserId, String contextToken) async {
    if (contextToken.isEmpty) return;
    final map = await _loadContextTokenMap();
    if (map[fromUserId] == contextToken) return;
    map[fromUserId] = contextToken;
    // 只保留最近 200 个
    if (map.length > 200) {
      final overflow = map.length - 200;
      map.removeWhere((k, _) => map.keys.take(overflow).contains(k));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.wxContextTokens, jsonEncode(map));
  }

  static Future<Map<String, dynamic>> _loadContextTokenMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefKeys.wxContextTokens) ?? '';
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ────────────── 开关与角色绑定 ──────────────

  static Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PrefKeys.wxEnabled) ?? false;
  }

  static Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.wxEnabled, enabled);
  }

  static Future<String?> loadBoundCharacterId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(PrefKeys.wxBoundCharacterId) ?? '';
    return id.isEmpty ? null : id;
  }

  static Future<void> saveBoundCharacterId(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.wxBoundCharacterId, characterId);
  }

  // ────────────── 白名单 ──────────────

  static Future<List<WxContactEntry>> loadWhitelist() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(PrefKeys.wxWhitelist),
        WxContactEntry.fromMap);
  }

  static Future<void> saveWhitelist(List<WxContactEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        PrefKeys.wxWhitelist, jsonEncode(entries.map((e) => e.toMap()).toList()));
  }

  static Future<bool> isWhitelisted(String wxId) async {
    final list = await loadWhitelist();
    return list.any((e) => e.wxId == wxId);
  }

  /// 备注名查询；未收录时返回 null。
  static Future<String?> displayNameOf(String wxId) async {
    final list = await loadWhitelist();
    for (final e in list) {
      if (e.wxId == wxId && e.displayName.isNotEmpty) return e.displayName;
    }
    return null;
  }

  // ────────────── 待审批 ──────────────

  static Future<List<WxPendingEntry>> loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(
        prefs.getString(PrefKeys.wxPending), WxPendingEntry.fromMap);
  }

  static Future<void> savePending(List<WxPendingEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        PrefKeys.wxPending, jsonEncode(entries.map((e) => e.toMap()).toList()));
  }

  /// 记录一条白名单外来信（同一 wxId 只保留最新一条，最多 20 条）。
  static Future<void> upsertPending({
    required String wxId,
    required String fromName,
    required String lastText,
  }) async {
    final list = await loadPending();
    list.removeWhere((e) => e.wxId == wxId);
    list.insert(
      0,
      WxPendingEntry(
        wxId: wxId,
        fromName: fromName,
        lastText: lastText.length > 80 ? lastText.substring(0, 80) : lastText,
        receivedAt: DateTime.now(),
      ),
    );
    if (list.length > 20) list.removeRange(20, list.length);
    await savePending(list);
  }

  static List<T> _decodeList<T>(
      String? raw, T Function(Map<String, dynamic>) fromMap) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded
          .whereType<Map>()
          .map((e) => fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <T>[];
    }
  }
}
