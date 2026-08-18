// 本地语音模型管理器。
//
// 硬约束：模型文件绝不内置进 APK（保持安装包体积不变），也不做 App 内自动下载。
// 模型由用户自行下载（官网 / 网盘分发包），放入同一文件夹后，App 通过
// 「手动导入」逐文件 sha1 校验并复制到应用私有目录。
// TTS 已云端化（MiMo），本地模型仅剩 STT（SenseVoice）与 VAD（Silero）。

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 模型种类。
enum VoiceModelKind { senseVoiceStt, sileroVad }

/// 单个模型文件（含落地名/来源名/大小/sha1 元数据）。
class VoiceModelFileSpec {
  /// 落地到私有目录后的文件名。
  final String localName;

  /// 分发包里的文件名（打包时加前缀防重名）。
  final String urlName;

  final int bytes;
  final String sha1;

  /// 是否为 tar.gz：导入时解包到模型目录、再删除压缩包。
  final bool extractTarGz;

  const VoiceModelFileSpec({
    required this.localName,
    required this.urlName,
    required this.bytes,
    required this.sha1,
    this.extractTarGz = false,
  });
}

/// 一个模型的完整清单。
class VoiceModelSpec {
  final VoiceModelKind kind;
  final String dirName;
  final List<VoiceModelFileSpec> files;

  const VoiceModelSpec({
    required this.kind,
    required this.dirName,
    required this.files,
  });

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

/// 模型注册表：文件名、大小、sha1 均来自本地实测（与分发包资产一一对应）。
abstract class VoiceModelRegistry {
  static const sileroVad = VoiceModelSpec(
    kind: VoiceModelKind.sileroVad,
    dirName: 'silero_vad',
    files: [
      VoiceModelFileSpec(
        localName: 'silero_vad.onnx',
        urlName: 'silero_vad.onnx',
        bytes: 643854,
        sha1: 'f7b6152f842c088fa7cc858594b5d0c1dcc1d6c9',
      ),
    ],
  );

  static const senseVoice = VoiceModelSpec(
    kind: VoiceModelKind.senseVoiceStt,
    dirName: 'sensevoice',
    files: [
      VoiceModelFileSpec(
        localName: 'model.int8.onnx',
        urlName: 'sensevoice-model.int8.onnx',
        bytes: 239233841,
        sha1: 'f9fd7aa0edc54107d1b42d5c846ffd4f1ecd1459',
      ),
      VoiceModelFileSpec(
        localName: 'tokens.txt',
        urlName: 'sensevoice-tokens.txt',
        bytes: 315894,
        sha1: '00ab0681ee4c3e278c17b26a0327e344da519815',
      ),
    ],
  );

  static VoiceModelSpec specOf(VoiceModelKind kind) => switch (kind) {
    VoiceModelKind.senseVoiceStt => senseVoice,
    VoiceModelKind.sileroVad => sileroVad,
  };
}

class VoiceModelManager {
  VoiceModelManager._();
  static final VoiceModelManager instance = VoiceModelManager._();

  Future<Directory> _modelsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'voice_models'));
  }

  /// 模型目录（即使未导入也会返回路径，供上层判断就绪状态）。
  Future<Directory> modelDir(VoiceModelKind kind) async {
    final root = await _modelsRoot();
    return Directory(p.join(root.path, VoiceModelRegistry.specOf(kind).dirName));
  }

  /// 模型是否已完整就位（所有文件存在；tar.gz 的落地目标是解包后的目录）。
  Future<bool> isReady(VoiceModelKind kind) async {
    final spec = VoiceModelRegistry.specOf(kind);
    final dir = await modelDir(kind);
    for (final f in spec.files) {
      if (f.extractTarGz) {
        // espeak-ng-data.tar.gz -> 解包为 espeak-ng-data/ 目录
        final d = Directory(
          p.join(dir.path, f.localName.replaceAll('.tar.gz', '')),
        );
        if (!await d.exists()) return false;
      } else {
        final file = File(p.join(dir.path, f.localName));
        if (!await file.exists()) return false;
        final len = await file.length();
        if (len != f.bytes) return false;
      }
    }
    return true;
  }

  /// 删除某模型，释放空间。
  Future<void> delete(VoiceModelKind kind) async {
    final dir = await modelDir(kind);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 手动导入：从用户选定的目录扫描该模型的全部文件，逐文件 sha1 校验后
  /// 复制/解包到应用私有模型目录（源文件保留，用户可自行删除分发目录）。
  ///
  /// 源文件名同时兼容「分发包名」（如 sensevoice-model.int8.onnx）与
  /// 「落地名」（如 model.int8.onnx），方便用户从不同来源获取。
  Future<VoiceModelImportResult> importFromDirectory(
    VoiceModelKind kind,
    Directory sourceDir,
  ) async {
    final spec = VoiceModelRegistry.specOf(kind);
    final dir = await modelDir(kind);
    await dir.create(recursive: true);

    final missing = <String>[];
    final verifyFailed = <String>[];
    int ok = 0;

    for (final f in spec.files) {
      final src = await _findSource(sourceDir, f);
      if (src == null) {
        missing.add(f.urlName);
        continue;
      }
      if (await _sha1Of(src) != f.sha1) {
        verifyFailed.add(f.urlName);
        continue;
      }
      final target = File(p.join(dir.path, f.localName));
      await src.copy(target.path);
      if (f.extractTarGz) {
        await _extractTarGz(target, dir);
        await target.delete();
      }
      ok++;
    }

    return VoiceModelImportResult(
      total: spec.files.length,
      ok: ok,
      missing: missing,
      verifyFailed: verifyFailed,
    );
  }

  /// 从同一目录一次性导入全部三种模型（语音通话用，共 9 个文件）。
  Future<VoiceModelImportResult> importAllFromDirectory(
    Directory sourceDir,
  ) async {
    var total = 0;
    var ok = 0;
    final missing = <String>[];
    final verifyFailed = <String>[];
    for (final kind in VoiceModelKind.values) {
      final r = await importFromDirectory(kind, sourceDir);
      total += r.total;
      ok += r.ok;
      missing.addAll(r.missing);
      verifyFailed.addAll(r.verifyFailed);
    }
    return VoiceModelImportResult(
      total: total,
      ok: ok,
      missing: missing,
      verifyFailed: verifyFailed,
    );
  }

  /// 在源目录里按多种可能文件名查找某个模型文件。
  Future<File?> _findSource(Directory dir, VoiceModelFileSpec f) async {
    for (final name in {f.urlName, f.localName}) {
      final cand = File(p.join(dir.path, name));
      if (await cand.exists()) return cand;
    }
    return null;
  }

  Future<String> _sha1Of(File f) async {
    final digest = await sha1.bind(f.openRead()).first;
    return digest.toString();
  }

  /// 解包 tar.gz 到模型目录（espeak-ng-data 约 9MB，内存内解包可接受）。
  Future<void> _extractTarGz(File archiveFile, Directory destDir) async {
    final bytes = await archiveFile.readAsBytes();
    final gunzipped = GZipDecoder().decodeBytes(bytes);
    final tar = TarDecoder().decodeBytes(gunzipped);
    for (final entry in tar) {
      if (!entry.isFile) continue;
      final outFile = File(p.join(destDir.path, entry.name));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>, flush: true);
    }
  }
}

/// 手动导入结果。
class VoiceModelImportResult {
  final int total;
  final int ok;

  /// 缺失文件的分发包名。
  final List<String> missing;

  /// sha1 校验失败（文件损坏 / 版本不对）的分发包名。
  final List<String> verifyFailed;

  const VoiceModelImportResult({
    required this.total,
    required this.ok,
    this.missing = const [],
    this.verifyFailed = const [],
  });

  bool get allOk => ok == total;
}
