import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/life/daily_schedule.dart';

void main() {
  group('ScheduleBlock', () {
    test('contains 判断普通时间区间', () {
      const block = ScheduleBlock(
        start: '08:00',
        end: '12:00',
        activity: LifeActivity.work,
        label: '工作',
      );
      expect(block.contains('08:00'), isTrue);
      expect(block.contains('09:30'), isTrue);
      expect(block.contains('11:59'), isTrue);
      expect(block.contains('12:00'), isFalse);
      expect(block.contains('07:59'), isFalse);
      expect(block.contains('13:00'), isFalse);
    });

    test('contains 判断跨零点区间（睡眠块）', () {
      const block = ScheduleBlock(
        start: '23:00',
        end: '07:00',
        activity: LifeActivity.sleep,
        label: '睡觉',
      );
      expect(block.contains('23:00'), isTrue);
      expect(block.contains('23:59'), isTrue);
      expect(block.contains('02:00'), isTrue);
      expect(block.contains('06:59'), isTrue);
      expect(block.contains('07:00'), isFalse);
      expect(block.contains('12:00'), isFalse);
    });

    test('toMap / fromMap 往返一致', () {
      const block = ScheduleBlock(
        start: '14:00',
        end: '17:30',
        activity: LifeActivity.hobby,
        label: '打游戏',
        moodHint: 'playful',
        shareable: true,
        sharePrompt: '战况如何',
      );
      final restored = ScheduleBlock.fromMap(block.toMap());
      expect(restored, equals(block));
    });

    test('未知 activity 字符串回退到 rest', () {
      final b = ScheduleBlock.fromMap({
        'start': '09:00',
        'end': '10:00',
        'activity': 'unknown_thing',
        'label': 'X',
      });
      expect(b.activity, LifeActivity.rest);
    });
  });

  group('DailySchedule', () {
    test('toMap / fromMap 往返一致（含 blocks）', () {
      final now = DateTime(2026, 9, 10, 12);
      final schedule = DailySchedule(
        id: 's1',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        blocks: const [
          ScheduleBlock(
            start: '08:00',
            end: '12:00',
            activity: LifeActivity.work,
            label: '工作',
          ),
          ScheduleBlock(
            start: '12:00',
            end: '13:00',
            activity: LifeActivity.meal,
            label: '午饭',
            shareable: true,
            sharePrompt: '吃午饭',
          ),
        ],
        generatedAt: now,
        generatedBy: ScheduleSource.rule,
        createdAt: now,
      );
      final restored = DailySchedule.fromMap(schedule.toMap());
      expect(restored.id, 's1');
      expect(restored.characterId, 'c1');
      expect(restored.date, '2026-09-10');
      expect(restored.generatedBy, ScheduleSource.rule);
      expect(restored.blocks.length, 2);
      expect(restored.blocks[1].activity, LifeActivity.meal);
      expect(restored.blocks[1].shareable, isTrue);
    });

    test('blocks_json 为空时不抛异常', () {
      final restored = DailySchedule.fromMap({
        'id': 's2',
        'character_id': 'c2',
        'user_id': 'u2',
        'date': '2026-09-10',
        'blocks_json': '',
        'generated_at': 0,
        'generated_by': 'rule',
        'created_at': 0,
      });
      expect(restored.blocks, isEmpty);
    });

    test('blocks_json 是非法 JSON 时不抛异常', () {
      final restored = DailySchedule.fromMap({
        'id': 's3',
        'character_id': 'c3',
        'user_id': 'u3',
        'date': '2026-09-10',
        'blocks_json': '{{{invalid',
        'generated_at': 0,
        'generated_by': 'rule',
        'created_at': 0,
      });
      expect(restored.blocks, isEmpty);
    });

    test('generated_by = llm 时解析为 ScheduleSource.llm', () {
      final restored = DailySchedule.fromMap({
        'id': 's4',
        'character_id': 'c4',
        'user_id': 'u4',
        'date': '2026-09-10',
        'blocks_json': '[]',
        'generated_at': 0,
        'generated_by': 'llm',
        'created_at': 0,
      });
      expect(restored.generatedBy, ScheduleSource.llm);
    });
  });
}
