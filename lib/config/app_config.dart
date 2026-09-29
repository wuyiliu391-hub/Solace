import 'constants.dart';

class AppConfig {
  AppConfig._();

  /// 本地离线语音总开关。
  /// 推理引擎（onnxruntime .so）由用户手动导入；模型文件不内置。
  static const bool localTtsEnabled = true; // MOSS-TTS-Nano 语音合成
  static const bool localSttEnabled = true; // SenseVoice 语音转文本



  static const String appWorkerBaseUrl = 'https://solace-auth-v2.pages.dev';

  static const String websiteUrl = 'https://solace-auth-v2.pages.dev';

  /// 后台统计页（管理员用）
  static const String adminStatsUrl = '$appWorkerBaseUrl${ApiDefaults.adminStatsUrl}';

  /// 下载 API（带计数重定向）
  static const String downloadApiUrl = '$appWorkerBaseUrl${ApiDefaults.downloadApiUrl}';
}
