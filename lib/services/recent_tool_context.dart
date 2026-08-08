import '../models/chat_message.dart';

/// Short-lived context that permits a user to naturally continue a read-only
/// device query without repeating its command wording.
class RecentToolContext {
  static const continuationWindow = Duration(minutes: 8);

  static const readOnlyTools = {
    'get_battery_info',
    'get_notifications',
    'get_notification_count',
    'get_current_app',
    'get_installed_apps',
    'get_app_usage_time',
    'get_processes',
    'take_screenshot',
  };

  final String toolName;
  final Map<String, dynamic> args;
  final String result;
  final DateTime createdAt;

  const RecentToolContext({
    required this.toolName,
    required this.args,
    required this.result,
    required this.createdAt,
  });

  bool get isReadOnly => readOnlyTools.contains(toolName);

  bool isUsableAt(DateTime now) =>
      isReadOnly && now.difference(createdAt) <= continuationWindow;

  /// Explicit natural-language refresh requests should not depend on another
  /// LLM classification round.
  static bool isContinuationRequest(String message) {
    final normalized = message
        .trim()
        .replaceAll(RegExp(r'[，。！？,.!?、:：]'), '')
        .replaceAll(RegExp(r'^(哥哥|姐姐|宝贝|亲爱的|作者)\s*'), '')
        .replaceAll(RegExp(r'[呀啊吗呗啦嘛哟哦~～]+$'), '')
        .trim();
    return RegExp(
      r'^(?:再看(?:一次|一遍|一下|下)?|再看看|再来一次|再查(?:一次|一下|下)?|再帮我看看|重新看(?:一次|一下)?|再测(?:一次|一下)?|再读(?:一次|一下)?)$',
    ).hasMatch(normalized);
  }

  static RecentToolContext? fromMessages(
    List<ChatMessage> messages, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    for (final message in messages.reversed) {
      if (message.isHidden || message.isGhost) continue;
      final trace = message.metadata?['toolTrace'];
      if (trace is! List) continue;
      for (final raw in trace.reversed) {
        if (raw is! Map) continue;
        final entry = Map<String, dynamic>.from(raw);
        if (entry['success'] != true) continue;
        final tool = entry['tool']?.toString() ?? '';
        if (!readOnlyTools.contains(tool)) continue;
        final context = RecentToolContext(
          toolName: tool,
          args: entry['args'] is Map
              ? Map<String, dynamic>.from(entry['args'] as Map)
              : const {},
          result: entry['result']?.toString() ?? '',
          createdAt: message.createdAt,
        );
        return context.isUsableAt(reference) ? context : null;
      }
    }
    return null;
  }

  String toPromptText() => '最近真实设备查询：$toolName(${args.isEmpty ? '无参数' : args})，'
      '结果：$result。时间：${createdAt.toIso8601String()}。';
}
