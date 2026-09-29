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
      final rawPath = '${dir.path}/solace_update.download';
      final filePath = '${dir.path}/solace_update.apk';
      final rawFile = File(rawPath);
      final apkFile = File(filePath);

      if (await rawFile.exists()) await rawFile.delete();
      if (await apkFile.exists()) await apkFile.delete();

      final bustUrl = url.contains('?')
          ? '$url&_t=${DateTime.now().millisecondsSinceEpoch}'
          : '$url?_t=${DateTime.now().millisecondsSinceEpoch}';
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(bustUrl));
        // 避免中间层用 br/zstd 等我们不好处理的编码
        request.headers['Accept-Encoding'] = 'identity';
        final response = await client.send(request);

        if (response.statusCode != 200) {
          throw Exception('Download failed: ${response.statusCode}');
        }

        int contentLength = response.contentLength ?? -1;
        if (contentLength <= 0) {
          try {
            final headResp =
                await http.head(Uri.parse(bustUrl)).timeout(const Duration(seconds: 5));
            final cl = headResp.headers['content-length'];
            if (cl != null) contentLength = int.tryParse(cl) ?? -1;
          } catch (_) {}
        }

        final sink = rawFile.openWrite();
        int received = 0;
        int lastReportedBytes = -1;
        const reportThreshold = 256 * 1024;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null &&
              (received - lastReportedBytes) >= reportThreshold) {
            lastReportedBytes = received;
            if (contentLength > 0) {
              onProgress((received / contentLength).clamp(0.0, 0.99));
            } else {
              // 无 Content-Length：传已下载字节数，UI 显示 MB
              onProgress(received.toDouble());
            }
          }
        }
        await sink.close();

        if (received < 1024 * 100) {
          throw Exception('APK 文件过小($received bytes)，下载可能失败');
        }

        final rawBytes = await rawFile.readAsBytes();
        final contentEncoding =
            (response.headers['content-encoding'] ?? '').toLowerCase();
        final looksGzip = rawBytes.length >= 2 &&
            rawBytes[0] == 0x1f &&
            rawBytes[1] == 0x8b;
        final isGzipPayload = looksGzip ||
            contentEncoding.contains('gzip') ||
            bustUrl.contains('.apk.gz') ||
            (response.request?.url.path.contains('.apk.gz') ?? false);

        List<int> apkBytes = rawBytes;
        if (isGzipPayload) {
          try {
            apkBytes = gzip.decode(rawBytes);
            debugPrint(
                'APK download: gzip 解压 ${rawBytes.length} → ${apkBytes.length} bytes');
          } catch (e) {
            throw Exception('APK gzip 解压失败: $e');
          }
        }

        // APK 本质是 ZIP，必须以 PK 开头
        if (apkBytes.length < 4 ||
            apkBytes[0] != 0x50 ||
            apkBytes[1] != 0x4b) {
          final head = apkBytes
              .take(8)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          throw Exception('APK 校验失败（非 ZIP 格式），文件头: $head');
        }

        await apkFile.writeAsBytes(apkBytes, flush: true);
        if (await rawFile.exists()) {
          await rawFile.delete();
        }
        onProgress?.call(1.0);
        return filePath;
      } finally {
        client.close();
      }
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
