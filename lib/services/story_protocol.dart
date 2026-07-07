import 'dart:convert';
import '../models/story_scene.dart';

/// AI 结构化输出的解析结果
class StoryAIResult {
  final String narrative; // 正文（已剔除 JSON 块）
  final List<String> branchOptions; // 候选分支
  final StorySceneDelta? sceneDelta; // 参数面板更新

  const StoryAIResult({
    required this.narrative,
    this.branchOptions = const [],
    this.sceneDelta,
  });
}

/// 场景参数增量（AI 本轮给出的新值，null 表示不变）
class StorySceneDelta {
  final int? affinity;
  final int? emotionValue;
  final String? emotionLabel;
  final String? bodyState;
  final String? psychState;
  final String? actionState;
  final String? location;
  final String? atmosphere;
  final List<ScenePresence>? presentCharacters;

  const StorySceneDelta({
    this.affinity,
    this.emotionValue,
    this.emotionLabel,
    this.bodyState,
    this.psychState,
    this.actionState,
    this.location,
    this.atmosphere,
    this.presentCharacters,
  });

  /// 把增量应用到旧快照，得到新快照
  StoryScene applyTo(StoryScene old) {
    return old.copyWith(
      affinity: affinity ?? old.affinity,
      emotionValue: emotionValue ?? old.emotionValue,
      emotionLabel: emotionLabel ?? old.emotionLabel,
      bodyState: bodyState ?? old.bodyState,
      psychState: psychState ?? old.psychState,
      actionState: actionState ?? old.actionState,
      location: location ?? old.location,
      atmosphere: atmosphere ?? old.atmosphere,
      presentCharacters: presentCharacters ?? old.presentCharacters,
      updatedAt: DateTime.now(),
    );
  }
}

/// 故事书 AI 输出协议 — 定义结构化格式并解析
class StoryProtocol {
  StoryProtocol._();

  /// 注入到 system prompt 的输出格式约定
  static const String outputInstruction = '''
【输出格式 — 必须严格遵守】
先输出剧情正文（自然流畅的叙事文字，不要出现任何标记或代码）。
正文写完后，另起一行，输出一个被 <STATE>...</STATE> 包裹的 JSON 块，用于刷新状态面板与分支选项。JSON 字段如下（数值 0~100，文本简短）：
<STATE>
{
  "affinity": 好感度整数,
  "emotionValue": 情绪度整数,
  "emotionLabel": "情绪文字标签",
  "bodyState": "主视角人物身体状态",
  "psychState": "主视角人物心理状态",
  "actionState": "主视角人物行动状态",
  "location": "当前地点",
  "atmosphere": "场景环境氛围",
  "present": [{"name":"在场人物名","affinity":好感整数,"emotion":"情绪","state":"状态简讯"}],
  "branches": ["可选分支1", "可选分支2", "可选分支3"]
}
</STATE>
只输出一个 STATE 块。branches 给 2-4 个，引导剧情走向；若剧情自然结束可给空数组。''';

  static final RegExp _stateBlock =
      RegExp(r'<STATE>\s*([\s\S]*?)\s*</STATE>', caseSensitive: false);

  /// 解析 AI 完整输出：拆出正文、分支、场景增量
  static StoryAIResult parse(String raw) {
    final match = _stateBlock.firstMatch(raw);
    if (match == null) {
      return StoryAIResult(narrative: raw.trim());
    }

    final narrative = raw.replaceRange(match.start, match.end, '').trim();
    final jsonStr = match.group(1)?.trim() ?? '';

    List<String> branches = [];
    StorySceneDelta? delta;

    try {
      final map = jsonDecode(_repairJson(jsonStr)) as Map<String, dynamic>;

      final rawBranches = map['branches'];
      if (rawBranches is List) {
        branches = rawBranches
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      List<ScenePresence>? present;
      final rawPresent = map['present'];
      if (rawPresent is List) {
        present = rawPresent.whereType<Map>().map((e) {
          final m = Map<String, dynamic>.from(e);
          return ScenePresence(
            characterId: m['characterId'] as String? ?? '',
            name: m['name'] as String? ?? '',
            affinity: (m['affinity'] as num?)?.toInt() ?? 50,
            emotion: m['emotion'] as String? ?? '',
            state: m['state'] as String? ?? '',
          );
        }).toList();
      }

      delta = StorySceneDelta(
        affinity: (map['affinity'] as num?)?.toInt(),
        emotionValue: (map['emotionValue'] as num?)?.toInt(),
        emotionLabel: (map['emotionLabel'] as String?)?.trim(),
        bodyState: (map['bodyState'] as String?)?.trim(),
        psychState: (map['psychState'] as String?)?.trim(),
        actionState: (map['actionState'] as String?)?.trim(),
        location: (map['location'] as String?)?.trim(),
        atmosphere: (map['atmosphere'] as String?)?.trim(),
        presentCharacters: present,
      );
    } catch (_) {
      // JSON 解析失败：正文仍可用，参数保持不变
    }

    return StoryAIResult(
      narrative: narrative,
      branchOptions: branches,
      sceneDelta: delta,
    );
  }

  /// 流式过程中，剥离尚未闭合的 <STATE> 块，只显示正文部分
  static String stripStateForDisplay(String partial) {
    final idx = partial.indexOf('<STATE>');
    if (idx >= 0) return partial.substring(0, idx).trim();
    // 兜底：末尾正在生成 <STAT... 时也隐藏
    final lower = partial.toLowerCase();
    final partialTag = RegExp(r'<st?a?t?e?$').firstMatch(lower.length > 10
        ? lower.substring(lower.length - 8)
        : lower);
    if (partialTag != null) {
      return partial.substring(0, partial.length - partialTag.group(0)!.length).trim();
    }
    return partial;
  }

  /// 轻量修复 LLM 常见 JSON 瑕疵（尾逗号）
  static String _repairJson(String s) {
    return s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
  }
}
