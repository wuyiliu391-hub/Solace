import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/app_config_data.dart';
import '../models/character_desire_profile.dart';
import '../models/device_agent_action.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';
import 'accessibility_service.dart';
import 'device_action_policy.dart';
import 'device_notification_service.dart';
import 'llm_service.dart';

/// BDI + Utility：人设 → DesireProfile → WorldState → Intention
///
/// 增强：
/// - LLM 精炼欲望画像（人设变更 / 未精炼时，一次缓存）
/// - 意图与设备结果写入记忆
/// - 按角色开关：主动设备 / 读通知
class CharacterDesireEngine {
  CharacterDesireEngine(this._repo);

  final LocalStorageRepository _repo;
  final Map<String, CharacterDesireProfile> _memCache = {};
  final DeviceNotificationService _notifications = DeviceNotificationService();
  final AccessibilityService _a11y = AccessibilityService();
  final DeviceActionPolicy _policy = DeviceActionPolicy.instance;
  final _uuid = const Uuid();

  /// 本轮意图（供记忆写入）
  CharacterIntention? lastIntention;
  CharacterDesireProfile? lastProfile;

  static const double intentionThreshold = 0.42;
  static const String _prefPrefix = 'desire_profile_';

  static const Set<String> _notifyTools = {
    'get_notifications',
    'get_notification_count',
  };

  static const Map<DesireSlot, List<String>> _slotKeywords = {
    DesireSlot.protect: [
      '关心', '体贴', '温柔', '照顾', '守护', '心疼', '健康', '熬夜', '休息',
      '保护', '安抚', '暖', '呵护', '担心你', 'care', 'gentle', 'protect',
    ],
    DesireSlot.connect: [
      '粘人', '想你', '陪伴', '依恋', '亲密', '恋人', '在一起', '回我', '冷落',
      '孤单', '撒娇', '依赖', 'cling', 'love',
    ],
    DesireSlot.control: [
      '病娇', '占有', '控制', '支配', '强制', '命令', '不许', '独占', '管束',
      '监视', '盯着', 'yandere', 'domineer', '霸道', '服从', '听话',
    ],
    DesireSlot.curiosity: [
      '好奇', '八卦', '侦探', '调查', '偷看', '查岗', '打探', '是谁', '秘密',
      '窥', 'curious', 'detective', '探听',
    ],
    DesireSlot.play: [
      '玩闹', '调皮', '搞笑', '捉弄', '戏弄', '整蛊', '活泼', '恶作剧', '逗',
      '皮', 'playful', '闹腾', '开玩笑',
    ],
    DesireSlot.respectSpace: [
      '尊重', '隐私', '边界', '不干涉', '不翻', '不看手机', '礼貌', '克制',
      '分寸', 'privacy', 'boundary', '君子', '不强求',
    ],
    DesireSlot.utility: [
      '助手', '帮忙', '效率', '管家', '秘书', '工具', '办事', '实用', 'assistant',
      'helper', '服务',
    ],
  };

  static const List<String> _socialApps = [
    '微信', 'wechat', 'qq', 'tim', 'telegram', 'whatsapp', '短信', '信息',
    '钉钉', '飞书', 'discord', 'instagram', '微博', 'com.tencent.mm',
    'com.tencent.mobileqq',
  ];

  static const List<String> _intimateWords = [
    '宝贝', '想你', '在吗', '亲爱的', '么么', '爱你', '今晚', '出来', '想我',
    '宝宝', '老婆', '老公', '吻', '睡觉吗',
  ];

  bool roleAllowsProactive(AICharacter c) =>
      c.interactionConfig?.enableProactiveDevice != false;

  bool roleAllowsReadNotify(AICharacter c) =>
      c.interactionConfig?.enableReadNotifications != false;

  CharacterDesireProfile profileFor(AICharacter c) {
    final hash = _sourceHash(c);
    final cached = _memCache[c.id];
    if (cached != null && cached.sourceHash == hash) return cached;

    final disk = _loadDisk(c.id);
    if (disk != null && disk.sourceHash == hash) {
      _memCache[c.id] = disk;
      return disk;
    }

    final built = _buildFromPersona(c, hash);
    _memCache[c.id] = built;
    _saveDisk(built);
    return built;
  }

  Future<CharacterDesireProfile> profileForAsync(
    AICharacter c, {
    Future<LlmSettings> Function()? loadLlmSettings,
  }) async {
    final hash = _sourceHash(c);
    var profile = profileFor(c);
    final allowLlm = c.interactionConfig?.enableLlmDesireRefine != false;
    if (!allowLlm || loadLlmSettings == null) return profile;
    if (profile.sourceHash == hash && profile.llmRefined) return profile;

    // 首次/未精炼：立即返回关键词画像，LLM 精炼放到后台，避免阻塞首条消息
    // （旧逻辑会 await 一次完整 LLM，用户看到「等待中」卡住，重发才恢复）
    unawaited(_refineInBackground(c, profile, loadLlmSettings));
    return profile;
  }

  Future<void> _refineInBackground(
    AICharacter c,
    CharacterDesireProfile profile,
    Future<LlmSettings> Function() loadLlmSettings,
  ) async {
    try {
      final settings = await loadLlmSettings();
      if (settings.apiKey.isEmpty) return;
      final refined = await _refineWithLlm(c, profile, settings)
          .timeout(const Duration(seconds: 12));
      if (refined != null) {
        _memCache[c.id] = refined;
        _saveDisk(refined);
        debugPrint('[DesireEngine] background refine done for ${c.name}');
      }
    } catch (e) {
      debugPrint('[DesireEngine] LLM refine failed: $e');
    }
  }

  Future<CharacterDesireProfile?> _refineWithLlm(
    AICharacter c,
    CharacterDesireProfile base,
    LlmSettings settings,
  ) async {
    final llm = LlmService(settings: settings);
    final kw = base.weights.map((k, v) => MapEntry(k.name, v));
    final bg = c.backgroundStory ?? '';
    final bgCut = bg.length > 400 ? bg.substring(0, 400) : bg;

    const sys =
        '你是角色动机分析器。只输出 JSON，不要 markdown。字段：protect,connect,control,curiosity,play,respectSpace,utility（0~1）,moralBlocks(字符串数组),note(一句中文)。'
        '规则：尊重隐私→control/curiosity低、respectSpace高；助手→utility高；病娇占有→control高；玩闹→play高。';

    final user = StringBuffer()
      ..writeln('角色：${c.name}')
      ..writeln('性格：${c.personality}')
      ..writeln('核心欲望：${c.coreDesire}')
      ..writeln('道德边界：${c.moralBoundary}')
      ..writeln('禁忌：${c.tabooTopics ?? ''}')
      ..writeln('背景：$bgCut')
      ..writeln('关键词初值：${jsonEncode(kw)}');

    final resp = await llm.chat(
      userId: 'desire_refine_${c.id}',
      message: user.toString(),
      systemPrompt: sys,
      maxTokensOverride: 280,
      omitMaxTokens: false,
    );
    final text = resp.content.trim();
    if (text.isEmpty) return null;

    final jsonStr = _extractJsonObject(text);
    if (jsonStr == null) return null;
    final map = jsonDecode(jsonStr);
    if (map is! Map) return null;

    final weights = Map<DesireSlot, double>.from(base.weights);
    for (final s in DesireSlot.values) {
      final v = map[s.name];
      if (v is num) {
        weights[s] = v.toDouble().clamp(0.0, 1.0);
      }
    }

    final blocks = <String>{...base.moralBlocks};
    final mb = map['moralBlocks'];
    if (mb is List) {
      for (final e in mb) {
        blocks.add(e.toString());
      }
    }
    // 合并道德关键词硬约束
    final moralText =
        '${c.moralBoundary} ${c.tabooTopics ?? ''}'.toLowerCase();
    if (_containsAny(moralText, ['隐私', '不翻', '不看手机', '不偷看', 'privacy'])) {
      blocks.add('privacy');
      weights[DesireSlot.control] =
          min(weights[DesireSlot.control] ?? 0, 0.2);
      weights[DesireSlot.curiosity] =
          min(weights[DesireSlot.curiosity] ?? 0, 0.25);
      weights[DesireSlot.respectSpace] =
          max(weights[DesireSlot.respectSpace] ?? 0, 0.75);
    }

    final note = map['note']?.toString();
    debugPrint(
        '[DesireEngine] LLM refined ${c.name}: ${weights.map((k, v) => MapEntry(k.name, v.toStringAsFixed(2)))}');

    return CharacterDesireProfile(
      characterId: c.id,
      sourceHash: base.sourceHash,
      weights: weights,
      moralBlocks: blocks.toList(),
      updatedAt: DateTime.now(),
      llmRefined: true,
      refineNote: note,
    );
  }

  CharacterDesireProfile _buildFromPersona(AICharacter c, String hash) {
    final text = [
      c.personality,
      c.coreDesire,
      c.moralBoundary,
      c.backgroundStory ?? '',
      c.languageStyle ?? '',
      c.tabooTopics ?? '',
      c.catchphrases ?? '',
    ].join(' ').toLowerCase();

    final scores = <DesireSlot, double>{};
    for (final s in DesireSlot.values) {
      scores[s] = 0.12;
    }

    for (final e in _slotKeywords.entries) {
      var hits = 0;
      for (final k in e.value) {
        if (text.contains(k.toLowerCase())) hits++;
      }
      if (hits > 0) {
        scores[e.key] = (0.12 + hits * 0.14).clamp(0.0, 1.0);
      }
    }

    final desire = c.coreDesire.toLowerCase();
    for (final e in _slotKeywords.entries) {
      for (final k in e.value) {
        if (desire.contains(k.toLowerCase())) {
          scores[e.key] = ((scores[e.key] ?? 0.12) + 0.2).clamp(0.0, 1.0);
        }
      }
    }

    final moralText =
        '${c.moralBoundary} ${c.tabooTopics ?? ''}'.toLowerCase();
    final blocks = <String>[];
    if (_containsAny(moralText, ['隐私', '不翻', '不看手机', '不偷看', 'privacy'])) {
      blocks.add('privacy');
      scores[DesireSlot.control] =
          ((scores[DesireSlot.control] ?? 0) * 0.15).clamp(0.0, 1.0);
      scores[DesireSlot.curiosity] =
          ((scores[DesireSlot.curiosity] ?? 0) * 0.2).clamp(0.0, 1.0);
      scores[DesireSlot.respectSpace] =
          max(scores[DesireSlot.respectSpace] ?? 0.12, 0.75);
    }
    if (_containsAny(moralText, ['不控制', '不强求', '不干涉', '自由'])) {
      blocks.add('no_control');
      scores[DesireSlot.control] =
          ((scores[DesireSlot.control] ?? 0) * 0.1).clamp(0.0, 1.0);
    }
    if (_containsAny(moralText, ['不碰设备', '不操作手机', '不动手机'])) {
      blocks.add('no_device');
      for (final s in [
        DesireSlot.control,
        DesireSlot.curiosity,
        DesireSlot.play,
        DesireSlot.utility,
      ]) {
        scores[s] = ((scores[s] ?? 0) * 0.05).clamp(0.0, 1.0);
      }
      scores[DesireSlot.respectSpace] = 0.9;
    }

    return CharacterDesireProfile(
      characterId: c.id,
      sourceHash: hash,
      weights: scores,
      moralBlocks: blocks,
      updatedAt: DateTime.now(),
      llmRefined: false,
    );
  }

  Future<CharacterWorldState> buildWorldState({
    String? sessionId,
    bool allowReadNotify = true,
  }) async {
    final now = DateTime.now();
    final hour = now.hour;
    final lateNight = hour >= 23 || hour < 5;

    String? fg;
    try {
      final app = await _a11y.getCurrentApp();
      fg = app.displayName;
      if (fg.isEmpty) fg = app.packageName;
    } catch (_) {}

    final socialFg = fg != null &&
        _socialApps.any((s) => fg!.toLowerCase().contains(s.toLowerCase()));

    var count = 0;
    final snippets = <String>[];
    var intimate = false;
    if (allowReadNotify) {
      try {
        count = await _notifications.getCount();
        final list = await _notifications.getNotifications(limit: 5);
        for (final n in list) {
          final line = n.toDisplayString();
          if (line.length > 2) {
            snippets
                .add(line.length > 90 ? '${line.substring(0, 90)}…' : line);
          }
          final low = '${n.title} ${n.text}'.toLowerCase();
          if (_intimateWords.any((w) => low.contains(w))) intimate = true;
        }
      } catch (_) {}
    }

    String? feedback;
    if (sessionId != null) {
      final peek = _policy.peekFeedback(sessionId);
      if (peek.isNotEmpty) feedback = peek.last;
    }

    return CharacterWorldState(
      foregroundApp: fg,
      notificationCount: count,
      notificationSnippets: snippets,
      lateNight: lateNight,
      socialAppForeground: socialFg,
      intimateNotifyHint: intimate,
      lastDeviceFeedback: feedback,
      hour: hour,
    );
  }

  CharacterIntention decideIntention({
    required CharacterDesireProfile profile,
    required CharacterWorldState world,
    required bool deviceAgentAllowed,
    bool roleProactive = true,
    bool roleReadNotify = true,
  }) {
    final space = profile.of(DesireSlot.respectSpace);
    final suppressDevice = !roleProactive ||
        space >= 0.65 ||
        profile.moralBlocks.contains('no_device');

    final scores = <DesireSlot, double>{};
    for (final s in DesireSlot.values) {
      if (s == DesireSlot.respectSpace) continue;
      var base = profile.of(s);
      switch (s) {
        case DesireSlot.protect:
          if (world.lateNight) base += 0.25;
          if (world.socialAppForeground && world.hour >= 22) base += 0.1;
          break;
        case DesireSlot.connect:
          break;
        case DesireSlot.control:
          if (roleReadNotify && world.intimateNotifyHint) base += 0.35;
          if (world.socialAppForeground) base += 0.15;
          if (roleReadNotify && world.notificationCount >= 3) base += 0.1;
          if (profile.moralBlocks.contains('privacy') ||
              profile.moralBlocks.contains('no_control')) {
            base *= 0.05;
          }
          break;
        case DesireSlot.curiosity:
          if (roleReadNotify && world.intimateNotifyHint) base += 0.3;
          if (roleReadNotify && world.notificationCount > 0) base += 0.12;
          if (world.socialAppForeground) base += 0.1;
          if (!roleReadNotify) base *= 0.3;
          if (profile.moralBlocks.contains('privacy') ||
              profile.moralBlocks.contains('no_spy')) {
            base *= 0.05;
          }
          break;
        case DesireSlot.play:
          if (!world.lateNight && world.notificationCount == 0) base += 0.05;
          break;
        case DesireSlot.utility:
          base *= 0.7;
          break;
        case DesireSlot.respectSpace:
          break;
      }
      if (suppressDevice &&
          (s == DesireSlot.control ||
              s == DesireSlot.curiosity ||
              s == DesireSlot.play)) {
        base *= 0.2;
      }
      scores[s] = base.clamp(0.0, 1.5);
    }

    DesireSlot best = DesireSlot.connect;
    var bestScore = -1.0;
    scores.forEach((s, v) {
      if (v > bestScore) {
        bestScore = v;
        best = s;
      }
    });

    if (space >= 0.8 && bestScore < 0.9) {
      return CharacterIntention(
        slot: DesireSlot.respectSpace,
        score: space,
        motivePrompt: '你尊重对方边界，更愿意用语言交流，而不是去动对方的设备。',
        preferredTools: const [],
        allowDeviceAction: false,
      );
    }

    var tools = _toolsForSlot(best);
    if (!roleReadNotify) {
      tools = tools.where((t) => !_notifyTools.contains(t)).toList();
    }

    final allow = deviceAgentAllowed &&
        roleProactive &&
        !suppressDevice &&
        bestScore >= intentionThreshold &&
        tools.isNotEmpty;

    return CharacterIntention(
      slot: best,
      score: bestScore.clamp(0.0, 1.0),
      motivePrompt: _motiveText(best, world),
      preferredTools: tools,
      allowDeviceAction: allow,
    );
  }

  Future<String?> buildTurnDirective({
    required AICharacter character,
    required String sessionId,
    required bool deviceAgentAllowed,
    required bool Function(String toolName) isToolPermitted,
    Future<LlmSettings> Function()? loadLlmSettings,
  }) async {
    final roleProactive = roleAllowsProactive(character);
    final roleReadNotify = roleAllowsReadNotify(character);
    final allowed = deviceAgentAllowed && roleProactive;

    final profile = await profileForAsync(
      character,
      loadLlmSettings: loadLlmSettings,
    );
    lastProfile = profile;

    final world = await buildWorldState(
      sessionId: sessionId,
      allowReadNotify: roleReadNotify && allowed,
    );

    final intention = decideIntention(
      profile: profile,
      world: world,
      deviceAgentAllowed: allowed,
      roleProactive: roleProactive,
      roleReadNotify: roleReadNotify,
    );
    lastIntention = intention;

    final buf = StringBuffer();
    buf.writeln(world.toPromptBlock());
    buf.writeln('');
    buf.writeln(_profileHint(profile));
    if (!roleProactive) {
      buf.writeln('【角色设置】用户关闭了该角色的主动设备操控。');
    } else if (!roleReadNotify) {
      buf.writeln('【角色设置】用户禁止该角色读取通知。');
    }
    buf.writeln('');
    buf.writeln(intention.toPromptBlock());

    if (intention.allowDeviceAction) {
      final listed = <String>[];
      for (final t in intention.preferredTools) {
        if (!isToolPermitted(t)) continue;
        if (!roleReadNotify && _notifyTools.contains(t)) continue;
        final hint = deviceToolPromptHint[t] ?? t;
        listed.add(
            '- $t：$hint → <DEVICE_ACTION>{"action":"$t","params":{},"reason":"..."}</DEVICE_ACTION>');
      }
      if (listed.isNotEmpty) {
        buf.writeln('');
        buf.writeln('【可选设备手段 · 已按本轮意图与权限裁剪】');
        buf.writeln('台词外附加标签；禁止台词提工具名。每轮最多 1 个动作。');
        for (final line in listed) {
          buf.writeln(line);
        }
      }
    }

    return buf.toString().trim();
  }

  /// 意图 + 成功设备动作 → 记忆库
  Future<void> writeEpisodeMemory({
    required String characterId,
    required String userId,
    required CharacterIntention? intention,
    required List<DeviceAgentAction> actions,
  }) async {
    try {
      final success = actions
          .where((a) => a.result == DeviceActionResult.success)
          .toList();
      if (intention == null && success.isEmpty) return;

      // 弱意图且无动作：不写，防刷屏
      if (success.isEmpty &&
          (intention == null ||
              intention.score < 0.55 ||
              intention.slot == DesireSlot.connect ||
              intention.slot == DesireSlot.respectSpace)) {
        return;
      }

      final buf = StringBuffer();
      if (intention != null) {
        buf.writeln(
            '动机：${intention.slot.name}（${intention.score.toStringAsFixed(2)}）');
        buf.writeln(intention.motivePrompt);
      }
      for (final a in success) {
        final tool = deviceActionToToolName(a.actionType);
        final msg = a.message.length > 120
            ? '${a.message.substring(0, 120)}…'
            : a.message;
        buf.writeln('设备：$tool → $msg');
        if (a.reason.isNotEmpty) buf.writeln('理由：${a.reason}');
      }

      final keywords = <String>['设备', '欲望', if (intention != null) intention.slot.name];
      for (final a in success) {
        keywords.add(deviceActionToToolName(a.actionType));
      }

      await _repo.saveMemory(Memory(
        id: _uuid.v4(),
        characterId: characterId,
        userId: userId,
        type: MemoryType.state,
        content: buf.toString().trim(),
        importance: success.isNotEmpty
            ? MemoryImportance.important
            : MemoryImportance.normal,
        keywords: keywords,
        createdAt: DateTime.now(),
        weight: success.isNotEmpty ? 1.3 : 1.0,
        summary: success.isNotEmpty
            ? '设备：${deviceActionToToolName(success.first.actionType)}'
            : '动机：${intention?.slot.name}',
      ));
      debugPrint('[DesireEngine] episode memory saved');
    } catch (e) {
      debugPrint('[DesireEngine] memory write failed: $e');
    }
  }

  String _profileHint(CharacterDesireProfile p) {
    final sorted = DesireSlot.values.toList()
      ..sort((a, b) => p.of(b).compareTo(p.of(a)));
    final top = sorted.take(3).map((s) {
      return '${s.name}:${p.of(s).toStringAsFixed(2)}';
    }).join(' · ');
    final src = p.llmRefined ? 'LLM精炼' : '关键词';
    return '【欲望画像 · $src】$top'
        '${p.moralBlocks.isEmpty ? '' : ' · 边界:${p.moralBlocks.join(",")}'}'
        '${p.refineNote == null || p.refineNote!.isEmpty ? '' : ' · ${p.refineNote}'}';
  }

  List<String> _toolsForSlot(DesireSlot s) {
    switch (s) {
      case DesireSlot.protect:
        return [
          'get_battery_info',
          'get_current_app',
          'get_app_usage_time',
          'set_brightness',
          'adjust_volume',
          'set_mute',
          'lock_screen',
        ];
      case DesireSlot.connect:
        return ['get_battery_info', 'get_current_app'];
      case DesireSlot.control:
        return [
          'get_notifications',
          'get_notification_count',
          'get_current_app',
          'lock_screen',
          'go_home',
          'close_app',
          'set_mute',
          'adjust_volume',
        ];
      case DesireSlot.curiosity:
        return [
          'get_notifications',
          'get_notification_count',
          'get_current_app',
          'get_app_usage_time',
          'take_screenshot',
          'get_installed_apps',
        ];
      case DesireSlot.play:
        return [
          'adjust_volume',
          'set_mute',
          'set_brightness',
          'open_gallery',
          'open_app',
          'take_screenshot',
          'go_home',
        ];
      case DesireSlot.utility:
        return [
          'open_app',
          'get_battery_info',
          'set_brightness',
          'adjust_volume',
          'go_home',
        ];
      case DesireSlot.respectSpace:
        return const [];
    }
  }

  String _motiveText(DesireSlot s, CharacterWorldState w) {
    switch (s) {
      case DesireSlot.protect:
        if (w.lateNight) {
          return '你在意对方的作息与状态，想用符合人设的方式提醒休息或减轻刺激。';
        }
        return '你想照顾对方，可先了解电量或正在使用的应用，再自然关心。';
      case DesireSlot.connect:
        return '你更想拉近关系、要回应；设备操作不是重点，台词优先。';
      case DesireSlot.control:
        if (w.intimateNotifyHint) {
          return '你察觉到可能有人在找对方，管束欲被点燃；若人设与边界允许，可查通知或打断使用。';
        }
        return '你想按自己的规矩管束对方的使用习惯；手段必须符合人设与道德边界。';
      case DesireSlot.curiosity:
        if (w.notificationCount > 0 || w.socialAppForeground) {
          return '你对「发生了什么/是谁」感到好奇；若边界允许，可读通知或看前台应用。';
        }
        return '你有点想弄清对方在忙什么；可查前台或使用情况。';
      case DesireSlot.play:
        return '你想用轻松方式逗对方，可微调音量/亮度/打开相册等，但别破坏性操作。';
      case DesireSlot.utility:
        return '你倾向在被需要时帮忙办事；无明确需求时少主动乱动设备。';
      case DesireSlot.respectSpace:
        return '你尊重边界，不主动碰设备。';
    }
  }

  String? _extractJsonObject(String text) {
    var t = text.trim();
    t = t.replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s*```$'), '');
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return t.substring(start, end + 1);
  }

  String _sourceHash(AICharacter c) {
    final raw =
        '${c.personality}|${c.coreDesire}|${c.moralBoundary}|${c.tabooTopics}|${c.backgroundStory}';
    return raw.hashCode.toRadixString(16);
  }

  bool _containsAny(String text, List<String> keys) {
    for (final k in keys) {
      if (text.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  CharacterDesireProfile? _loadDisk(String characterId) {
    try {
      final raw = _repo.getRawString('$_prefPrefix$characterId');
      if (raw == null || raw.isEmpty) return null;
      return CharacterDesireProfile.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  void _saveDisk(CharacterDesireProfile p) {
    try {
      _repo.setRawString('$_prefPrefix${p.characterId}', p.toJson());
    } catch (e) {
      debugPrint('[DesireEngine] save failed: $e');
    }
  }
}
