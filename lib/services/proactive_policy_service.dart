import '../models/proactive_policy.dart';

/// 本地确定性闸门：模型无权绕过用户设置、静默时段或频率限制。
class ProactivePolicyService {
  static const int _dailyCap = 2;

  ProactivePolicyDecision evaluate(ProactivePolicyInput input) {
    if (!input.enabled)
      return const ProactivePolicyDecision(false, '用户未开启角色主动消息');
    if (_isQuietHour(input.now.hour) && !input.hasDueCommitment) {
      return const ProactivePolicyDecision(false, '静默时段');
    }
    if (!input.respectsBoundary) {
      return const ProactivePolicyDecision(false, '用户要求空间');
    }
    if (input.deliveredToday >= _dailyCap && !input.hasDueCommitment) {
      return const ProactivePolicyDecision(false, '已达每日主动消息上限');
    }
    final cooldown = Duration(hours: input.frequencyHours.clamp(1, 24));
    if (input.lastProactiveAt != null &&
        input.now.difference(input.lastProactiveAt!) < cooldown) {
      return const ProactivePolicyDecision(false, '主动消息冷却中');
    }
    if (input.lastUserMessageAt != null &&
        input.now.difference(input.lastUserMessageAt!) <
            const Duration(minutes: 20)) {
      return const ProactivePolicyDecision(false, '用户刚刚互动过');
    }
    return ProactivePolicyDecision(
        true, input.hasDueCommitment ? '兑现待跟进事项' : '满足主动联系条件');
  }

  bool _isQuietHour(int hour) => hour >= 23 || hour < 7;
}
