import '../../models/chat_message.dart';
import '../../utils/message_sanitizer.dart';
import '../../services/builtin_sticker_service.dart';

/// ChatBloc 的纯工具方法 mixin
/// 不依赖 BLoC 状态，仅做数据转换和判断
mixin ChatBlocUtils {
  // 仅匹配「AI 身份自述 + 明确拒绝」的完整句式，避免误判正常角色扮演台词。
  // 规则：必须含有 AI 身份词（AI/语言模型/助手/我是AI）且同时含拒绝动词，
  // 或者使用了明确的角色扮演拒绝短语（如"无法扮演此角色"）。
  // 刻意排除：抱歉/对不起/换个话题 等日常词汇，这些在角色扮演中极为常见。
  static final RegExp aiRefusalPattern = RegExp(
    // AI 身份自述 + 拒绝动词组合
    r'作为.{0,10}(?:AI|语言模型|人工智能|助手).{0,20}(?:无法|不能|拒绝)|'
    r'(?:AI|语言模型|人工智能).{0,10}(?:无法|不能|拒绝).{0,20}(?:角色扮演|扮演|生成|继续)|'
    // 明确角色扮演拒绝短语
    r'无法扮演此角色|不能继续扮演|不能.*角色扮演|拒绝.*扮演|'
    // 内容政策/安全限制（必须同时提到政策/规定等关键词）
    r'违反.{0,8}(?:内容政策|使用条款|安全准则|平台规定)|'
    r'(?:内容政策|安全限制|使用条款).{0,10}(?:不允许|禁止|限制)|'
    // 直接声明超出范围
    r'超出.{0,6}(?:训练|设计|能力).{0,6}范围',
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
