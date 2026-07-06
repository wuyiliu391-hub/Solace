// 【对标来源：SillyTavern-1.18.0 — char-data.js v2CharData 角色卡数据结构】
// 1:1 转译自 SillyTavern v2 spec，字段名、类型、语义完全保留
// 参考文件：public/scripts/char-data.js、public/index.html:6039-6655 (#form_create)

/// 角色卡 v2 数据结构（对标 SillyTavern v2CharData）
class CharacterCardV2 {
  /// 角色名称（对标 #character_name_pole / ch_name）
  final String name;

  /// 角色描述：身体/心理特征（对标 #description_textarea / description）
  final String description;

  /// 角色版本号（对标 #character_version_textarea / character_version）
  final String characterVersion;

  /// 人格简述（对标 #personality_textarea / personality）
  final String personality;

  /// 场景/交互背景（对标 #scenario_pole / scenario）
  final String scenario;

  /// 首条消息/开场白（对标 #firstmessage_textarea / first_mes）
  final String firstMes;

  /// 对话示例，<START> 分隔（对标 #mes_example_textarea / mes_example）
  final String mesExample;

  /// 创建者备注（对标 #creator_notes_textarea / creator_notes）
  final String creatorNotes;

  /// 标签列表（对标 #tags_textarea / tags，逗号分隔）
  final List<String> tags;

  /// 系统提示词 v2 spec（对标 #system_prompt_textarea / system_prompt）
  final String systemPrompt;

  /// 历史后指令 v2 spec（对标 #post_history_instructions_textarea）
  final String postHistoryInstructions;

  /// 创建者名称/联系方式（对标 #creator_textarea / creator）
  final String creator;

  /// 备用问候列表（对标 #alternate_greetings_template）
  final List<String> alternateGreetings;

  /// 角色内嵌世界观（对标 character_book / .character_world_info_selector）
  final WorldInfoBook? characterBook;

  /// 扩展字段（对标 extensions）
  final CharacterExtensions extensions;

  /// 头像路径（SillyTavern 原生用 URL，Solace 用本地路径）
  final String? avatarPath;

  const CharacterCardV2({
    required this.name,
    this.description = '',
    this.characterVersion = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.creatorNotes = '',
    this.tags = const [],
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.creator = '',
    this.alternateGreetings = const [],
    this.characterBook,
    this.extensions = const CharacterExtensions(),
    this.avatarPath,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'character_version': characterVersion,
        'personality': personality,
        'scenario': scenario,
        'first_mes': firstMes,
        'mes_example': mesExample,
        'creator_notes': creatorNotes,
        'tags': tags,
        'system_prompt': systemPrompt,
        'post_history_instructions': postHistoryInstructions,
        'creator': creator,
        'alternate_greetings': alternateGreetings,
        'character_book': characterBook?.toJson(),
        'extensions': extensions.toJson(),
        'avatar_path': avatarPath,
      };

  factory CharacterCardV2.fromJson(Map<String, dynamic> json) {
    return CharacterCardV2(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      characterVersion: json['character_version'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      scenario: json['scenario'] as String? ?? '',
      firstMes: json['first_mes'] as String? ?? '',
      mesExample: json['mes_example'] as String? ?? '',
      creatorNotes: json['creator_notes'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      systemPrompt: json['system_prompt'] as String? ?? '',
      postHistoryInstructions:
          json['post_history_instructions'] as String? ?? '',
      creator: json['creator'] as String? ?? '',
      alternateGreetings:
          (json['alternate_greetings'] as List<dynamic>?)?.cast<String>() ?? [],
      characterBook: json['character_book'] != null
          ? WorldInfoBook.fromJson(
              json['character_book'] as Map<String, dynamic>)
          : null,
      extensions: json['extensions'] != null
          ? CharacterExtensions.fromJson(
              json['extensions'] as Map<String, dynamic>)
          : const CharacterExtensions(),
      avatarPath: json['avatar_path'] as String?,
    );
  }
}

/// 角色扩展字段（对标 SillyTavern extensions）
class CharacterExtensions {
  /// 健谈度 0-1，step 0.05（对标 #talkativeness_slider / talkativeness）
  final double talkativeness;

  /// 收藏标记（对标 fav）
  final bool fav;

  /// 关联世界观名称（对标 world）
  final String? world;

  /// 深度注入配置（对标 depth_prompt）
  final DepthPrompt? depthPrompt;

  /// 正则脚本列表（对标 regex_scripts）
  final List<RegexScript> regexScripts;

  const CharacterExtensions({
    this.talkativeness = 0.5,
    this.fav = false,
    this.world,
    this.depthPrompt,
    this.regexScripts = const [],
  });

  Map<String, dynamic> toJson() => {
        'talkativeness': talkativeness,
        'fav': fav,
        'world': world,
        'depth_prompt': depthPrompt?.toJson(),
        'regex_scripts': regexScripts.map((e) => e.toJson()).toList(),
      };

  factory CharacterExtensions.fromJson(Map<String, dynamic> json) {
    return CharacterExtensions(
      talkativeness:
          (json['talkativeness'] as num?)?.toDouble() ?? 0.5,
      fav: json['fav'] as bool? ?? false,
      world: json['world'] as String?,
      depthPrompt: json['depth_prompt'] != null
          ? DepthPrompt.fromJson(
              json['depth_prompt'] as Map<String, dynamic>)
          : null,
      regexScripts: (json['regex_scripts'] as List<dynamic>?)
              ?.map(
                  (e) => RegexScript.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// 深度注入配置（对标 SillyTavern #depth_prompt_*）
class DepthPrompt {
  /// 注入深度 0-9999，默认 4（对标 #depth_prompt_depth）
  final int depth;

  /// 注入文本（对标 #depth_prompt_prompt）
  final String prompt;

  /// 注入角色：system/user/assistant（对标 #depth_prompt_role）
  final String role;

  const DepthPrompt({
    this.depth = 4,
    this.prompt = '',
    this.role = 'system',
  });

  Map<String, dynamic> toJson() => {
        'depth': depth,
        'prompt': prompt,
        'role': role,
      };

  factory DepthPrompt.fromJson(Map<String, dynamic> json) {
    return DepthPrompt(
      depth: json['depth'] as int? ?? 4,
      prompt: json['prompt'] as String? ?? '',
      role: json['role'] as String? ?? 'system',
    );
  }
}

/// 正则脚本（对标 SillyTavern regex_scripts）
class RegexScript {
  final String scriptName;
  final String findRegex;
  final String replaceString;
  final bool marked;
  final String? substituteRegex;
  final int trimType;

  const RegexScript({
    this.scriptName = '',
    this.findRegex = '',
    this.replaceString = '',
    this.marked = false,
    this.substituteRegex,
    this.trimType = 0,
  });

  Map<String, dynamic> toJson() => {
        'scriptName': scriptName,
        'findRegex': findRegex,
        'replaceString': replaceString,
        'marked': marked,
        'substituteRegex': substituteRegex,
        'trimType': trimType,
      };

  factory RegexScript.fromJson(Map<String, dynamic> json) {
    return RegexScript(
      scriptName: json['scriptName'] as String? ?? '',
      findRegex: json['findRegex'] as String? ?? '',
      replaceString: json['replaceString'] as String? ?? '',
      marked: json['marked'] as bool? ?? false,
      substituteRegex: json['substituteRegex'] as String?,
      trimType: json['trimType'] as int? ?? 0,
    );
  }
}

/// 世界观书（对标 SillyTavern WorldInfoBook / character_book）
class WorldInfoBook {
  final List<WorldInfoEntry> entries;
  final String name;
  final String description;
  final String? scanDepth;
  final String? tokenBudget;
  final String? recursiveScanning;
  final int? extensions;

  const WorldInfoBook({
    this.entries = const [],
    this.name = '',
    this.description = '',
    this.scanDepth,
    this.tokenBudget,
    this.recursiveScanning,
    this.extensions,
  });

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'name': name,
        'description': description,
        'scanDepth': scanDepth,
        'tokenBudget': tokenBudget,
        'recursiveScanning': recursiveScanning,
        'extensions': extensions,
      };

  factory WorldInfoBook.fromJson(Map<String, dynamic> json) {
    return WorldInfoBook(
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) =>
                  WorldInfoEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      scanDepth: json['scanDepth'] as String?,
      tokenBudget: json['tokenBudget'] as String?,
      recursiveScanning: json['recursiveScanning'] as String?,
      extensions: json['extensions'] as int?,
    );
  }
}

/// 世界观条目（对标 SillyTavern WorldInfoEntry）
/// 完整字段定义见 world_info_entry.dart
class WorldInfoEntry {
  final String uid;
  final String comment;
  final String content;
  final List<String> key;
  final List<String> keysecondary;
  final bool constant;
  final bool vectorized;
  final bool selective;
  final bool disable;
  final int position;
  final int depth;
  final int order;
  final int probability;
  final bool useGroupScoring;
  final int scanDepth;
  final bool caseSensitive;
  final bool matchWholeWords;
  final bool excludeRecursion;
  final bool preventRecursion;
  final int delayUntilRecursion;
  final int? sticky;
  final int? cooldown;
  final int? delay;
  final String? outletName;
  final int role;
  final int entryLogicType;
  final List<String>? triggers;
  final String? automationId;

  const WorldInfoEntry({
    this.uid = '',
    this.comment = '',
    this.content = '',
    this.key = const [],
    this.keysecondary = const [],
    this.constant = false,
    this.vectorized = false,
    this.selective = false,
    this.disable = false,
    this.position = 0,
    this.depth = 4,
    this.order = 100,
    this.probability = 100,
    this.useGroupScoring = false,
    this.scanDepth = 0,
    this.caseSensitive = false,
    this.matchWholeWords = false,
    this.excludeRecursion = false,
    this.preventRecursion = false,
    this.delayUntilRecursion = 0,
    this.sticky,
    this.cooldown,
    this.delay,
    this.outletName,
    this.role = 0,
    this.entryLogicType = 0,
    this.triggers,
    this.automationId,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'comment': comment,
        'content': content,
        'key': key,
        'keysecondary': keysecondary,
        'constant': constant,
        'vectorized': vectorized,
        'selective': selective,
        'disable': disable,
        'position': position,
        'depth': depth,
        'order': order,
        'probability': probability,
        'useGroupScoring': useGroupScoring,
        'scanDepth': scanDepth,
        'caseSensitive': caseSensitive,
        'matchWholeWords': matchWholeWords,
        'excludeRecursion': excludeRecursion,
        'preventRecursion': preventRecursion,
        'delayUntilRecursion': delayUntilRecursion,
        'sticky': sticky,
        'cooldown': cooldown,
        'delay': delay,
        'outletName': outletName,
        'role': role,
        'entryLogicType': entryLogicType,
        'triggers': triggers,
        'automationId': automationId,
      };

  factory WorldInfoEntry.fromJson(Map<String, dynamic> json) {
    return WorldInfoEntry(
      uid: json['uid'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      content: json['content'] as String? ?? '',
      key: (json['key'] as List<dynamic>?)?.cast<String>() ?? [],
      keysecondary:
          (json['keysecondary'] as List<dynamic>?)?.cast<String>() ?? [],
      constant: json['constant'] as bool? ?? false,
      vectorized: json['vectorized'] as bool? ?? false,
      selective: json['selective'] as bool? ?? false,
      disable: json['disable'] as bool? ?? false,
      position: json['position'] as int? ?? 0,
      depth: json['depth'] as int? ?? 4,
      order: json['order'] as int? ?? 100,
      probability: json['probability'] as int? ?? 100,
      useGroupScoring: json['useGroupScoring'] as bool? ?? false,
      scanDepth: json['scanDepth'] as int? ?? 0,
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      matchWholeWords: json['matchWholeWords'] as bool? ?? false,
      excludeRecursion: json['excludeRecursion'] as bool? ?? false,
      preventRecursion: json['preventRecursion'] as bool? ?? false,
      delayUntilRecursion: json['delayUntilRecursion'] as int? ?? 0,
      sticky: json['sticky'] as int?,
      cooldown: json['cooldown'] as int?,
      delay: json['delay'] as int?,
      outletName: json['outletName'] as String?,
      role: json['role'] as int? ?? 0,
      entryLogicType: json['entryLogicType'] as int? ?? 0,
      triggers: (json['triggers'] as List<dynamic>?)?.cast<String>(),
      automationId: json['automationId'] as String?,
    );
  }
}
