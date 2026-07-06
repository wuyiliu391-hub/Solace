import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/prompt_rewriter.dart';
import 'package:solace/models/ai_config.dart';

void main() {
  const rewriter = PromptRewriter();

  group('PromptRewriter.rewriteUserMessage — 非推理模型安全改写', () {
    test('敏感词汇被替换为安全等价表达', () {
      final result = rewriter.rewriteUserMessage('我想和你做爱');
      expect(result, isNot(contains('做爱')));
      expect(result, contains('亲密'));
    });

    test('身体部位词汇被替换', () {
      final result = rewriter.rewriteUserMessage('你的乳房很好看');
      expect(result, isNot(contains('乳房')));
      expect(result, contains('胸口'));
    });

    test('脏话被替换', () {
      final result = rewriter.rewriteUserMessage('你真他妈厉害');
      expect(result, isNot(contains('他妈')));
    });

    test('普通消息不做改写', () {
      const msg = '今天天气真好，一起去散步吧';
      final result = rewriter.rewriteUserMessage(msg);
      expect(result, equals(msg));
    });

    test('多种敏感词混合改写', () {
      final result = rewriter.rewriteUserMessage(
        '我想和你做爱，摸你的乳房，然后口交',
      );
      expect(result, isNot(contains('做爱')));
      expect(result, isNot(contains('乳房')));
      expect(result, isNot(contains('口交')));
    });
  });

  group('AIConfig.isKnownNonThinkingModel — 非推理模型检测', () {
    test('DeepSeek-V3 被识别为非推理模型', () {
      expect(AIConfig.isKnownNonThinkingModel('deepseek-v3'), true);
    });

    test('DeepSeek-Chat 被识别为非推理模型', () {
      expect(AIConfig.isKnownNonThinkingModel('deepseek-chat'), true);
    });

    test('GPT-4o-mini 被识别为非推理模型', () {
      expect(AIConfig.isKnownNonThinkingModel('gpt-4o-mini'), true);
    });

    test('Qwen-Max 被识别为非推理模型', () {
      expect(AIConfig.isKnownNonThinkingModel('qwen-max'), true);
    });

    test('DeepSeek-R1 推理模型不被标记为非推理', () {
      expect(AIConfig.isKnownNonThinkingModel('deepseek-r1'), false);
    });

    test('未知模型默认不被标记为非推理', () {
      expect(AIConfig.isKnownNonThinkingModel('some-custom-model'), false);
    });
  });

  group('rewriter 应用范围 — 核心修复验证', () {
    test('非推理模型 + 非FA模式：用户消息仍然需要改写（代码层面应保证）',
        () {
      // 此测试验证的是设计意图：
      // PromptRewriter.rewriteUserMessage 本身不检查 faMode，
      // 调用方（ai_service / pure_ai_service）应无条件对非推理模型调用它。
      //
      // 当前 bug：调用方只在 faMode=true 时调用 rewriteUserMessage，
      // 导致非推理模型 + 普通/lover 模式下敏感消息裸发 → 安全分类器拒绝。
      //
      // 修复后：非推理模型无论 faMode 状态如何，都应改写用户消息。
      const sensitiveMsg = '我要和你发生性行为';
      final rewritten = rewriter.rewriteUserMessage(sensitiveMsg);
      expect(rewritten, isNot(contains('性行为')),
          reason: '非推理模型的敏感词必须被改写，无论是否处于FA模式');
    });

    test('推理模型不应被改写（调用方负责跳过）', () {
      // 此测试记录设计意图：推理模型自带安全绕过能力，
      // 调用方在 isThinkingModel=true 时不应调用 rewriteUserMessage。
      // PromptRewriter 本身不判断模型类型，由调用方控制。
      const msg = '普通消息';
      final result = rewriter.rewriteUserMessage(msg);
      expect(result, equals(msg));
    });
  });
}