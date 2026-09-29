import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  AICharacter base() => AICharacter(
        id: 'c1',
        name: '小夜',
        personality: '冷静',
        coreDesire: '陪伴',
        moralBoundary: '',
        createdAt: DateTime(2026, 1, 1),
      );

  test('colorHex 默认 null', () {
    expect(base().colorHex, isNull);
  });

  test('colorHex 可构造与 copyWith', () {
    final c = base().copyWith(colorHex: '#E53935');
    expect(c.colorHex, '#E53935');
    expect(c.copyWith(clearColorHex: true).colorHex, isNull);
  });

  test('toMap/fromMap 往返保留 colorHex', () {
    final c = base().copyWith(colorHex: 'E53935');
    final round = AICharacter.fromMap(c.toMap());
    expect(round.colorHex, 'E53935');
    expect(AICharacter.fromMap(base().toMap()).colorHex, isNull);
  });

  test('fromMap 兼容无 colorHex 的旧数据', () {
    final map = base().toMap()..remove('colorHex');
    expect(AICharacter.fromMap(map).colorHex, isNull);
  });
}
