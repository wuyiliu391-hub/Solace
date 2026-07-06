import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../config/app_config.dart';
import '../config/constants.dart';
import '../utils/response_decoder.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final int buildNumber;
  final int minSdk;
  final String downloadUrl;
  final List<String> changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.buildNumber,
    required this.minSdk,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      hasUpdate: json['hasUpdate'] as bool? ?? false,
      latestVersion: json['latestVersion'] as String? ?? '',
      buildNumber: json['buildNumber'] as int? ?? 0,
      minSdk: json['minSdk'] as int? ?? 23,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      changelog: (json['changelog'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      forceUpdate: json['forceUpdate'] as bool? ?? false,
    );
  }
}

class UpdateService {
  static final UpdateService _instance = UpdateService._();
  factory UpdateService() => _instance;
  UpdateService._();

  UpdateInfo? _cachedInfo;
  UpdateInfo? get cachedInfo => _cachedInfo;

  String get _versionUrl => '${AppConfig.appWorkerBaseUrl}/api/v1/version';

  Future<UpdateInfo> checkForUpdate({
    required String currentVersion,
    required int currentBuild,
  }) async {
    try {
      final uri = Uri.parse('$_versionUrl?current=$currentVersion&build=$currentBuild');
      final response = await http.get(uri).timeout(AppDurations.updateCheck);

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final info = UpdateInfo.fromJson(json);
        _cachedInfo = info;
        return info;
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }

    return UpdateInfo(
      hasUpdate: false,
      latestVersion: currentVersion,
      buildNumber: currentBuild,
      minSdk: 23,
      downloadUrl: '',
      changelog: [],
      forceUpdate: false,
    );
  }

  Future<String?> downloadApk({
    required String url,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/solace_update.apk';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      final bustUrl = url.contains('?') ? '$url&_t=${DateTime.now().millisecondsSinceEpoch}' : '$url?_t=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.Client().send(
        http.Request('GET', Uri.parse(bustUrl)),
      );

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      // 尝试从 Content-Length 或 URL 推断文件大小
      int contentLength = response.contentLength ?? -1;
      // Cloudflare Workers 的 .apk.gz 通常 ~17MB，如果没 Content-Length 就用这个估算
      if (contentLength <= 0) {
        // 尝试 HEAD 请求获取 Content-Length
        try {
          final headResp = await http.head(Uri.parse(bustUrl)).timeout(const Duration(seconds: 5));
          final cl = headResp.headers['content-length'];
          if (cl != null) contentLength = int.tryParse(cl) ?? -1;
        } catch (_) {}
      }

      final sink = file.openWrite();
      int received = 0;
      int lastReportedBytes = -1;
      final reportThreshold = 256 * 1024; // 每 256KB 报告一次

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && (received - lastReportedBytes) >= reportThreshold) {
          lastReportedBytes = received;
          if (contentLength > 0) {
            onProgress(received / contentLength);
          } else {
            // 无 Content-Length：传正数表示已下载字节数，UI 显示 MB
            onProgress(received.toDouble());
          }
        }
      }

      await sink.close();
      return filePath;
    } catch (e) {
      debugPrint('APK download failed: $e');
      return null;
    }
  }

  Future<bool> installApk(String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('APK install failed: $e');
      return false;
    }
  }

  Future<bool> canRequestPackageInstalls() async {
    try {
      final result = await _settingsChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return result ?? false;
    } catch (e) {
      debugPrint('canRequestPackageInstalls failed: $e');
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      await _settingsChannel.invokeMethod('openAppSettings');
      return true;
    } catch (e) {
      debugPrint('openAppSettings failed: $e');
      return false;
    }
  }

  Future<bool> openInstallSourceSettings() async {
    try {
      await _settingsChannel.invokeMethod('openInstallSourceSettings');
      return true;
    } catch (e) {
      debugPrint('openInstallSourceSettings failed: $e');
      return false;
    }
  }

  static final _settingsChannel =
      MethodChannel(MethodChannels.settings);

  String get versionUrl => _versionUrl;
}
