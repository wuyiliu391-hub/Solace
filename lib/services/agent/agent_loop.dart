/// Agent 确定性工具路由 — 关键词匹配执行 BT 操作，不依赖 LLM function calling
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/bt_agent_action.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../repositories/local_storage_repository.dart';
import '../bt_agent_execution_service.dart';
import 'agent_tools.dart';

/// BT 动作执行回调
/// [toolName] 工具名，[success] 是否成功，[args] 工具参数
typedef BtActionCallback = void Function(
    String toolName, bool success, Map<String, dynamic> args);

/// Agent 执行结果
class AgentResult {
  final String content; // 回复文本
  final String reasoning; // 推理内容（不再使用，保留兼容）
  final List<AgentToolExecution> toolExecutions; // 执行的工具列表

  const AgentResult({
    required this.content,
    this.reasoning = '',
    this.toolExecutions = const [],
  });
}

/// 单次工具执行记录
class AgentToolExecution {
  final String toolName;
  final Map<String, dynamic> args;
  final String result;
  final bool success;

  const AgentToolExecution({
    required this.toolName,
    required this.args,
    required this.result,
    required this.success,
  });
}

/// Agent 工具路由服务
///
/// 纯关键词匹配，不调用 LLM。覆盖全部 BT 白名单操作。
/// 当用户消息不匹配任何 BT 操作时返回 null，由 ChatBloc 回退到普通聊天。
class AgentLoop {
  final BtAgentExecutionService _btService;

  AgentLoop({
    required LocalStorageRepository storage,
  }) : _btService = BtAgentExecutionService(storage);

  /// 尝试匹配并执行 BT 操作。无匹配时返回 null。
  Future<AgentResult?> run({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
    String? sessionId,
    BtActionCallback? onActionExecuted,
  }) async {
    debugPrint('[AgentLoop] 尝试确定性路由: $userMessage');

    final routed = await _tryDeterministicToolRoute(
      userMessage: userMessage,
      characterName: character.name,
      characterId: character.id,
      sessionId: sessionId ?? '',
      onActionExecuted: onActionExecuted,
    );

    if (routed != null) {
      debugPrint('[AgentLoop] 确定性路由命中');
    } else {
      debugPrint('[AgentLoop] 无匹配，回退普通聊天');
    }

    return routed;
  }

  /// 关键词匹配结果（不含执行）
  @visibleForTesting
  static ({String toolName, Map<String, dynamic> args})? matchBtKeyword(
      String userMessage) {
    final text = userMessage.trim();
    final lower = text.toLowerCase();

    // ─── 1. 主题切换 ───
    if (_matchAny(lower, ['浅色', '亮色', '白天']) &&
        _matchAny(lower, ['模式', '主题', '界面', '设置'])) {
      return (toolName: 'setTheme', args: {'mode': 'light'});
    }
    if (_matchAny(lower, ['深色', '暗色', '夜间', '黑色']) &&
        _matchAny(lower, ['模式', '主题', '界面', '设置'])) {
      return (toolName: 'setTheme', args: {'mode': 'dark'});
    }
    if (_matchAny(lower, ['跟随系统', '系统主题', '自动主题']) &&
        _matchAny(lower, ['模式', '主题', '界面', '设置'])) {
      return (toolName: 'setTheme', args: {'mode': 'system'});
    }

    // ─── 2. 清空聊天记录 ───
    if (_matchAny(lower, ['清空', '清除', '删掉所有', '删除所有', '全部删除']) &&
        _matchAny(lower, ['聊天记录', '对话记录', '消息记录', '聊天'])) {
      return (toolName: 'clearChatHistory', args: <String, dynamic>{});
    }

    // ─── 3. 删除消息（排除"动态/朋友圈"，避免误命中）───
    if (_matchAny(lower, ['删', '撤回', '删除']) &&
        _matchAny(lower, ['消息', '这条', '那条', '上一条', '上条']) &&
        !_matchAny(lower, ['动态', '朋友圈'])) {
      return (toolName: 'deleteMessage', args: <String, dynamic>{});
    }

    // ─── 4. 屏蔽/取消屏蔽 ───
    if (_matchAny(lower, [
          '取消屏蔽',
          '解除屏蔽',
          '取消拉黑',
          '解除拉黑',
          '解封',
          '取消封禁',
          '解除封禁',
          'unblock'
        ]) &&
        _matchAny(lower, ['屏蔽', '拉黑', '封禁', '封'])) {
      return (toolName: 'toggleBlock', args: {'block': false});
    }
    if (_matchAny(lower, ['屏蔽', '拉黑', '封禁', 'block']) &&
        !_matchAny(lower, ['取消', '解除', '解封'])) {
      return (toolName: 'toggleBlock', args: {'block': true});
    }

    // ─── 5. 隐藏联系人 ───
    if (_matchAny(lower, ['隐藏']) &&
        _matchAny(lower, ['联系人', '好友', '这个人', '他', '她'])) {
      return (toolName: 'hideContact', args: <String, dynamic>{});
    }

    // ─── 6. 删除联系人 ───
    if (_matchAny(lower, ['删', '删除', '移除']) &&
        _matchAny(lower, ['联系人', '好友', '好友列表'])) {
      return (toolName: 'deleteContact', args: <String, dynamic>{});
    }

    // ─── 7. 修改备注 ───
    final remarkMatch =
        RegExp(r'(?:改|修改|设置|换|改成|换成|设置为|改为)(?:备注名?|昵称备注)[\s:：为名]*(.+)')
            .firstMatch(text);
    if (remarkMatch != null) {
      final newName = remarkMatch.group(1)!.trim();
      if (newName.isNotEmpty) {
        return (toolName: 'updateContactRemark', args: {'name': newName});
      }
    }

    // ─── 8. 在线/离线状态 ───
    if (_matchAny(lower, ['上线', '设为在线', '设置在线', '让他上线', '让她上线'])) {
      return (toolName: 'setOnlineStatus', args: {'online': true});
    }
    if (_matchAny(lower, ['下线', '设为离线', '设置离线', '让他下线', '让她下线'])) {
      return (toolName: 'setOnlineStatus', args: {'online': false});
    }

    // ─── 9. 清空角色记忆 ───
    if (_matchAny(lower, ['清空', '清除', '删除', '擦除', '重置']) &&
        _matchAny(lower, ['记忆', '他的记忆', '她的记忆', '角色记忆', '全部记忆'])) {
      return (toolName: 'clearCharacterMemory', args: <String, dynamic>{});
    }

    // ─── 10. 重置角色人设 ───
    if (_matchAny(lower, ['重置', '恢复', '还原']) &&
        _matchAny(lower, ['人设', '角色', '初始', '默认'])) {
      return (toolName: 'resetCharacterPersona', args: <String, dynamic>{});
    }

    // ─── 11. 发朋友圈/动态 ───
    final momentMatch =
        RegExp(r'(?:发|发布|发一条|发个|帮我发)[\s]*(?:朋友圈|动态|说说)[\s:：]*(.*)')
            .firstMatch(text);
    if (momentMatch != null) {
      final content = momentMatch.group(1)?.trim() ?? '';
      return (
        toolName: 'postMoment',
        args: {'content': content.isNotEmpty ? content : text}
      );
    }
    if (_matchAny(lower, ['发朋友圈', '发动态', '发说说', '发个朋友圈', '发个动态'])) {
      return (toolName: 'postMoment', args: {'content': ''});
    }

    // ─── 12. 删除动态 ───
    if (_matchAny(lower, ['删', '删除']) &&
        _matchAny(lower, ['动态', '朋友圈', '那条动态', '这条动态'])) {
      return (toolName: 'deleteMoment', args: <String, dynamic>{});
    }

    // ─── 13. 发信件 ───
    // "发一封/写一封" 可以独立匹配；"发/写" 后面必须跟 "信"
    final letterSingle = RegExp(r'(?:发一封|写一封)[\s:：]*(.*)').firstMatch(text);
    final letterRegular =
        RegExp(r'(?:发|写)[\s]*(?:信件?|信给|信件给)[\s:：]*(.*)').firstMatch(text);
    final letterMatch = letterSingle ?? letterRegular;
    if (letterMatch != null) {
      final content =
          (letterSingle?.group(1) ?? letterRegular?.group(1))?.trim() ?? '';
      return (
        toolName: 'sendLetter',
        args: {'content': content.isNotEmpty ? content : text}
      );
    }

    // ─── 14. 修改昵称 ───
    final nicknameMatch =
        RegExp(r'(?:改|修改|设置|换|改成|换成|设置为|改为)(?:我的)?(?:昵称|名字)[\s:：为名]*(.+)')
            .firstMatch(text);
    if (nicknameMatch != null) {
      final newName = nicknameMatch.group(1)!.trim();
      if (newName.isNotEmpty) {
        return (toolName: 'updateProfileNickname', args: {'nickname': newName});
      }
    }

    // ─── 15. 写日记 ───
    if (_matchAny(lower, ['写日记', '记日记', '写一篇日记', '发日记', '创建日记'])) {
      return (toolName: 'createDiary', args: {'content': text});
    }

    // ─── 16. 插入系统消息 ───
    if (_matchAny(lower, ['插入系统消息', '发系统消息'])) {
      return (toolName: 'insertSystemMessage', args: {'content': text});
    }

    // ─── 17. 转幸运转盘 ───
    if (_matchAny(lower, ['转盘', '抽奖', '幸运转盘', '转一下'])) {
      return (toolName: 'triggerLuckyWheel', args: <String, dynamic>{});
    }

    return null;
  }

  /// 确定性工具路由：调用 matchBtKeyword 匹配，然后执行工具。
  Future<AgentResult?> _tryDeterministicToolRoute({
    required String userMessage,
    required String characterName,
    required String characterId,
    required String sessionId,
    BtActionCallback? onActionExecuted,
  }) async {
    final matched = matchBtKeyword(userMessage);
    if (matched == null) return null;

    final toolName = matched.toolName;
    final args = matched.args;

    final result = await _executeTool(
      toolName: toolName,
      args: args,
      characterId: characterId,
      sessionId: sessionId,
    );
    final success = !result.startsWith('错误') &&
        !result.startsWith('权限') &&
        !result.startsWith('执行失败');
    onActionExecuted?.call(toolName, success, args);

    final successMsg = _successMessage(toolName);
    final failMsg = success ? '' : '操作失败：$result';

    return AgentResult(
      content: success ? successMsg : failMsg,
      toolExecutions: [
        AgentToolExecution(
          toolName: toolName,
          args: args,
          result: result,
          success: success,
        ),
      ],
    );
  }

  static String _successMessage(String toolName) {
    switch (toolName) {
      case 'setTheme':
        return '好了，已经帮你切换主题了。';
      case 'clearChatHistory':
        return '已经帮你清空当前聊天记录了。';
      case 'deleteMessage':
        return '已经帮你删掉消息了。';
      case 'toggleBlock':
        return '已经帮你处理屏蔽了。';
      case 'hideContact':
        return '已经帮你隐藏联系人了。';
      case 'deleteContact':
        return '已经帮你删除联系人了。';
      case 'updateContactRemark':
        return '已经帮你修改备注了。';
      case 'setOnlineStatus':
        return '已经帮你设置状态了。';
      case 'clearCharacterMemory':
        return '已经帮你清空角色记忆了。';
      case 'resetCharacterPersona':
        return '已经帮你重置角色人设了。';
      case 'postMoment':
        return '已经帮你发布朋友圈了。';
      case 'deleteMoment':
        return '已经帮你删除动态了。';
      case 'sendLetter':
        return '已经帮你发信了。';
      case 'updateProfileNickname':
        return '已经帮你修改昵称了。';
      case 'createDiary':
        return '已经帮你写好日记了。';
      case 'insertSystemMessage':
        return '已经帮你插入系统消息了。';
      case 'triggerLuckyWheel':
        return '已经帮你转了转盘。';
      default:
        return '已经帮你处理好了。';
    }
  }

  /// 辅助：文本包含任一关键词
  static bool _matchAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }

  /// 执行单个工具
  Future<String> _executeTool({
    required String toolName,
    required Map<String, dynamic> args,
    required String characterId,
    required String sessionId,
  }) async {
    try {
      // setTheme 特殊处理
      if (toolName == 'setTheme') {
        final mode = args['mode'] as String? ?? 'system';
        final actionType = mapThemeMode(mode);
        if (actionType == null) return '错误：无效的主题模式 $mode';

        final actionJson = jsonEncode([
          {
            'action': actionType.name,
            'target_id': '',
            'value': mode,
            'reason': '用户要求切换主题',
          }
        ]);

        final results = await _btService.executeFromJson(
          actionJson,
          characterId: characterId,
          sessionId: sessionId,
        );

        if (results.isNotEmpty &&
            results.first.result == BtActionResult.success) {
          return '已切换为${mode == 'light' ? '浅色' : mode == 'dark' ? '深色' : '跟随系统'}主题';
        }
        return '切换主题失败';
      }

      // 其他工具
      final actionType = mapToolNameToBtAction(toolName);
      if (actionType == null) return '错误：未知工具 $toolName';

      // 构建 target_id 和 value
      String targetId = args['characterId'] as String? ??
          args['messageId'] as String? ??
          args['momentId'] as String? ??
          args['toCharacterId'] as String? ??
          '';
      String value = args['name'] as String? ??
          args['content'] as String? ??
          args['nickname'] as String? ??
          '';

      // 布尔值特殊处理
      if (args.containsKey('online')) {
        value = args['online'] == true ? 'true' : 'false';
      }
      if (args.containsKey('block')) {
        value = args['block'] == true ? 'true' : 'false';
      }

      final actionJson = jsonEncode([
        {
          'action': actionType.name,
          'target_id': targetId,
          'value': value,
          'reason': 'Agent 工具调用: $toolName',
        }
      ]);

      final results = await _btService.executeFromJson(
        actionJson,
        characterId: characterId,
        sessionId: sessionId,
      );

      if (results.isNotEmpty) {
        final r = results.first;
        if (r.result == BtActionResult.success) {
          return '执行成功: $toolName';
        } else if (r.result == BtActionResult.rejected) {
          return '权限不足: ${r.rejectionReason?.name ?? '未知原因'}';
        }
        return '执行失败: $toolName';
      }

      return '执行完成';
    } catch (e) {
      return '错误: $e';
    }
  }
}
