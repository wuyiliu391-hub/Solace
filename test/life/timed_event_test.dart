import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/life/timed_event.dart';

void main() {
  group('TimedEvent', () {
    test('toMap / fromMap 往返一致', () {
      final now = DateTime(2026, 9, 10);
      final ev = TimedEvent(
        id: 'evt_1',
        characterId: 'c1',
        userId: 'u1',
        eventType: TimedEventType.birthday,
        title: '生日',
        date: '2026-09-10',
        recurring: true,
        reminderDays: 3,
        firedAt: null,
        createdAt: now,
      );
      final restored = TimedEvent.fromMap(ev.toMap());
      expect(restored, equals(ev));
    });

    test('isToday 判断一次性事件', () {
      final ev = TimedEvent(
        id: 'evt_1',
        characterId: 'c1',
        userId: 'u1',
        eventType: TimedEventType.custom,
        title: '一次性',
        date: '2026-09-10',
        recurring: false,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(ev.isToday(DateTime(2026, 9, 10)), isTrue);
      expect(ev.isToday(DateTime(2026, 9, 11)), isFalse);
      // 下一年不算（非重复）
      expect(ev.isToday(DateTime(2027, 9, 10)), isFalse);
    });

    test('isToday 判断重复事件（每年同月日）', () {
      final ev = TimedEvent(
        id: 'evt_2',
        characterId: 'c1',
        userId: 'u1',
        eventType: TimedEventType.anniversary,
        title: '周年',
        date: '2020-03-15',
        recurring: true,
        createdAt: DateTime(2020, 3, 15),
      );
      expect(ev.isToday(DateTime(2026, 3, 15)), isTrue);
      expect(ev.isToday(DateTime(2030, 3, 15)), isTrue);
      expect(ev.isToday(DateTime(2030, 3, 16)), isFalse);
    });

    test('isWithin 未来 N 天判断', () {
      final ev = TimedEvent(
        id: 'evt_3',
        characterId: 'c1',
        userId: 'u1',
        eventType: TimedEventType.festival,
        title: '节日',
        date: '2026-09-15',
        createdAt: DateTime(2026, 9, 1),
      );
      final now = DateTime(2026, 9, 10);
      // isWithin(now, N) 检查 [now, now+N-1]，9-15 需要 N >= 6 才覆盖
      expect(ev.isWithin(now, 5), isFalse);
      expect(ev.isWithin(now, 6), isTrue);
      expect(ev.isWithin(now, 3), isFalse);
    });

    test('copyWith clearFiredAt 清空 firedAt', () {
      final ev = TimedEvent(
        id: 'evt_4',
        characterId: 'c1',
        userId: 'u1',
        eventType: TimedEventType.custom,
        title: 'X',
        date: '2026-09-10',
        firedAt: 123456,
        createdAt: DateTime(2026, 1, 1),
      );
      final cleared = ev.copyWith(clearFiredAt: true);
      expect(cleared.firedAt, isNull);
    });

    test('未知 event_type 字符串回退到 custom', () {
      final restored = TimedEvent.fromMap({
        'id': 'evt_5',
        'character_id': 'c1',
        'user_id': 'u1',
        'event_type': 'unknown',
        'title': 'X',
        'date': '2026-01-01',
        'created_at': 0,
      });
      expect(restored.eventType, TimedEventType.custom);
    });
  });
}
