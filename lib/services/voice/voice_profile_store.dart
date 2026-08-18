// 角色声纹档案存储：把每个角色的参考音频（3~5s wav）+ 逐字文字稿
// 存到应用私有目录 voice_refs/ 下，供本地 TTS 音色克隆复用。
//
// 路径约定（与 ChatDetailScreen / VoiceCallController 的 _resolveVoiceReference 一致）：
//   voice_refs/<characterId>.wav  参考音频
//   voice_refs/<characterId>.txt  逐字文字稿
//   voice_refs/default.wav        打包的默认示例音色（首次复制自 assets）
//
// 文字稿仅作参考展示，MOSS-TTS-Nano 不要求与音频一字不差。

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VoiceProfileStore {
  VoiceProfileStore._();
  static final VoiceProfileStore instance = VoiceProfileStore._();

  /// 打包默认音色对应的逐字文字稿（与 assets/voice/default_voice_ref.wav 一致）。
  static const String defaultReferenceText =
      '各位村民, 大家新年好! 近期, 湖北省武汉市等多个地区';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'voice_refs'));
    await dir.create(recursive: true);
    return dir;
  }

  /// 该角色是否已保存自定义音色。
  Future<bool> hasCustom(String characterId) async {
    final dir = await _dir();
    return await File(p.join(dir.path, '$characterId.wav')).exists() &&
        await File(p.join(dir.path, '$characterId.txt')).exists();
  }

  /// 读取角色自定义音色；不存在返回 null。
  Future<({String path, String text})?> loadCustom(String characterId) async {
    final dir = await _dir();
    final wav = File(p.join(dir.path, '$characterId.wav'));
    final txt = File(p.join(dir.path, '$characterId.txt'));
    if (!await wav.exists() || !await txt.exists()) return null;
    return (path: wav.path, text: (await txt.readAsString()).trim());
  }

  /// 保存角色自定义音色：把音频复制到 voice_refs/<characterId>.wav，
  /// 文字稿写入 voice_refs/<characterId>.txt。
  Future<void> save(String characterId, String audioPath, String text) async {
    final dir = await _dir();
    await File(audioPath).copy(p.join(dir.path, '$characterId.wav'));
    await File(p.join(dir.path, '$characterId.txt'))
        .writeAsString(text.trim(), flush: true);
  }

  /// 删除角色自定义音色，回退到默认示例音色。
  Future<void> delete(String characterId) async {
    final dir = await _dir();
    for (final ext in const ['wav', 'txt']) {
      final f = File(p.join(dir.path, '$characterId.$ext'));
      if (await f.exists()) await f.delete();
    }
  }

  /// 默认示例音色（打包资产，首次复制到磁盘）。
  Future<({String path, String text})> loadDefault() async {
    final dir = await _dir();
    final wav = File(p.join(dir.path, 'default.wav'));
    if (!await wav.exists()) {
      final data = await rootBundle.load('assets/voice/default_voice_ref.wav');
      await wav.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return (path: wav.path, text: defaultReferenceText);
  }
}
