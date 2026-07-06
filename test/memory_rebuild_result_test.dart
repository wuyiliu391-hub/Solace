import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/memory_engine.dart';

void main() {
  group('MemoryRebuildResult', () {
    test('无历史记录时给出明确失败反馈', () {
      const result = MemoryRebuildResult(
        scannedSessions: 0,
        scannedMessages: 0,
        savedMemories: 0,
        skippedBatches: 0,
        failedBatches: 0,
      );

      expect(result.hasHistory, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.feedbackMessage, contains('没有找到该角色的历史聊天记录'));
    });

    test('有新增记忆时给出扫描和新增数量反馈', () {
      const result = MemoryRebuildResult(
        scannedSessions: 2,
        scannedMessages: 48,
        savedMemories: 7,
        skippedBatches: 1,
        failedBatches: 0,
      );

      expect(result.hasHistory, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.hasNewMemories, isTrue);
      expect(result.feedbackMessage, contains('已扫描 2 个会话、48 条历史消息'));
      expect(result.feedbackMessage, contains('新增 7 条记忆'));
    });

    test('批次失败时反馈失败数量和原因', () {
      const result = MemoryRebuildResult(
        scannedSessions: 1,
        scannedMessages: 20,
        savedMemories: 0,
        skippedBatches: 0,
        failedBatches: 2,
        errors: ['API 超时'],
      );

      expect(result.isSuccess, isFalse);
      expect(result.feedbackMessage, contains('有 2 批处理失败'));
      expect(result.feedbackMessage, contains('API 超时'));
    });
  });
}
