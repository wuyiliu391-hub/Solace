/// BT Agent 动作数据模型
///
/// 仅定义 APP 内白名单动作，不包含退出登录、数据导入/导出、AI/API 配置等永久禁用项。
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

/// BT Agent 动作类型枚举（仅允许动作）
enum BtActionType {
  // ─── 局部会话 ───
  deleteMessage,
  clearChatHistory,
  toggleBlock,
  deleteCharacter,
  clearCharacterMemory,
  resetCharacterPersona,
  deleteChatSession,
  clearGroupContent,
  insertSystemMessage,

  // ─── 通讯录/联系人 ───
  updateContactRemark,
  updateContactAvatar,
  hideContact,
  deleteContact,

  // ─── 角色/互动配置 ───
  setOnlineStatus,
  setSaveStatus,
  setMessageDisturb,
  setVideoChat,
  reportCharacter,

  // ─── 发现页 ───
  postMoment,
  deleteMoment,
  hideMoment,
  commentMoment,
  clearMomentsData,
  sendLetter,
  deleteLetter,
  markLetter,
  clearLettersData,
  createDiary,
  modifyDiary,
  deleteDiary,
  clearDiaryData,
  triggerLuckyWheel,
  clearLuckyWheelData,
  queryGlobalMemory,
  organizeGlobalMemory,
  deleteGlobalMemoryItem,

  // ─── 个人资料 ───
  updateProfileAvatar,
  updateProfileNickname,

  // ─── 外观主题 ───
  setLightTheme,
  setDarkTheme,
  setSystemTheme,
}

/// 权限分类
enum BtPermissionCategory {
  contact,
  interaction,
  discover,
  profile,
  appearance,
}

/// 作用域
enum BtActionScope {
  chatScope,
  groupScope,
  characterScope,
  contactScope,
  discoverScope,
  profileScope,
  appearanceScope,
}

/// 动作执行结果
enum BtActionResult {
  success,
  rejected,
  failed,
}

/// 拒绝/失败原因
enum BtRejectionReason {
  masterSwitchOff,
  childPermissionOff,
  permanentlyForbidden,
  scopeViolation,
  whitelistMismatch,
  parseError,
  unknown,
}

/// 操作对象类型
enum BtTargetType {
  message,
  chatSession,
  character,
  memory,
  contact,
  moment,
  letter,
  diary,
  luckyWheel,
  globalMemory,
  user,
  theme,
  none,
}

/// 动作到权限分类的映射
const Map<BtActionType, BtPermissionCategory> btActionCategoryMap = {
  // 通讯录
  BtActionType.updateContactRemark: BtPermissionCategory.contact,
  BtActionType.updateContactAvatar: BtPermissionCategory.contact,
  BtActionType.hideContact: BtPermissionCategory.contact,
  BtActionType.deleteContact: BtPermissionCategory.contact,
  // 角色&互动
  BtActionType.setOnlineStatus: BtPermissionCategory.interaction,
  BtActionType.setSaveStatus: BtPermissionCategory.interaction,
  BtActionType.setMessageDisturb: BtPermissionCategory.interaction,
  BtActionType.setVideoChat: BtPermissionCategory.interaction,
  BtActionType.toggleBlock: BtPermissionCategory.interaction,
  BtActionType.clearChatHistory: BtPermissionCategory.interaction,
  BtActionType.resetCharacterPersona: BtPermissionCategory.interaction,
  BtActionType.clearCharacterMemory: BtPermissionCategory.interaction,
  BtActionType.reportCharacter: BtPermissionCategory.interaction,
  BtActionType.deleteMessage: BtPermissionCategory.interaction,
  BtActionType.deleteCharacter: BtPermissionCategory.interaction,
  BtActionType.deleteChatSession: BtPermissionCategory.interaction,
  BtActionType.clearGroupContent: BtPermissionCategory.interaction,
  BtActionType.insertSystemMessage: BtPermissionCategory.interaction,
  // 发现页
  BtActionType.postMoment: BtPermissionCategory.discover,
  BtActionType.deleteMoment: BtPermissionCategory.discover,
  BtActionType.hideMoment: BtPermissionCategory.discover,
  BtActionType.commentMoment: BtPermissionCategory.discover,
  BtActionType.clearMomentsData: BtPermissionCategory.discover,
  BtActionType.sendLetter: BtPermissionCategory.discover,
  BtActionType.deleteLetter: BtPermissionCategory.discover,
  BtActionType.markLetter: BtPermissionCategory.discover,
  BtActionType.clearLettersData: BtPermissionCategory.discover,
  BtActionType.createDiary: BtPermissionCategory.discover,
  BtActionType.modifyDiary: BtPermissionCategory.discover,
  BtActionType.deleteDiary: BtPermissionCategory.discover,
  BtActionType.clearDiaryData: BtPermissionCategory.discover,
  BtActionType.triggerLuckyWheel: BtPermissionCategory.discover,
  BtActionType.clearLuckyWheelData: BtPermissionCategory.discover,
  BtActionType.queryGlobalMemory: BtPermissionCategory.discover,
  BtActionType.organizeGlobalMemory: BtPermissionCategory.discover,
  BtActionType.deleteGlobalMemoryItem: BtPermissionCategory.discover,
  // 个人资料
  BtActionType.updateProfileAvatar: BtPermissionCategory.profile,
  BtActionType.updateProfileNickname: BtPermissionCategory.profile,
  // 外观主题
  BtActionType.setLightTheme: BtPermissionCategory.appearance,
  BtActionType.setDarkTheme: BtPermissionCategory.appearance,
  BtActionType.setSystemTheme: BtPermissionCategory.appearance,
};

/// 永久禁用动作关键字列表（AI prompt + 执行层双重拦截）
const List<String> btPermanentlyForbiddenKeywords = [
  'logout',
  'sign_out',
  'signOut',
  'export_data',
  'exportData',
  'import_data',
  'importData',
  'change_api_key',
  'changeApiKey',
  'modify_model',
  'modifyModel',
  'change_model',
  'changeModel',
  'reset_ai_config',
  'resetAiConfig',
];

bool looksLikeBtAgentPayload(String input) {
  final text = input.trim();
  if (text.isEmpty) return false;
  final lower = text.toLowerCase();
  if (lower.contains('bt_agent') ||
      lower.contains('bt_agent_actions') ||
      lower.contains('【bt 模式强制输出规则】') ||
      lower.contains('bt 病娇模式已开启') ||
      lower.contains('白名单动作') ||
      lower.contains('永久禁用') ||
      lower.contains('permanently forbidden')) {
    return true;
  }

  final compact = lower.replaceAll(RegExp(r'\s+'), '');
  if (compact.contains('"type":"action"') ||
      compact.contains('"targetpage"') ||
      compact.contains('"targetcontrol"') ||
      compact.contains('"targetid"') ||
      compact.contains('"permissioncategory"') ||
      compact.contains('"visible_text"')) {
    return true;
  }

  return BtActionType.values
      .any((action) => compact.contains('"${action.name.toLowerCase()}"'));
}

String stripBtAgentPayloads(String input, {bool preserveVisibleText = true}) {
  var text = input.trim();
  if (text.isEmpty) return text;

  text = text.replaceAll(
    RegExp(r'<bt_agent_actions>[\s\S]*?</bt_agent_actions>',
        caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(r'<BT_ACTION>\s*\{.*?\}\s*</BT_ACTION>',
        caseSensitive: false, dotAll: true),
    '',
  );
  text = text.replaceAll(
    RegExp(
        r'<internal_context[^>]*type="bt_agent"[^>]*>[\s\S]*?</internal_context>',
        caseSensitive: false),
    '',
  );
  text = text.replaceAllMapped(
    RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false),
    (match) {
      final block = match.group(1) ?? '';
      if (!looksLikeBtAgentPayload(block)) return match.group(0) ?? '';
      if (!preserveVisibleText) return '';
      return _extractBtVisibleText(block);
    },
  );

  final visible = preserveVisibleText ? _extractBtVisibleText(text) : '';
  if (looksLikeBtAgentPayload(text)) {
    final jsonOnly = _extractFirstBtJsonObject(text);
    if (jsonOnly.isNotEmpty && jsonOnly.length >= text.length - 8) {
      return visible.trim();
    }
    if (jsonOnly.isNotEmpty) {
      text = text.replaceFirst(jsonOnly, visible);
    }
  }

  return text.trim();
}

String _extractBtVisibleText(String input) {
  final jsonText = _extractFirstBtJsonObject(input);
  if (jsonText.isEmpty) return '';
  try {
    final decoded =
        json.decode(jsonText.replaceAll(RegExp(r',\s*([}\]])'), r'$1'));
    if (decoded is Map<String, dynamic>) {
      final type = decoded['type']?.toString().trim() ?? '';
      if (type == 'chat') return decoded['content']?.toString().trim() ?? '';
      return decoded['visible_text']?.toString().trim() ?? '';
    }
  } catch (_) {}
  return '';
}

String _extractFirstBtJsonObject(String input) {
  final start = input.indexOf('{');
  final end = input.lastIndexOf('}');
  if (start < 0 || end <= start) return '';
  return input.substring(start, end + 1).trim();
}

/// 构建注入给 LLM 的 BT Agent 私有指令。
///
/// 只在 BT 病娇总开关开启时注入；执行层仍会再次校验总开关、子权限、禁用项与白名单。
String buildBtAgentSystemInstruction({required bool enabled}) {
  if (!enabled) return '';
  final allowedActions = BtActionType.values.map((e) => e.name).join(', ');
  final forbidden = btPermanentlyForbiddenKeywords.join(', ');
  return '''
<internal_context type="bt_agent" visibility="private">
【BT 模式强制输出规则】
BT 病娇模式已开启。从现在开始，你的最终回复只能输出一个纯 JSON 对象，禁止输出任何额外文字、解释、Markdown 代码块、注释、XML 标签或隐藏块。

【仅允许两种 JSON 格式，二选一】
1. 普通聊天：{"type":"chat","content":"你的回复文本"}
2. 执行动作：{"type":"action","targetPage":"chat","targetControl":"current_session","action":"setDarkTheme","params":{"value":"","reason":"因为想让界面更适合现在的氛围"}}

【动作请求优先级 — 最高优先级】
当用户明确要求执行某个 App 操作（如切换主题、删除消息、清空记录、发朋友圈、写日记、发送信件等白名单内的动作）时，你必须输出 type=action 的 JSON，绝对不能用小说叙事来"假装"执行。
- 错误示范：用户说"帮我调成深色模式"，你回复小说描写"她伸手在手机上点了几下，屏幕暗了下来" ← 这是错误的！
- 正确示范：用户说"帮我调成深色模式"，你输出 {"type":"action","action":"setDarkTheme",...} ← 这才是正确的！
只有在用户没有要求执行 App 操作时，才可以用 type=chat 输出小说内容。

【JSON 严格要求】
- JSON 必须可被 Dart 的 json.decode() 直接解析。
- 字符串中的换行、双引号、反斜杠必须正确转义。
- 禁止多余逗号，禁止结构缺失，禁止把 JSON 放进代码块。
- 禁止在 JSON 前后添加自然语言、表情、括号说明或空白段落。
- 普通聊天也必须包在 type=chat 的 JSON 中，不允许直接返回纯文本。

	【动作字段映射】
	- action 必须从允许动作白名单中选择。
	- targetControl 可使用 current_character 或 current_session；执行层会替换成真实 ID。
	- params.value 表示动作值；params.reason 表示执行原因。
	- 如果不确定目标或不需要动作，输出 type=chat。
	
	【允许动作白名单】
$allowedActions

【永久禁止】
绝对不要请求以下动作或同义动作：$forbidden。包括退出登录、导入/导出数据、修改 API Key、修改模型、重置 AI 配置等。

【执行边界】
你只是在请求动作，不要伪造执行结果；本地执行层会再次校验总开关、子权限、白名单和审计日志。
</internal_context>''';
}

/// BT Agent 审计日志记录
class BtAgentAction {
  final String id;
  final BtActionType actionType;
  final BtPermissionCategory category;
  final BtActionScope scope;
  final BtTargetType targetType;
  final String targetId;
  final String reason;
  final String stateBefore;
  final String stateAfter;
  final BtActionResult result;
  final BtRejectionReason? rejectionReason;
  final String characterId;
  final String sessionId;
  final String chatType; // 'single' or 'group'
  final String createdAt;

  BtAgentAction({
    String? id,
    required this.actionType,
    required this.category,
    required this.scope,
    required this.targetType,
    this.targetId = '',
    this.reason = '',
    this.stateBefore = '',
    this.stateAfter = '',
    required this.result,
    this.rejectionReason,
    this.characterId = '',
    this.sessionId = '',
    this.chatType = 'single',
    String? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'actionType': actionType.name,
        'category': category.name,
        'scope': scope.name,
        'targetType': targetType.name,
        'targetId': targetId,
        'reason': reason,
        'stateBefore': stateBefore,
        'stateAfter': stateAfter,
        'result': result.name,
        'rejectionReason': rejectionReason?.name ?? '',
        'characterId': characterId,
        'sessionId': sessionId,
        'chatType': chatType,
        'createdAt': createdAt,
      };

  factory BtAgentAction.fromMap(Map<String, dynamic> m) => BtAgentAction(
        id: m['id'] as String? ?? '',
        actionType: BtActionType.values.firstWhere(
          (e) => e.name == m['actionType'],
          orElse: () => BtActionType.deleteMessage,
        ),
        category: BtPermissionCategory.values.firstWhere(
          (e) => e.name == m['category'],
          orElse: () => BtPermissionCategory.interaction,
        ),
        scope: BtActionScope.values.firstWhere(
          (e) => e.name == m['scope'],
          orElse: () => BtActionScope.chatScope,
        ),
        targetType: BtTargetType.values.firstWhere(
          (e) => e.name == m['targetType'],
          orElse: () => BtTargetType.none,
        ),
        targetId: m['targetId'] as String? ?? '',
        reason: m['reason'] as String? ?? '',
        stateBefore: m['stateBefore'] as String? ?? '',
        stateAfter: m['stateAfter'] as String? ?? '',
        result: BtActionResult.values.firstWhere(
          (e) => e.name == m['result'],
          orElse: () => BtActionResult.failed,
        ),
        rejectionReason: (m['rejectionReason'] as String? ?? '').isNotEmpty
            ? BtRejectionReason.values.firstWhere(
                (e) => e.name == m['rejectionReason'],
                orElse: () => BtRejectionReason.unknown,
              )
            : null,
        characterId: m['characterId'] as String? ?? '',
        sessionId: m['sessionId'] as String? ?? '',
        chatType: m['chatType'] as String? ?? 'single',
        createdAt: m['createdAt'] as String? ?? '',
      );
}

/// 构建 BT 双通道专用 prompt（纯 App 控制，不含角色扮演）
///
/// 此 prompt 发给独立的 API 调用，不污染主聊天的 system prompt。
/// AI 只做一件事：判断用户是否需要执行 App 动作，如果是则输出动作 JSON。
String buildBtAgentDedicatedPrompt({
  required String characterName,
  required String userMessage,
  required String aiResponse,
}) {
  final allowedActions = BtActionType.values.map((e) => e.name).join(', ');
  final forbidden = btPermanentlyForbiddenKeywords.join(', ');
  return '''你是一个 App 自动化控制器。你不是角色扮演 AI，你不负责聊天。

你的唯一职责：分析「用户消息」和「AI 角色回复」，判断用户是否需要执行 App 操作。

## 判断规则
1. 如果用户明确要求了 App 操作（如"帮我调深色模式"、"删掉聊天记录"、"发个朋友圈"），输出对应的动作 JSON。
2. 如果用户的请求隐含了 App 操作意图（如"我不想看到他的消息了"→ 屏蔽/隐藏联系人），也输出动作 JSON。
3. 如果用户只是普通聊天、没有要求任何 App 操作，输出 {"action":"noop"}。
4. 不确定时输出 {"action":"noop"}。

## 可用动作白名单
$allowedActions

## 动作 JSON 格式（单个动作）
{"action":"动作名","target_id":"目标ID或留空","value":"参数值或留空","reason":"执行原因"}

## target_id 约定
- 涉及当前角色的操作：留空字符串 ""（执行层会自动替换为当前角色 ID）
- 涉及当前会话的操作：留空字符串 ""（执行层会自动替换为当前会话 ID）
- 涉及其他联系人的操作：需要从对话上下文中推断联系人名称或 ID

## 永久禁止
$forbidden

## 上下文
- 当前角色：$characterName
- 用户消息：$userMessage
- AI 角色回复（仅供参考，你不需要模仿此风格）：$aiResponse

只输出 JSON，不要输出任何其他文字。''';
}

/// 从 BT 专用 API 响应中提取动作 JSON
///
/// 支持：纯 JSON、fenced code block、noop 判断
String extractBtActionFromDedicatedResponse(String response) {
  var text = response.trim();
  if (text.isEmpty) return '';

  // 去掉 fenced code block
  final fenced =
      RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false)
          .firstMatch(text);
  if (fenced != null) {
    text = fenced.group(1)?.trim() ?? text;
  }

  // 提取第一个 JSON 对象
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return '';

  final jsonStr = text.substring(start, end + 1).trim();
  try {
    final decoded = json.decode(jsonStr);
    if (decoded is! Map<String, dynamic>) return '';
    final action = decoded['action']?.toString().trim() ?? '';
    if (action.isEmpty || action == 'noop') return '';
    // 返回标准化的动作 JSON 数组格式
    return json.encode([decoded]);
  } catch (_) {
    return '';
  }
}
