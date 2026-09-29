// MiMo TTS 服务测试：
// 覆盖配置模型（引擎切换/模型映射）、配置存储（SharedPreferences 读写清除）、
// 参考音频档案（sha1 指纹）、未配置 API Key 时的错误路径。
// 429 退避与真实 HTTP 合成依赖云端 API，不在单测范围（人工/集成验证）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/services/voice/mimo_tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiMoTtsConfig 配置模型', () {
    test('apiKey 为空/空白时无效', () {
      expect(const MiMoTtsConfig(apiKey: '').isValid, isFalse);
      expect(const MiMoTtsConfig(apiKey: '   ').isValid, isFalse);
      expect(const MiMoTtsConfig(apiKey: 'sk-xxx').isValid, isTrue);
    });

    test('默认引擎为 voiceclone，非预置/非设计', () {
      const config = MiMoTtsConfig(apiKey: 'sk-xxx');
      expect(config.engine, 'voiceclone');
      expect(config.usePreset, isFalse);
      expect(config.useVoicedesign, isFalse);
    });

    test('effectiveModel 按引擎映射到对应模型 ID', () {
      // 预置音色引擎 → 固定预置模型
      const preset = MiMoTtsConfig(apiKey: 'k', engine: 'preset');
      expect(preset.effectiveModel, MiMoTtsConfig.defaultPresetModel);
      expect(preset.usePreset, isTrue);

      // 音色设计引擎 → 固定设计模型
      const design = MiMoTtsConfig(apiKey: 'k', engine: 'voicedesign');
      expect(design.effectiveModel, MiMoTtsConfig.defaultDesignModel);
      expect(design.useVoicedesign, isTrue);

      // 克隆引擎 → 使用自定义 model 字段
      const clone = MiMoTtsConfig(
        apiKey: 'k',
        model: 'mimo-v2.5-tts-voiceclone-x',
      );
      expect(clone.effectiveModel, 'mimo-v2.5-tts-voiceclone-x');
    });

    test('预置音色清单只含服务端真实生效的 ID', () {
      expect(MiMoPresetVoices.all.length, 3);
      expect(
        MiMoPresetVoices.all.map((v) => v.id),
        containsAll(['mimo_default', 'Dean', 'Milo']),
      );
    });
  });

  group('MiMoTtsConfigStore 配置存储', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('未配置时 load 返回 null', () async {
      expect(await MiMoTtsConfigStore.load(), isNull);
    });

    test('save 后 load 读写一致（含 trim）', () async {
      await MiMoTtsConfigStore.save(
        ' sk-abc ',
        baseUrl: 'https://example.com/v1',
        model: 'mimo-custom',
        engine: 'preset',
        presetVoice: 'Dean',
        voiceDesignPrompt: '少年音',
      );

      final config = await MiMoTtsConfigStore.load();
      expect(config, isNotNull);
      expect(config!.apiKey, 'sk-abc'); // 已 trim
      expect(config.baseUrl, 'https://example.com/v1');
      expect(config.engine, 'preset');
      expect(config.presetVoice, 'Dean');
      expect(config.voiceDesignPrompt, '少年音');
      // preset 引擎 → effectiveModel 映射到预置模型而非 model 字段
      expect(config.effectiveModel, MiMoTtsConfig.defaultPresetModel);
    });

    test('save 省略的可选字段回退默认值', () async {
      await MiMoTtsConfigStore.save('sk-abc');
      final config = await MiMoTtsConfigStore.load();
      expect(config!.baseUrl, MiMoTtsConfig.defaultBaseUrl);
      expect(config.model, MiMoTtsConfig.defaultModel);
      expect(config.engine, 'voiceclone');
      expect(config.presetVoice, MiMoTtsConfig.presetVoices);
    });

    test('clear 后 load 返回 null（ApiKey 被移除）', () async {
      await MiMoTtsConfigStore.save('sk-abc', engine: 'preset');
      await MiMoTtsConfigStore.clear();
      expect(await MiMoTtsConfigStore.load(), isNull);
    });
  });

  group('MiMoTtsService 服务', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('未配置 API Key 时合成抛 StateError 并提示配置入口', () async {
      final service = MiMoTtsService();
      expect(
        () => service.synthesizeWithStyle('char-1', '你好'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('API Key 未配置'),
          ),
        ),
      );
    });

    test('setReferenceAudio 生成含 sha1 指纹的角色档案', () async {
      // 生成临时参考音频文件
      final dir = await Directory.systemTemp.createTemp('mimo_tts_test');
      addTearDown(() => dir.delete(recursive: true));
      final wav = File('${dir.path}/ref.wav');
      await wav.writeAsBytes(List.filled(1024, 7));

      final service = MiMoTtsService();
      final profile = await service.setReferenceAudio(
        'char-1',
        wav.path,
        '这是参考文本',
      );

      expect(profile.characterId, 'char-1');
      expect(profile.referenceAudioPath, wav.path);
      expect(profile.referenceText, '这是参考文本');
      // sha1 指纹为 40 位十六进制
      expect(profile.referenceHash, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('isModelReady 跟随配置存在性', () async {
      final service = MiMoTtsService();
      expect(await service.isModelReady, isFalse); // 未配置

      await MiMoTtsConfigStore.save('sk-abc');
      expect(await service.isModelReady, isTrue);
    });
  });
}
