import 'package:flutter_test/flutter_test.dart';
import 'package:solace/config/constants.dart';
import 'package:solace/config/business_rules.dart';

void main() {
  group('AppVersion', () {
    test('版本号格式正确', () {
      expect(AppVersion.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(AppVersion.build, isA<int>());
      expect(AppVersion.build, greaterThan(0));
    });

    test('版本号不为空', () {
      expect(AppVersion.version.isNotEmpty, true);
    });
  });

  group('IntimacyRules', () {
    test('每日上限为 5', () {
      expect(IntimacyRules.dailyCap, 5);
    });

    test('亲密等级范围 0-100', () {
      expect(IntimacyRules.maxLevel, 100);
    });

    test('decayAfterHours 为 48', () {
      expect(IntimacyRules.decayAfterHours, 48);
    });

    test('msgsPerPoint 根据等级返回正确值', () {
      expect(IntimacyRules.msgsPerPoint(0), 1);
      expect(IntimacyRules.msgsPerPoint(29), 1);
      expect(IntimacyRules.msgsPerPoint(30), 2);
      expect(IntimacyRules.msgsPerPoint(59), 2);
      expect(IntimacyRules.msgsPerPoint(60), 3);
      expect(IntimacyRules.msgsPerPoint(79), 3);
      expect(IntimacyRules.msgsPerPoint(80), 5);
    });

    test('亲密层级递增', () {
      expect(IntimacyRules.tierLow, lessThan(IntimacyRules.tierMid));
      expect(IntimacyRules.tierMid, lessThan(IntimacyRules.tierHigh));
      expect(IntimacyRules.tierHigh, lessThan(IntimacyRules.tierVeryHigh));
    });
  });

  group('EmotionEngineRules', () {
    test('情感强度范围合理', () {
      expect(EmotionEngineRules.baseIntensityMin, greaterThanOrEqualTo(0));
      expect(EmotionEngineRules.baseIntensityMax, lessThanOrEqualTo(1));
      expect(EmotionEngineRules.baseIntensityMin,
          lessThan(EmotionEngineRules.baseIntensityMax));
    });

    test('个性乘数合理', () {
      expect(EmotionEngineRules.warmMultiplier, greaterThan(1.0));
      expect(EmotionEngineRules.coolMultiplier, lessThan(1.0));
      expect(EmotionEngineRules.bouncyMultiplier, greaterThan(1.0));
    });
  });

  group('CoinRules', () {
    test('默认金币为正数', () {
      expect(CoinRules.defaultCoins, greaterThan(0));
    });

    test('消息成本为正数', () {
      expect(CoinRules.messageCost, greaterThan(0));
    });

    test('签到奖励为正数', () {
      expect(CoinRules.dailyCheckInReward, greaterThan(0));
    });

    test('AI 默认余额为正数', () {
      expect(CoinRules.aiDefaultBalance, greaterThan(0));
    });
  });

  group('SilenceRules', () {
    test('不同性格返回不同沉默时长', () {
      final active = SilenceRules.silenceSeconds('活泼');
      final warm = SilenceRules.silenceSeconds('温柔');
      final cool = SilenceRules.silenceSeconds('高冷');
      final shy = SilenceRules.silenceSeconds('害羞');
      final def = SilenceRules.silenceSeconds(null);

      expect(active, greaterThan(0));
      expect(warm, greaterThan(0));
      expect(cool, greaterThan(0));
      expect(shy, greaterThan(0));
      expect(def, greaterThan(0));
    });

    test('活泼性格沉默时间最短', () {
      final active = SilenceRules.silenceSeconds('活泼');
      final cool = SilenceRules.silenceSeconds('高冷');
      expect(active, lessThan(cool));
    });

    test('silenceTimeout 返回 Duration', () {
      final timeout = SilenceRules.silenceTimeout('活泼');
      expect(timeout, isA<Duration>());
      expect(timeout.inSeconds, greaterThan(0));
    });
  });

  group('Festivals', () {
    test('节日祝福不为空', () {
      expect(Festivals.greetings.isNotEmpty, true);
    });

    test('包含新年祝福', () {
      expect(Festivals.greetings.containsKey('01-01'), true);
    });
  });

  group('ShopDeliveryRules', () {
    test('所有状态不为空', () {
      expect(ShopDeliveryRules.allStatuses.isNotEmpty, true);
    });

    test('时间范围合理', () {
      expect(ShopDeliveryRules.pendingMinSeconds,
          lessThan(ShopDeliveryRules.pendingMaxSeconds));
      expect(ShopDeliveryRules.preparingMinSeconds,
          lessThan(ShopDeliveryRules.preparingMaxSeconds));
      expect(ShopDeliveryRules.shippingMinSeconds,
          lessThan(ShopDeliveryRules.shippingMaxSeconds));
    });
  });
}
