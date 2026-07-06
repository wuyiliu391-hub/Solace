import '../../models/chat_message.dart';
import '../../utils/message_sanitizer.dart';
import '../../services/builtin_sticker_service.dart';

/// ChatBloc 的纯工具方法 mixin
/// 不依赖 BLoC 状态，仅做数据转换和判断
mixin ChatBlocUtils {
  static final RegExp aiRefusalPattern = RegExp(
    r'抱歉|对不起|我不能|我无法|无法继续|不能继续|不能满足|无法满足|'
    r'不适合|不合适|不便继续|不能扮演|继续扮演|任何性行为|性行为|'
    r'违反.*(?:政策|规定|准则)|不被允许|超出.*范围|作为.*(?:AI|语言模型|人工智能)|'
    r'换个话题|提供其他.*(?:请求|话题)|不能生成|无法生成|'
    r'不能继续扮演|无法扮演此角色|不能.*角色扮演|安全.*限制|内容.*政策|'
    r'不.*(?:适当|适宜|合适).*内容|涉及.*(?:敏感|不当)|需要.*(?:遵守|遵循).*(?:准则|规定)',
    caseSensitive: false,
  );

  /// 判断 AI 回复是否为拒绝模板
  bool isAIRefusal(String content) {
    final text = MessageSanitizer.sanitizeFinal(content).trim();
    if (text.isEmpty) return false;
    return aiRefusalPattern.hasMatch(text);
  }

  /// AI 拒绝时的兜底回复
  String fallbackForRefusal(String userMessage) {
    final trimmed = userMessage.trim();
    if (trimmed.length <= 8) {
      return '我听见了，先别急，慢慢跟我说。';
    }
    return '我有点卡住了，但我还在听你说。我们先顺着现在的感觉慢慢来。';
  }

  /// 从用户消息中移除"系统提示"指令部分
  String stripSystemDirective(String text) {
    final patterns = [
      RegExp(r'系统提示[:：]\s*.+', caseSensitive: false),
      RegExp(r'系统提示\s+.+', caseSensitive: false),
    ];
    String cleaned = text;
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned.trim();
  }

  /// 标准化裸贴纸标签
  String normalizeBareStickerTags(String text) {
    final pattern = RegExp(r'(?<!\[)表情包:(\d+)(?!\])');
    return text.replaceAllMapped(pattern, (m) => '[STICK:${m[1]}]');
  }

  /// 标准化文本用于重新生成比较
  String normalizeForRegenerationCompare(String text) {
    return MessageSanitizer.sanitizeFinal(text)
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、,.!?；;：:（）()""\[\]【】]'), '');
  }

  /// 格式化 AI 错误为用户友好消息
  String formatAiError(Object error) {
    final err = error.toString();
    if (err.contains('请求过于频繁') || err.contains('429')) {
      return '消息发送太频繁了，请稍等几秒再试';
    }
    if (err.contains('服务器繁忙') || err.contains('503') || err.contains('502')) {
      return '服务暂时开小差了，正在修复中，请稍后重试';
    }
    if (err.contains('网络请求失败') || err.contains('网络连接')) {
      return '网络连接不稳定，请检查网络后重试';
    }
    if (err.contains('API Key 无效') ||
        err.contains('余额不足') ||
        err.contains('没有调用该模型的权限') ||
        err.contains('不存在，请检查模型名称') ||
        err.contains('已被弃用') ||
        err.contains('timeout') ||
        err.contains('Timeout')) {
      return err.replaceAll('Exception: ', '');
    }
    return '服务暂时开小差了，正在修复中，请稍后重试';
  }

  /// 提取关键词
  List<String> extractKeywords(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    return words.where((w) => w.length > 2).toList();
  }
}
