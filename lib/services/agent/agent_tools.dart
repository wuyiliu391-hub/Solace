/// Agent 工具定义 — OpenAI function calling 格式
library;

import '../../models/bt_agent_action.dart';

/// 工具定义（OpenAI function calling 格式）
class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toOpenAIFormat() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// 所有可用工具列表
final List<AgentTool> agentTools = [
  // ─── 外观主题 ───
  AgentTool(
    name: 'setTheme',
    description: '切换 App 主题（浅色/深色/跟随系统）',
    parameters: {
      'type': 'object',
      'properties': {
        'mode': {
          'type': 'string',
          'enum': ['light', 'dark', 'system'],
          'description': '主题模式：light=浅色, dark=深色, system=跟随系统',
        },
      },
      'required': ['mode'],
    },
  ),

  // ─── 聊天管理 ───
  AgentTool(
    name: 'deleteMessage',
    description: '删除指定的聊天消息',
    parameters: {
      'type': 'object',
      'properties': {
        'messageId': {
          'type': 'string',
          'description': '要删除的消息 ID',
        },
      },
      'required': ['messageId'],
    },
  ),

  AgentTool(
    name: 'clearChatHistory',
    description: '清空当前聊天的所有记录',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  ),

  // ─── 联系人管理 ───
  AgentTool(
    name: 'hideContact',
    description: '隐藏联系人（不在列表显示）',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '要隐藏的角色 ID，留空则隐藏当前角色',
        },
      },
    },
  ),

  AgentTool(
    name: 'deleteContact',
    description: '删除联系人及其所有数据',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '要删除的角色 ID',
        },
      },
      'required': ['characterId'],
    },
  ),

  AgentTool(
    name: 'updateContactRemark',
    description: '修改联系人备注名',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '角色 ID',
        },
        'name': {
          'type': 'string',
          'description': '新的备注名',
        },
      },
      'required': ['characterId', 'name'],
    },
  ),

  // ─── 角色状态 ───
  AgentTool(
    name: 'setOnlineStatus',
    description: '设置角色在线/离线状态',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '角色 ID，留空则为当前角色',
        },
        'online': {
          'type': 'boolean',
          'description': 'true=在线, false=离线',
        },
      },
      'required': ['online'],
    },
  ),

  AgentTool(
    name: 'toggleBlock',
    description: '屏蔽/取消屏蔽当前聊天',
    parameters: {
      'type': 'object',
      'properties': {
        'block': {
          'type': 'boolean',
          'description': 'true=屏蔽, false=取消屏蔽',
        },
      },
      'required': ['block'],
    },
  ),

  // ─── 角色重置 ───
  AgentTool(
    name: 'clearCharacterMemory',
    description: '清空角色的全部记忆',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '角色 ID，留空则为当前角色',
        },
      },
    },
  ),

  AgentTool(
    name: 'resetCharacterPersona',
    description: '重置角色人设到初始状态',
    parameters: {
      'type': 'object',
      'properties': {
        'characterId': {
          'type': 'string',
          'description': '角色 ID，留空则为当前角色',
        },
      },
    },
  ),

  // ─── 朋友圈 ───
  AgentTool(
    name: 'postMoment',
    description: '发布一条朋友圈动态',
    parameters: {
      'type': 'object',
      'properties': {
        'content': {
          'type': 'string',
          'description': '动态文字内容',
        },
      },
      'required': ['content'],
    },
  ),

  AgentTool(
    name: 'deleteMoment',
    description: '删除指定的动态',
    parameters: {
      'type': 'object',
      'properties': {
        'momentId': {
          'type': 'string',
          'description': '动态 ID',
        },
      },
      'required': ['momentId'],
    },
  ),

  // ─── 信件 ───
  AgentTool(
    name: 'sendLetter',
    description: '给其他角色发送信件',
    parameters: {
      'type': 'object',
      'properties': {
        'toCharacterId': {
          'type': 'string',
          'description': '收件角色 ID',
        },
        'content': {
          'type': 'string',
          'description': '信件内容',
        },
      },
      'required': ['toCharacterId', 'content'],
    },
  ),

  // ─── 个人资料 ───
  AgentTool(
    name: 'updateProfileNickname',
    description: '修改用户昵称',
    parameters: {
      'type': 'object',
      'properties': {
        'nickname': {
          'type': 'string',
          'description': '新昵称',
        },
      },
      'required': ['nickname'],
    },
  ),

  // ─── 系统消息 ───
  AgentTool(
    name: 'insertSystemMessage',
    description: '在聊天中插入一条系统消息',
    parameters: {
      'type': 'object',
      'properties': {
        'content': {
          'type': 'string',
          'description': '系统消息内容',
        },
      },
      'required': ['content'],
    },
  ),
];

/// 获取工具的 OpenAI 格式列表
List<Map<String, dynamic>> getAgentToolsForAPI() {
  return agentTools.map((t) => t.toOpenAIFormat()).toList();
}

/// 工具名 → BtActionType 映射
BtActionType? mapToolNameToBtAction(String toolName) {
  switch (toolName) {
    case 'setTheme':
      return null; // 特殊处理，根据 mode 参数选择
    case 'deleteMessage':
      return BtActionType.deleteMessage;
    case 'clearChatHistory':
      return BtActionType.clearChatHistory;
    case 'hideContact':
      return BtActionType.hideContact;
    case 'deleteContact':
      return BtActionType.deleteContact;
    case 'updateContactRemark':
      return BtActionType.updateContactRemark;
    case 'setOnlineStatus':
      return BtActionType.setOnlineStatus;
    case 'toggleBlock':
      return BtActionType.toggleBlock;
    case 'clearCharacterMemory':
      return BtActionType.clearCharacterMemory;
    case 'resetCharacterPersona':
      return BtActionType.resetCharacterPersona;
    case 'postMoment':
      return BtActionType.postMoment;
    case 'deleteMoment':
      return BtActionType.deleteMoment;
    case 'sendLetter':
      return BtActionType.sendLetter;
    case 'updateProfileNickname':
      return BtActionType.updateProfileNickname;
    case 'insertSystemMessage':
      return BtActionType.insertSystemMessage;
    default:
      return null;
  }
}

/// setTheme 特殊处理
BtActionType? mapThemeMode(String mode) {
  switch (mode) {
    case 'light':
      return BtActionType.setLightTheme;
    case 'dark':
      return BtActionType.setDarkTheme;
    case 'system':
      return BtActionType.setSystemTheme;
    default:
      return null;
  }
}
