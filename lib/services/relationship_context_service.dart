import '../models/relationship_context.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/sentiment_analyzer.dart';

/// 维护用户与某个角色之间可持续、可解释的关系状态。
class RelationshipContextService {
  final LocalStorageRepository _storage;

  RelationshipContextService(this._storage);

  Future<RelationshipContext> updateFromUserMessage({
    required String chatId,
    required String message,
    required SentimentResult sentiment,
  }) async {
    final current = await _storage.getRelationshipContext(chatId) ??
        RelationshipContext(chatId: chatId, updatedAt: DateTime.now());
    final text = message.trim();
    final now = DateTime.now();
    var next = current.copyWith(updatedAt: now);

    if (_matches(text, ['不想谈', '别问', '不要再问', '让我静静', '需要空间'])) {
      next = next.copyWith(
        trust: current.trust + 0.03,
        boundary: '用户暂时不想谈这个话题，需要空间；除非用户主动提起，不要追问或主动联系。',
        clearConflict: true,
      );
    } else if (_matches(text, ['没考好', '考砸了', '失败了', '没通过', '不顺利'])) {
      next = next.copyWith(
        trust: current.trust + 0.05,
        recentImportantEvent: _preview('用户分享了未如愿的结果：$text'),
      );
    } else if (_matches(text, ['考完了', '结束了', '完成了', '结果出来了', '成绩出来了'])) {
      next = next.copyWith(
        trust: current.trust + 0.04,
        recentImportantEvent: _preview('用户回来了反馈之前的重要事项：$text'),
      );
    } else if (_matches(text, ['对不起', '抱歉', '是我不好', '我错了'])) {
      next = next.copyWith(
        trust: current.trust + 0.08,
        clearConflict: true,
        recentImportantEvent: _preview('用户尝试修复关系：$text'),
      );
    } else if (_matches(text, ['讨厌你', '别烦', '走开', '不想理你', '你好烦'])) {
      next = next.copyWith(
        trust: current.trust - 0.12,
        unresolvedConflict: _preview('用户表达了排斥或不满：$text'),
      );
    } else if (_matches(text, ['难过', '崩溃', '害怕', '压力很大', '好累', '委屈'])) {
      next = next.copyWith(
        trust: current.trust + 0.06,
        recentImportantEvent: _preview('用户分享了脆弱时刻：$text'),
      );
    } else if (_matches(text, ['嗯', '哦', '随便', '算了']) ||
        sentiment.type == SentimentType.veryNegative) {
      next = next.copyWith(trust: current.trust - 0.02);
    }

    await _storage.saveRelationshipContext(next);
    return next;
  }

  String buildPrompt(RelationshipContext context) {
    final lines = <String>[
      '【你们现在的关系】',
      '信任感：${(context.trust * 100).round()}%'
    ];
    if (context.boundary?.isNotEmpty == true)
      lines.add('已确认边界：${context.boundary}');
    if (context.unresolvedConflict?.isNotEmpty == true) {
      lines.add('尚未修复的矛盾：${context.unresolvedConflict}');
    }
    if (context.recentImportantEvent?.isNotEmpty == true) {
      lines.add('最近重要经历：${context.recentImportantEvent}');
    }
    lines.add('这些是你们真实互动留下的状态。尊重边界，不要编造和解、结果或共同经历。');
    return lines.join('\n');
  }

  bool _matches(String text, List<String> values) => values.any(text.contains);

  String _preview(String text) =>
      text.length > 100 ? '${text.substring(0, 100)}...' : text;
}
