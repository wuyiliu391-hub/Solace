import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/character_desire_engine.dart';
import 'package:solace/services/memory_engine.dart';
import 'package:solace/services/virtual_phone_generator.dart';
import 'package:solace/utils/global_mode_prompt.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

/// 法模式开启时的真实模式文案（走单一来源纯函数，避免测试与实现文本漂移）
String _faModePrompt(String scope) => buildGlobalModePromptText(
      pureAiMode: false,
      novelMode: false,
      loverMode: false,
      openMode: false,
      faMode: true,
      daoMode: false,
      scope: scope,
    );

void main() {
  group('虚拟手机生成器 · 法模式注入', () {
    test('法模式开启时 system prompt 包含法功能文案', () {
      final mode = _faModePrompt('虚拟手机');
      final sys = VirtualPhoneGenerator.composeSystemPrompt(mode);

      expect(sys, contains('法功能已开启'));
      expect(sys, contains(mode));
      // 固定人设指令仍完整保留
      expect(sys, contains('拟人真实感'));
    });
  });

  group('欲望画像 · 法模式注入', () {
    test('法模式开启时 system prompt 包含法功能文案', () {
      final mode = _faModePrompt('欲望画像');
      final sys = CharacterDesireEngine.composeDesireSystemPrompt(mode);

      expect(sys, contains('法功能已开启'));
      expect(sys, contains(mode));
      expect(sys, contains('你是角色动机分析器'));
    });
  });

  group('记忆摘要 · 法模式注入', () {
    // generateSummary 对 <40 字的内容直接短路，这里用足够长的素材
    final longContent = '这是一条足够长的记忆内容，长度必须超过四十个字符。' * 2;

    test('法模式开启时请求体 system 消息包含法功能文案', () async {
      final storage = _MockStorage();
      when(() => storage.buildGlobalModePrompt(scope: any(named: 'scope')))
          .thenReturn(_faModePrompt('记忆摘要'));

      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'memory summary'}
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = MemoryEngine(storage, httpClient: client);
      final result = await engine.generateSummary(
        longContent,
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        modelName: 'test-model',
      );

      expect(result, isNotNull);
      final messages = (capturedBody['messages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final systemMsg =
          messages.firstWhere((m) => m['role'] == 'system');
      expect(systemMsg['content'], contains('法功能已开启'));
    });

    test('法模式关闭时请求体 system 消息不包含法功能文案', () async {
      final storage = _MockStorage();
      when(() => storage.buildGlobalModePrompt(scope: any(named: 'scope')))
          .thenReturn(buildGlobalModePromptText(
        pureAiMode: false,
        novelMode: false,
        loverMode: false,
        openMode: false,
        faMode: false,
        daoMode: false,
        scope: '记忆摘要',
      ));

      late Map<String, dynamic> capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'memory summary'}
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = MemoryEngine(storage, httpClient: client);
      await engine.generateSummary(
        longContent,
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        modelName: 'test-model',
      );

      final messages = (capturedBody['messages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final systemMsg =
          messages.firstWhere((m) => m['role'] == 'system');
      expect(systemMsg['content'], isNot(contains('法功能已开启')));
    });
  });
}
