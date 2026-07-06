// 【对标来源：SillyTavern-1.18.0 — PromptManager.js Prompt 条目数据结构】
// 1:1 转译自 SillyTavern PromptManager 编辑表单字段
// 参考文件：public/scripts/PromptManager.js:300、#completion_prompt_manager_popup_entry_form_*

/// Prompt 条目（对标 SillyTavern PromptManager 编辑表单）
class PromptEntry {
  /// Prompt 名称（对标 #completion_prompt_manager_popup_entry_form_name）
  final String name;

  /// 注入角色：system/user/assistant（对标 #..._form_role）
  final String role;

  /// 触发器列表：Normal/Continue/Impersonate/Swipe/Regenerate/Quiet
  /// （对标 #..._form_injection_trigger）
  final List<String> injectionTrigger;

  /// 注入位置：↑Context/↓Context/@Depth
  /// （对标 #..._form_injection_position）
  final String injectionPosition;

  /// 注入深度 0-9999（对标 #..._form_injection_depth）
  final int injectionDepth;

  /// 注入顺序 0-9999（对标 #..._form_injection_order）
  final int injectionOrder;

  /// Prompt 内容，支持宏（对标 #..._form_prompt）
  final String prompt;

  /// 禁止角色卡覆盖（对标 #..._form_forbid_overrides）
  final bool forbidOverrides;

  /// 是否启用
  final bool enabled;

  /// 是否为系统内置（不可删除）
  final bool system;

  const PromptEntry({
    required this.name,
    this.role = 'system',
    this.injectionTrigger = const ['normal'],
    this.injectionPosition = '↑Context',
    this.injectionDepth = 4,
    this.injectionOrder = 100,
    this.prompt = '',
    this.forbidOverrides = false,
    this.enabled = true,
    this.system = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'injection_trigger': injectionTrigger,
        'injection_position': injectionPosition,
        'injection_depth': injectionDepth,
        'injection_order': injectionOrder,
        'prompt': prompt,
        'forbid_overrides': forbidOverrides,
        'enabled': enabled,
        'system': system,
      };

  factory PromptEntry.fromJson(Map<String, dynamic> json) {
    return PromptEntry(
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'system',
      injectionTrigger:
          (json['injection_trigger'] as List<dynamic>?)?.cast<String>() ??
              ['normal'],
      injectionPosition:
          json['injection_position'] as String? ?? '↑Context',
      injectionDepth: json['injection_depth'] as int? ?? 4,
      injectionOrder: json['injection_order'] as int? ?? 100,
      prompt: json['prompt'] as String? ?? '',
      forbidOverrides: json['forbid_overrides'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      system: json['system'] as bool? ?? false,
    );
  }
}
