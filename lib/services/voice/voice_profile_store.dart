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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_converter_service.dart';

class VoiceProfileStore {
  VoiceProfileStore._();
  static final VoiceProfileStore instance = VoiceProfileStore._();

  /// 打包默认音色对应的逐字文字稿（与 assets/voice/default_voice_ref.wav 一致）。
  static const String defaultReferenceText =
      '各位村民, 大家新年好! 近期, 湖北省武汉市等多个地区';

  /// 有效 WAV 的最小体积（标准 WAV 头 44 字节）。曾经出现过 0 字节坏文件
  /// 被当作有效音色传给 MiMo TTS，base64 载荷为空导致所有请求 400
  /// （Param Incorrect: audio.voice must be a valid DataURL）——所有读取
  /// 路径都必须过滤掉这种文件。
  static const int _minValidWavBytes = 44;

  Future<bool> _isValidWav(File f) async {
    if (!await f.exists()) return false;
    final len = await f.length();
    if (len >= _minValidWavBytes) return true;
    debugPrint('[VoiceProfile] 忽略损坏的参考音频(仅 $len 字节): ${f.path}');
    return false;
  }

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'voice_refs'));
    await dir.create(recursive: true);
    return dir;
  }

  /// 该角色是否已保存自定义音色。
  Future<bool> hasCustom(String characterId) async {
    final dir = await _dir();
    final wav = File(p.join(dir.path, '$characterId.wav'));
    final txt = File(p.join(dir.path, '$characterId.txt'));
    return await _isValidWav(wav) && await txt.exists();
  }

  /// 读取角色自定义音色；不存在或已损坏（空文件）返回 null，调用方回退默认音色。
  /// 旧版遗留的不合规样本（48kHz 立体声 / 超长）自动规范化为
  /// 24kHz 单声道 ≤6s 后覆盖原文件——声纹规格不对齐会让 MiMo 音色克隆
  /// 严重偏移、人机感重。
  Future<({String path, String text})?> loadCustom(String characterId) async {
    final dir = await _dir();
    final wav = File(p.join(dir.path, '$characterId.wav'));
    final txt = File(p.join(dir.path, '$characterId.txt'));
    if (!await _isValidWav(wav) || !await txt.exists()) return null;

    final spec = _wavSpec(wav.path);
    if (spec != null &&
        (spec.sampleRate != 24000 ||
            spec.channels != 1 ||
            spec.durationSec > 6.5)) {
      try {
        debugPrint('[VoiceProfile] 规范化旧参考音频: 原=${spec.sampleRate}Hz/'
            '${spec.channels}ch/${spec.durationSec.toStringAsFixed(1)}s → 24000Hz/1ch/≤6s');
        final normalized = await AudioConverterService.instance
            .normalizeReferenceAudio(wav.path, maxSeconds: 6);
        final nf = File(normalized);
        if (await nf.exists()) {
          await nf.copy(wav.path); // 覆盖原文件，保持 voice_refs/<id>.wav 约定
        }
      } catch (e) {
        debugPrint('[VoiceProfile] 参考音频规范化失败（沿用原文件）: $e');
      }
    }

    return (path: wav.path, text: (await txt.readAsString()).trim());
  }

  /// 读 wav 头返回（采样率/声道/时长秒）；非合法 wav 头返回 null。
  /// 头布局：22=声道(u16)、24=采样率(u32)、40=data 块大小(u32)。
  ({int sampleRate, int channels, double durationSec})? _wavSpec(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.length < 44) return null;
      final d = ByteData.sublistView(bytes);
      final channels = d.getUint16(22, Endian.little);
      final sampleRate = d.getUint32(24, Endian.little);
      final dataSize = d.getUint32(40, Endian.little);
      if (channels <= 0 || sampleRate <= 0 || dataSize <= 0) return null;
      return (
        sampleRate: sampleRate,
        channels: channels,
        durationSec: dataSize / (sampleRate * channels * 2),
      );
    } catch (_) {
      return null;
    }
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

  /// 角色是否选择了内置预置音色（preset_<id>.txt 存在即生效）。
  Future<bool> hasPreset(String characterId) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, 'preset_$characterId.txt'));
    return await f.exists();
  }

  /// 读取角色预置音色 ID；未设置返回 null。
  Future<String?> loadPreset(String characterId) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, 'preset_$characterId.txt'));
    if (!await f.exists()) return null;
    final id = (await f.readAsString()).trim();
    return id.isEmpty ? null : id;
  }

  /// 保存/切换角色预置音色（会删除参考音频，避免冲突）。
  Future<void> savePreset(String characterId, String voiceId) async {
    final dir = await _dir();
    await File(p.join(dir.path, 'preset_$characterId.txt'))
        .writeAsString(voiceId.trim(), flush: true);
    for (final ext in const ['wav', 'txt']) {
      final f = File(p.join(dir.path, '$characterId.$ext'));
      if (await f.exists()) await f.delete();
    }
  }

  /// 清除角色预置音色（回退参考音频/默认音色）。
  Future<void> deletePreset(String characterId) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, 'preset_$characterId.txt'));
    if (await f.exists()) await f.delete();
  }

  /// 默认示例音色（打包资产，首次复制到磁盘；已存在但损坏时自愈重拷）。
  Future<({String path, String text})> loadDefault() async {
    final dir = await _dir();
    final wav = File(p.join(dir.path, 'default.wav'));
    if (!await _isValidWav(wav)) {
      final data = await rootBundle.load('assets/voice/default_voice_ref.wav');
      await wav.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      debugPrint('[VoiceProfile] 默认音色已(重新)复制自 assets: ${wav.path} '
          '(${data.lengthInBytes} 字节)');
    }
    return (path: wav.path, text: defaultReferenceText);
  }
}
