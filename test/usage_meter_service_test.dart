import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/models/usage_record.dart';
import 'package:solace/services/usage_meter_service.dart';
import 'package:solace/utils/prefs_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsHelper.warmUp();
    UsageMeterService.resetForTest();
  });

  test('超过2000条记录后，「总计」请求次数仍持续累计', () async {
    final meter = UsageMeterService.instance;

    // 灌入超过 _maxRecords(2000) 的记录
    for (var i = 0; i < 2200; i++) {
      await meter.trackHttpResponse(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: {
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        },
        response: http.Response.bytes(
          utf8.encode(
              '{"usage":{"prompt_tokens":100,"completion_tokens":50}}'),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
    }

    final summary = await meter.getSummary(UsageRange.all);
    expect(summary.requestCount, 2200);
    expect(summary.inputTokens, 2200 * 100);
    expect(summary.outputTokens, 2200 * 50);
    expect(summary.totalCost, greaterThan(0));
  });

  test('超过2000条记录后，「今日」统计不受裁剪影响', () async {
    final meter = UsageMeterService.instance;

    for (var i = 0; i < 2050; i++) {
      await meter.trackHttpResponse(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: {
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        },
        response: http.Response.bytes(
          utf8.encode(
              '{"usage":{"prompt_tokens":100,"completion_tokens":50}}'),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
    }

    final summary = await meter.getSummary(UsageRange.today);
    expect(summary.requestCount, 2050);
    expect(summary.inputTokens, 2050 * 100);
  });

  test('重启（重新加载）后累计数据不丢失', () async {
    final meter = UsageMeterService.instance;

    for (var i = 0; i < 2100; i++) {
      await meter.trackHttpResponse(
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: {
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        },
        response: http.Response.bytes(
          utf8.encode(
              '{"usage":{"prompt_tokens":100,"completion_tokens":50}}'),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
    }
    await UsageMeterService.flushForTest();

    // 模拟重启：清空内存缓存，重新加载
    UsageMeterService.resetForTest();

    final reloaded = UsageMeterService.instance;
    await reloaded.warmUp();
    final summary = await reloaded.getSummary(UsageRange.all);
    expect(summary.requestCount, 2100);
    expect(summary.inputTokens, 2100 * 100);
  });
}
