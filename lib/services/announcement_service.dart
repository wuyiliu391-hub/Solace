import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../config/constants.dart';
import '../models/announcement.dart';
import '../utils/response_decoder.dart';

class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._();
  factory AnnouncementService() => _instance;
  AnnouncementService._();

  String get _announcementsUrl => '${AppConfig.appWorkerBaseUrl}/api/v1/announcements';
  static const String _lastSeenAnnouncementKey = PrefKeys.lastSeenAnnouncementId;

  /// 获取所有活跃公告
  Future<List<Announcement>> fetchAnnouncements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenId = prefs.getString(_lastSeenAnnouncementKey) ?? '';

      final uri = Uri.parse('$_announcementsUrl?lastId=$lastSeenId');
      final response = await http.get(uri).timeout(AppDurations.announcementFetch);

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
        final List<dynamic> jsonList = jsonDecode(decoded) as List<dynamic>;
        final announcements = jsonList
            .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
            .toList();

        // 更新最后看到的公告 ID
        if (announcements.isNotEmpty) {
          await prefs.setString(
            _lastSeenAnnouncementKey,
            announcements.first.id,
          );
        }

        return announcements;
      }
    } catch (e) {
      debugPrint('Announcement fetch failed: $e');
    }
    return [];
  }

  /// 标记所有公告为已读
  Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenAnnouncementKey, 'all_seen');
  }
}
