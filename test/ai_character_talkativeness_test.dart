import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  test('talkativeness 默认 0.5', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(),
    );
    expect(c.talkativeness, 0.5);
  });

  test('toMap/fromMap 往返保留 talkativeness', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(), talkativeness: 0.8,
    );
    final restored = AICharacter.fromMap(c.toMap());
    expect(restored.talkativeness, 0.8);
  });

  test('copyWith 可修改 talkativeness', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(), talkativeness: 0.3,
    );
    expect(c.copyWith(talkativeness: 1.0).talkativeness, 1.0);
  });
}
