// BT Agent 工具链（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocBtAgent on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState {
  String? _stripBtJsonLeak(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    final jsonText = _extractFirstJsonObject(trimmed);
    if (jsonText.isEmpty) return trimmed;

    try {
      final decoded = json.decode(_cleanBtJsonString(jsonText));
      if (decoded is! Map<String, dynamic>) return trimmed;
      final type = decoded['type']?.toString().trim() ?? '';
      if (type == 'chat') {
        final content = decoded['content']?.toString().trim() ?? '';
        return content.isNotEmpty ? content : '';
      }
      if (type == 'action' || decoded.containsKey('targetPage')) {
        return '';
      }
    } catch (_) {
      if (trimmed.contains('"type"') &&
          trimmed.contains('"action"') &&
          trimmed.contains('"params"')) {
        return '';
      }
    }
    return trimmed;
  }

  ({String visibleText, String actionsJson}) _extractBtAgentActions(
    String text, {
    required bool allowAction,
    required String characterId,
    required String sessionId,
    required String chatId,
  }) {
    final rawText = text.trim();
    if (rawText.isEmpty) return (visibleText: '', actionsJson: '');
    if (!allowAction) {
      final visibleText = _stripBtJsonLeak(rawText) ?? rawText;
      if (visibleText != rawText) {
        LogService.instance.w(
          'BT',
          '纯AI模式拦截 BT JSON 泄漏，已禁止动作执行',
          chatId: chatId,
        );
      }
      return (visibleText: visibleText, actionsJson: '');
    }

    final legacyMatch = RegExp(
      r'<bt_agent_actions>\s*([\s\S]*?)\s*</bt_agent_actions>',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (legacyMatch != null) {
      final legacyJson = legacyMatch.group(1)?.trim() ?? '';
      return (
        visibleText: rawText.replaceFirst(legacyMatch.group(0)!, '').trim(),
        actionsJson: _resolveBtAgentActionTargets(
          _cleanBtJsonString(legacyJson),
          characterId: characterId,
          sessionId: sessionId,
        ),
      );
    }

    final jsonText = _extractFirstJsonObject(rawText);
    if (jsonText.isEmpty) {
      LogService.instance.w(
        'BT',
        'BT JSON 提取失败：AI 未返回 JSON，按普通聊天显示',
        chatId: chatId,
      );
      return (visibleText: rawText, actionsJson: '');
    }

    final cleanedJson = _cleanBtJsonString(jsonText);
    try {
      final decoded = json.decode(cleanedJson);
      if (decoded is! Map<String, dynamic>) {
        LogService.instance.w(
          'BT',
          'BT JSON 根节点不是对象，按普通聊天显示',
          chatId: chatId,
        );
        return (visibleText: rawText, actionsJson: '');
      }

      final type = decoded['type']?.toString().trim() ?? '';
      if (type == 'chat') {
        final content = decoded['content']?.toString().trim() ?? '';
        return (
          visibleText: content.isNotEmpty ? content : rawText,
          actionsJson: '',
        );
      }

      if (type == 'action') {
        final actionJson = _convertBtActionEnvelopeToExecutionJson(
          decoded,
          characterId: characterId,
          sessionId: sessionId,
        );
        if (actionJson.isEmpty) {
          LogService.instance.w(
            'BT',
            'BT action JSON 字段缺失，按普通聊天显示',
            chatId: chatId,
          );
          return (visibleText: rawText, actionsJson: '');
        }
        return (visibleText: '', actionsJson: actionJson);
      }

      LogService.instance.w(
        'BT',
        'BT JSON type 不支持: $type，按普通聊天显示',
        chatId: chatId,
      );
      return (visibleText: rawText, actionsJson: '');
    } catch (e) {
      LogService.instance.e(
        'BT',
        'BT JSON 解析失败: $e；原始片段=$cleanedJson',
        chatId: chatId,
      );
      return (visibleText: rawText, actionsJson: '');
    }
  }


  String _extractFirstJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return '';
    return text.substring(start, end + 1);
  }


  String _cleanBtJsonString(String jsonText) {
    var cleaned = jsonText.trim();
    cleaned = cleaned.replaceAll(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
    cleaned = cleaned.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    return cleaned.trim();
  }


  String _convertBtActionEnvelopeToExecutionJson(
    Map<String, dynamic> decoded, {
    required String characterId,
    required String sessionId,
  }) {
    final action = decoded['action']?.toString().trim() ?? '';
    if (action.isEmpty) return '';

    final params = decoded['params'];
    final paramMap =
        params is Map<String, dynamic> ? params : <String, dynamic>{};
    final targetControl = decoded['targetControl']?.toString().trim() ?? '';
    final targetPage = decoded['targetPage']?.toString().trim() ?? '';
    final rawTargetId = (paramMap['target_id'] ??
            paramMap['targetId'] ??
            paramMap['id'] ??
            targetControl)
        .toString()
        .trim();
    final value = (paramMap['value'] ?? '').toString();
    final reason = (paramMap['reason'] ??
            decoded['reason'] ??
            'BT 模式动作请求：$targetPage/$targetControl')
        .toString();

    final normalized = <String, dynamic>{
      'action': action,
      'target_id': _resolveBtAgentTargetId(
        rawTargetId,
        characterId: characterId,
        sessionId: sessionId,
      ),
      'value': value,
      'reason': reason,
    };
    return json.encode(normalized);
  }


  String _resolveBtAgentTargetId(
    String targetId, {
    required String characterId,
    required String sessionId,
  }) {
    if (targetId == 'current_character') return characterId;
    if (targetId == 'current_session') return sessionId;
    return targetId;
  }


  String _resolveBtAgentActionTargets(
    String jsonText, {
    required String characterId,
    required String sessionId,
  }) {
    return jsonText
        .replaceAll(
            '"target_id":"current_character"', '"target_id":"$characterId"')
        .replaceAll(
            '"target_id": "current_character"', '"target_id": "$characterId"')
        .replaceAll('"target_id":"current_session"', '"target_id":"$sessionId"')
        .replaceAll(
            '"target_id": "current_session"', '"target_id": "$sessionId"');
  }


  /// 从 AI 回复中提取 <BT_ACTION> 标签并执行操作
  ///
  /// 返回清理标签后的纯文本，同时通过 BtAgentExecutionService 执行动作。
  /// 适用于不支持 function calling 的国产模型：通过系统 prompt 告诉 AI 输出
  /// <BT_ACTION>{"action":"xxx","params":{...}}</BT_ACTION> 标签来触发操作。
  Future<String> _processBtActionTags(
    String text, {
    required String characterId,
    required String sessionId,
  }) async {
    if (text.isEmpty || !text.contains('<BT_ACTION>')) return text;

    final pattern = RegExp(r'<BT_ACTION>\s*(\{.*?\})\s*</BT_ACTION>',
        caseSensitive: false, dotAll: true);
    final matches = pattern.allMatches(text);
    if (matches.isEmpty) return text;

    final cleanText = text.replaceAll(pattern, '').trim();

    for (final match in matches) {
      final jsonStr = match.group(1)?.trim() ?? '';
      if (jsonStr.isEmpty) continue;

      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final actionName = decoded['action'] as String? ?? '';
        final params = decoded['params'] as Map<String, dynamic>? ?? {};
        if (actionName.isEmpty) continue;

        LogService.instance
            .i('BT', '提取到 BT_ACTION: $actionName $params', chatId: sessionId);

        await _dispatchBtAction(
          actionName: actionName,
          params: params,
          characterId: characterId,
          sessionId: sessionId,
        );
      } catch (e) {
        LogService.instance.e('BT', 'BT_ACTION 解析执行失败: $e', chatId: sessionId);
      }
    }

    _storage.modeSettingsNotifier.value++;
    return cleanText;
  }


  /// 派发单个 BT 动作到执行服务
  Future<void> _dispatchBtAction({
    required String actionName,
    required Map<String, dynamic> params,
    required String characterId,
    required String sessionId,
  }) async {
    try {
      // 主题切换特殊处理
      if (actionName == 'setTheme') {
        final mode = params['mode'] as String? ?? 'system';
        final themeType = mapThemeMode(mode);
        if (themeType == null) return;

        final actionJson = jsonEncode([
          {
            'action': themeType.name,
            'target_id': '',
            'value': mode,
            'reason': '病娇操控: 主题切换',
          }
        ]);

        await _btAgentExecutionService.executeFromJson(
          actionJson,
          characterId: characterId,
          sessionId: sessionId,
        );
        _storage.themeChangeNotifier.value = mode;
        return;
      }

      // 其他工具
      final actionType = mapToolNameToBtAction(actionName);
      if (actionType == null) {
        LogService.instance.w('BT', '未知 BT 动作: $actionName', chatId: sessionId);
        return;
      }

      // 构建 value
      String value = '';
      if (params.containsKey('online')) {
        value = params['online'] == true ? 'true' : 'false';
      } else if (params.containsKey('block')) {
        value = params['block'] == true ? 'true' : 'false';
      } else {
        value = params['name'] as String? ??
            params['content'] as String? ??
            params['nickname'] as String? ??
            params['messageId'] as String? ??
            '';
      }

      final actionJson = jsonEncode([
        {
          'action': actionType.name,
          'target_id': '',
          'value': value,
          'reason': '病娇操控: $actionName',
        }
      ]);

      await _btAgentExecutionService.executeFromJson(
        actionJson,
        characterId: characterId,
        sessionId: sessionId,
      );
    } catch (e) {
      LogService.instance.e('BT', '_dispatchBtAction 失败: $actionName -> $e',
          chatId: sessionId);
    }
  }

}
