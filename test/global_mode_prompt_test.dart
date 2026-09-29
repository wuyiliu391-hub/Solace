import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/global_mode_prompt.dart';

void main() {
  group('buildGlobalModePromptText', () {
    test('无模式开启时输出默认提示', () {
      final text = buildGlobalModePromptText(
        pureAiMode: false,
        novelMode: false,
        loverMode: false,
        openMode: false,
        faMode: false,
        daoMode: false,
      );
      expect(text, contains('【全局模式规则 · AI回复】'));
      expect(text, contains('未开启特殊模式'));
      expect(text, isNot(contains('小说模式已开启')));
    });

    test('纯AI视角立即返回，不含其他模式分支', () {
      final text = buildGlobalModePromptText(
        pureAiMode: true,
        novelMode: true,
        loverMode: true,
        openMode: true,
        faMode: true,
        daoMode: true,
      );
      expect(text, contains('纯AI视角模式已开启'));
      expect(text, isNot(contains('小说模式已开启')));
      expect(text, isNot(contains('未开启特殊模式')));
    });

    test('各模式独立注入对应分支', () {
      final text = buildGlobalModePromptText(
        pureAiMode: false,
        novelMode: true,
        loverMode: false,
        openMode: false,
        faMode: false,
        daoMode: false,
      );
      expect(text, contains('小说模式已开启'));
      expect(text, isNot(contains('刀模式已开启')));
      expect(text, isNot(contains('恋人模式已开启')));
    });

    test('scope 参数透传', () {
      final text = buildGlobalModePromptText(
        pureAiMode: false,
        novelMode: false,
        loverMode: false,
        openMode: false,
        faMode: false,
        daoMode: false,
        scope: '后台AI任务',
      );
      expect(text, contains('【全局模式规则 · 后台AI任务】'));
    });
  });
}
