import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/life/life_log.dart';

void main() {
  group('LifeLog 模型', () {
    test('toMap / fromMap 往返一致', () {
      final now = DateTime(2026, 9, 10, 14, 30);
      final log = LifeLog(
        id: 'log_1',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        time: '14:30',
        content: '刚睡醒，状态还行',
        mood: '平静',
        moodIntensity: 0.3,
        source: LifeLogSource.schedule,
        pushedToMemory: false,
        createdAt: now,
      );
      final restored = LifeLog.fromMap(log.toMap());
      expect(restored, equals(log));
    });

    test('crossVisit source 序列化为 cross_visit 并可反解析', () {
      final log = LifeLog(
        id: 'log_2',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        time: '20:00',
        content: '今天去了朋友家',
        source: LifeLogSource.crossVisit,
        createdAt: DateTime(2026, 9, 10),
      );
      final map = log.toMap();
      expect(map['source'], 'cross_visit');
      final restored = LifeLog.fromMap(map);
      expect(restored.source, LifeLogSource.crossVisit);
    });

    test('share source 序列化为 share', () {
      final log = LifeLog(
        id: 'log_3',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        time: '12:00',
        content: '午饭时间',
        source: LifeLogSource.share,
        createdAt: DateTime(2026, 9, 10),
      );
      expect(log.toMap()['source'], 'share');
    });

    test('未知 source 字符串回退到 schedule', () {
      final restored = LifeLog.fromMap({
        'id': 'log_4',
        'character_id': 'c1',
        'user_id': 'u1',
        'date': '2026-09-10',
        'time': '10:00',
        'content': 'X',
        'source': 'whatever',
        'created_at': 0,
      });
      expect(restored.source, LifeLogSource.schedule);
    });

    test('pushedToMemory 布尔与整型互转正确', () {
      final log = LifeLog(
        id: 'log_5',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        time: '10:00',
        content: 'X',
        pushedToMemory: true,
        createdAt: DateTime(2026, 9, 10),
      );
      expect(log.toMap()['pushed_to_memory'], 1);
      final restored = LifeLog.fromMap(log.toMap());
      expect(restored.pushedToMemory, isTrue);
    });

    test('copyWith 保留未修改字段', () {
      final log = LifeLog(
        id: 'log_6',
        characterId: 'c1',
        userId: 'u1',
        date: '2026-09-10',
        time: '10:00',
        content: 'X',
        createdAt: DateTime(2026, 9, 10),
      );
      final copy = log.copyWith(pushedToMemory: true);
      expect(copy.id, log.id);
      expect(copy.content, log.content);
      expect(copy.pushedToMemory, isTrue);
      expect(copy.date, log.date);
    });
  });
}
