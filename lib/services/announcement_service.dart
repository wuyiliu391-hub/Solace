import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/announcement.dart';

class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._();
  factory AnnouncementService() => _instance;
  AnnouncementService._();

  static const String _lastSeenAnnouncementKey = PrefKeys.lastSeenAnnouncementId;

  /// 公告服务域名已注销，暂不拉取；待新域名配置好后恢复。
  Future<List<Announcement>> fetchAnnouncements() async => [];

  /// 标记所有公告为已读
  Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenAnnouncementKey, 'all_seen');
  }
}
