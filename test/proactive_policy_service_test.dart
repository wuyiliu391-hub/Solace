import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/proactive_policy.dart';
import 'package:solace/services/proactive_policy_service.dart';

void main() {
  final service = ProactivePolicyService();

  ProactivePolicyInput input({
    bool enabled = true,
    DateTime? now,
    int deliveredToday = 0,
    bool hasDueCommitment = false,
    bool respectsBoundary = true,
    DateTime? lastProactiveAt,
    DateTime? lastUserMessageAt,
  }) =>
      ProactivePolicyInput(
        enabled: enabled,
        frequencyHours: 2,
        now: now ?? DateTime(2026, 8, 6, 12),
        deliveredToday: deliveredToday,
        hasDueCommitment: hasDueCommitment,
        respectsBoundary: respectsBoundary,
        lastProactiveAt: lastProactiveAt,
        lastUserMessageAt: lastUserMessageAt,
      );

  test('rejects messages when the user disabled proactivity', () {
    expect(service.evaluate(input(enabled: false)).allowed, isFalse);
  });

  test('respects quiet hours unless a commitment is due', () {
    expect(service.evaluate(input(now: DateTime(2026, 8, 6, 23))).allowed,
        isFalse);
    expect(
        service
            .evaluate(
                input(now: DateTime(2026, 8, 6, 23), hasDueCommitment: true))
            .allowed,
        isTrue);
  });

  test('rejects boundary violations, daily cap and cooldown', () {
    expect(service.evaluate(input(respectsBoundary: false)).allowed, isFalse);
    expect(service.evaluate(input(deliveredToday: 2)).allowed, isFalse);
    expect(
        service
            .evaluate(input(lastProactiveAt: DateTime(2026, 8, 6, 11)))
            .allowed,
        isFalse);
  });

  test('allows a due commitment with an explicit reason', () {
    final decision = service.evaluate(input(hasDueCommitment: true));
    expect(decision.allowed, isTrue);
    expect(decision.reason, contains('兑现'));
  });
}
