import 'constants.dart';

class AppConfig {
  AppConfig._();
  static const String appWorkerBaseUrl = 'https://solace-auth-v2.pages.dev';

  static const String websiteUrl = 'https://solace-auth-v2.pages.dev';

  /// 后台统计页（管理员用）
  static const String adminStatsUrl = '$appWorkerBaseUrl${ApiDefaults.adminStatsUrl}';

  /// 下载 API（带计数重定向）
  static const String downloadApiUrl = '$appWorkerBaseUrl${ApiDefaults.downloadApiUrl}';
}
