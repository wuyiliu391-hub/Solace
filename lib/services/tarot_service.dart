import '../models/tarot_card.dart';

/// 塔罗解牌服务 — 构造结构化 prompt 和格式化消息
class TarotService {
  TarotService._();

  /// 构造发送到聊天界面的完整消息文本
  ///
  /// 包含用户问题、牌阵信息、每张牌的位置和正逆位。
  /// 该消息会作为 initialMessage 发送到 ChatDetailScreen，由 AI 角色解读。
  static String buildTarotMessage({
    required String? userQuestion,
    required SpreadType spread,
    ThreeCardMode? threeCardMode,
    required List<TarotCard> cards,
    required List<bool> uprightFlags,
    required String characterName,
  }) {
    final buffer = StringBuffer();

    // 开头：角色称呼 + 塔罗主题
    buffer.writeln('$characterName，我们来玩塔罗牌吧！');
    buffer.writeln();

    // 用户问题（核心：让 AI 知道具体要解读什么）
    if (userQuestion != null && userQuestion.trim().isNotEmpty) {
      buffer.writeln('【我的问题】${userQuestion.trim()}');
      buffer.writeln();
    }

    // 牌阵信息
    final spreadLabel = _buildSpreadLabel(spread, threeCardMode);
    buffer.writeln('我选了「$spreadLabel」，刚刚抽了牌，你来看看：');
    buffer.writeln();

    // 每张牌的详情
    final positionNames = _getPositionNames(spread, threeCardMode);
    for (int i = 0; i < cards.length; i++) {
      final card = cards[i];
      final isUpright = uprightFlags[i];
      final positionName = i < positionNames.length ? positionNames[i] : '第${i + 1}张';
      final orientation = isUpright ? '正位 ↑' : '逆位 ↓';
      final meaning = isUpright ? card.uprightMeaning : card.reversedMeaning;
      buffer.writeln('$positionName：${card.nameCn}（$orientation）— $meaning');
    }
    buffer.writeln();

    // 解读指令（引导 AI 紧扣问题）
    if (userQuestion != null && userQuestion.trim().isNotEmpty) {
      buffer.writeln('请根据我的问题，结合每张牌在对应位置的含义，帮我做个性化解读。');
      buffer.writeln('要紧扣我的问题来分析每张牌，不要泛泛而谈，最后给我一些实用的建议。');
    } else {
      buffer.writeln('你觉得这些牌怎么样？帮我解读一下吧～');
    }

    return buffer.toString();
  }

  /// 构造牌阵标签（含解读体系）
  static String _buildSpreadLabel(SpreadType spread, ThreeCardMode? mode) {
    switch (spread) {
      case SpreadType.single:
        return '单张牌';
      case SpreadType.threeCard:
        if (mode != null) {
          return '三牌阵 · ${mode.name}（${mode.description}）';
        }
        return '三牌阵 · 时间流（过去 · 现在 · 未来）';
      case SpreadType.celticCross:
        return '五张牌阵';
    }
  }

  /// 获取位置名称列表
  static List<String> _getPositionNames(SpreadType spread, ThreeCardMode? mode) {
    if (spread == SpreadType.threeCard && mode != null) {
      return mode.positionNames;
    }
    return spread.positionNames;
  }
}