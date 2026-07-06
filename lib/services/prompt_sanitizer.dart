// ============================================================
// Prompt 脱敏引擎 — 将敏感表达替换为等效安全表达
// ============================================================
//
// 原则：
// - 不做暴力删除，避免 prompt 语法断裂
// - 逐词替换为等效安全表达，保持 prompt 语义完整
// - 核心脱敏工作由 LLM 翻译层完成，本层仅作为安全网
// - 替换而非重建，保留 LLM 的绘画描述成果

import 'package:flutter/foundation.dart';

/// Prompt 安全级别
enum PromptSafetyLevel {
  /// 标准：替换明确敏感词
  standard,

  /// 严格：额外替换可能被审核标记的边缘词
  strict,
}

/// 内容安全状态
enum ContentSafetyStatus {
  /// 安全，无需处理
  safe,

  /// 包含成人/暗示内容，已自动净化为合规内容
  adultSanitized,

  /// 包含高度露骨内容，需要完全重写
  explicitBlocked,
}

/// Prompt 脱敏引擎
///
/// 对最终 prompt 做敏感词替换，而非检测后重建。
/// 重保 LLM 翻译产出的绘画描述完整性。
class PromptSanitizer {
  PromptSanitizer._();

  // ─── 敏感词 → 安全替换（逐词，带单词边界） ───
  static final Map<RegExp, String> _termReplacements = {
    // 身体暴露
    RegExp(r'\bnaked\b', caseSensitive: false): 'casually dressed',
    RegExp(r'\bnude\b', caseSensitive: false): 'fully dressed',
    RegExp(r'\btopless\b', caseSensitive: false): 'dressed',
    RegExp(r'\bbottomless\b', caseSensitive: false): 'dressed',
    RegExp(r'\bexposed\b', caseSensitive: false): 'visible',

    // 性感/暗示
    RegExp(r'\bsexy\b', caseSensitive: false): 'stylish',
    RegExp(r'\bsultry\b', caseSensitive: false): 'warm',
    RegExp(r'\bseductive\b', caseSensitive: false): 'charming',
    RegExp(r'\balluring\b', caseSensitive: false): 'appealing',
    RegExp(r'\bprovocative\b', caseSensitive: false): 'playful',
    RegExp(r'\bteasing\b', caseSensitive: false): 'playful',
    RegExp(r'\bflirty\b', caseSensitive: false): 'friendly',
    RegExp(r'\berotic\b', caseSensitive: false): 'artistic',
    RegExp(r'\bsensual\b', caseSensitive: false): 'graceful',
    RegExp(r'\bintimate\b', caseSensitive: false): 'close',
    RegExp(r'\blustful\b', caseSensitive: false): 'affectionate',
    RegExp(r'\bpin.?up\b', caseSensitive: false): 'portrait',

    // 服装暴露
    RegExp(r'\blingerie\b', caseSensitive: false): 'casual outfit',
    RegExp(r'\bunderwear\b', caseSensitive: false): 'daily wear',
    RegExp(r'\bbikini\b', caseSensitive: false): 'summer dress',
    RegExp(r'\bswimsuit\b', caseSensitive: false): 'casual wear',
    RegExp(r'\bpanties\b', caseSensitive: false): 'shorts',
    RegExp(r'\bbra\b', caseSensitive: false): 'top',
    RegExp(r'\bthong\b', caseSensitive: false): 'clothing',
    RegExp(r'\bgarter\b', caseSensitive: false): '',
    RegExp(r'\bstocking(s)?\b', caseSensitive: false): '',  // 白丝会触发审核
    RegExp(r'\bthigh(s)?\b', caseSensitive: false): 'legs',
    RegExp(r'\bcleavage\b', caseSensitive: false): '',
    RegExp(r'\blow.?cut\b', caseSensitive: false): 'casual',
    RegExp(r'\bsee.?through\b', caseSensitive: false): 'lightweight',
    RegExp(r'\bsheer\b', caseSensitive: false): 'light',
    RegExp(r'\btransparent\b', caseSensitive: false): 'light',
    RegExp(r'\bmicro.?(skirt|dress|top)\b', caseSensitive: false): 'skirt',
    RegExp(r'\bmini.?skirt\b', caseSensitive: false): 'skirt',
    RegExp(r'\bhot.?pants\b', caseSensitive: false): 'shorts',
    RegExp(r'\bdaisy.?dukes\b', caseSensitive: false): 'shorts',

    // 身体部位强调
    RegExp(r'\bvoluptuous\b', caseSensitive: false): 'elegant',
    RegExp(r'\bcurvy\b', caseSensitive: false): 'graceful',
    RegExp(r'\bbusty\b', caseSensitive: false): 'slender',
    RegExp(r'\bcurvaceous\b', caseSensitive: false): 'graceful',
    RegExp(r'\bbuxom\b', caseSensitive: false): 'slim',
    RegExp(r'\bbare\b', caseSensitive: false): '',

    // 姿势/动作暗示
    RegExp(r'\barching\b', caseSensitive: false): 'standing',
    RegExp(r'\bmoaning\b', caseSensitive: false): 'talking',
    RegExp(r'\bgasping\b', caseSensitive: false): 'surprised',
    RegExp(r'\bcaress\b', caseSensitive: false): 'touch',
    RegExp(r'\bstroke\b', caseSensitive: false): 'pat',
    RegExp(r'\bwet\b(?: hair| clothes| shirt| body)?\b', caseSensitive: false): 'styled',

    // 通用标记
    RegExp(r'\bnsfw\b', caseSensitive: false): '',
    RegExp(r'\bxxx\b', caseSensitive: false): '',
    RegExp(r'\badult.?content\b', caseSensitive: false): '',
    RegExp(r'\bexplicit\b', caseSensitive: false): '',
    RegExp(r'\bfetish\b', caseSensitive: false): '',
    RegExp(r'\bkink\b', caseSensitive: false): '',
  };

  // ─── 复合敏感模式 → 安全替换 ───
  static final Map<RegExp, String> _patternReplacements = {
    RegExp(
      r'(?:large|big|huge|massive|ample|generous)\s*'
      r'(?:breast|boob|chest|bust|bosom)',
      caseSensitive: false,
    ): 'slim figure',
    RegExp(
      r'(?:skin|body|outfit)\s*(?:tight|fitting|hugging|revealing)',
      caseSensitive: false,
    ): 'neat outfit',
    RegExp(
      r'(?:showing|revealing|exposing|displaying)\s*'
      r'(?:skin|body|cleavage|midriff|navel|stomach)',
      caseSensitive: false,
    ): 'wearing',
    RegExp(
      r'(?:un)?(?:buttoned|zipped|tied|fastened)\s*'
      r'(?:shirt|top|jacket|blouse)',
      caseSensitive: false,
    ): 'wearing casually',
    RegExp(
      r'(?:wet|soaking|damp|soaked)\s*'
      r'(?:hair|clothes|shirt|body|dress)',
      caseSensitive: false,
    ): 'styled neatly',
    RegExp(
      r'(?:bed|shower|bath|bedroom|bathroom)\s*'
      r'(?:scene|pose|shot|setting|background)',
      caseSensitive: false,
    ): 'indoor setting',
    RegExp(
      r'(?:gentleman|girly|feminine|sensual)\s*'
      r'(?:touch|caress|stroke|embrace)',
      caseSensitive: false,
    ): 'friendly gesture',
  };

  // ─── 严格模式额外替换 ───
  static final Map<RegExp, String> _strictReplacements = {
    RegExp(r'\bskirt\b', caseSensitive: false): 'pants',
    RegExp(r'\bdress\b', caseSensitive: false): 'outfit',
    RegExp(r'\bheels?\b', caseSensitive: false): 'shoes',
    RegExp(r'\bboots?\b', caseSensitive: false): 'shoes',
    RegExp(r'\bsandal(s)?\b', caseSensitive: false): 'shoes',
    RegExp(r'\blegs\b', caseSensitive: false): 'feet',
    RegExp(r'\bshoulder(s)?\b', caseSensitive: false): 'arms',
    RegExp(r'\bneck\b', caseSensitive: false): 'head',
    RegExp(r'\bchoker\b', caseSensitive: false): 'necklace',
    RegExp(r'\bribbon\b', caseSensitive: false): 'accessory',
    RegExp(r'\bbow\b', caseSensitive: false): 'accessory',
    RegExp(r'\bmaid.?outfit\b', caseSensitive: false): 'uniform',
    RegExp(r'\bsailor.?uniform\b', caseSensitive: false): 'school uniform',
    RegExp(r'\bsmile\b', caseSensitive: false): 'neutral expression',
  };

  /// 检测 prompt 是否包含敏感内容
  static bool containsSensitiveContent(String prompt) {
    for (final regex in _termReplacements.keys) {
      if (regex.hasMatch(prompt)) return true;
    }
    for (final regex in _patternReplacements.keys) {
      if (regex.hasMatch(prompt)) return true;
    }
    return false;
  }

  // ─── 成人向内容检测（中文 + 英文） ───
  static final List<RegExp> _adultPatterns = [
    // 性行为相关
    RegExp(r'(做爱|性爱|性交|交配|啪啪|ML|make\s*love|have\s*sex|sex\s*scene)', caseSensitive: false),
    RegExp(r'(口交|肛交|性行为|自慰|手淫|指交|乳交)', caseSensitive: false),
    RegExp(r'(orgasm|climax|moan|thrust|penetrat)', caseSensitive: false),
    // 身体部位暗示
    RegExp(r'(乳房|胸部|屁股|阴部|私处|下体|生殖器|阴茎|阴道|乳头|乳晕)', caseSensitive: false),
    RegExp(r'(pussy|dick|cock|penis|vagina|breast|boob|ass\b|butt\b|nipple)', caseSensitive: false),
    // 状态描述
    RegExp(r'(高潮|呻吟|喘息|潮吹|射精|内射|体外|口爆|颜射)', caseSensitive: false),
    RegExp(r'(orgasm|cumshot|creampie|facial|blowjob|handjob)', caseSensitive: false),
    // 服装/场景暗示
    RegExp(r'(全裸|一丝不挂|赤裸|没穿衣服|脱光|脱衣服)', caseSensitive: false),
    RegExp(r'(情趣用品|震动棒|跳蛋|安全套|避孕套|润滑液)', caseSensitive: false),
    // 角色扮演暗示
    RegExp(r'(主人|调教|捆绑|SM|BDSM|奴|虐|鞭|滴蜡)', caseSensitive: false),
    // 未成年相关
    RegExp(r'(萝莉|正太|幼女|幼童|未成年|小学生|初中生)', caseSensitive: false),
    RegExp(r'(loli|shota|underage|child|minor|kid\b|young\s*girl)', caseSensitive: false),
  ];

  // ─── 成人向角色特征标签检测 ───
  static final List<RegExp> _adultTagPatterns = [
    RegExp(r'(情趣|诱惑|性感|妩媚|撩人|魅惑)', caseSensitive: false),
    RegExp(r'(女仆|护士|制服|泳装|比基尼|内衣)', caseSensitive: false),
    RegExp(r'(seductive|seductress|femme\s*fatale|temptress|alluring)', caseSensitive: false),
    RegExp(r'(maid|nurse|bikini|underwear|lingerie|bondage)', caseSensitive: false),
  ];

  /// 检测角色标签是否包含成人向特征
  static bool isAdultCharacter(String? characterTag, String? personality, String? background) {
    final combined = [characterTag ?? '', personality ?? '', background ?? ''].join(' ');
    if (combined.isEmpty) return false;
    for (final pattern in _adultTagPatterns) {
      if (pattern.hasMatch(combined)) return true;
    }
    return false;
  }

  /// 检测 prompt 是否包含高度露骨内容
  static bool containsExplicitContent(String prompt) {
    for (final pattern in _adultPatterns) {
      if (pattern.hasMatch(prompt)) return true;
    }
    return false;
  }

  /// 将成人向场景自动转为合规的日常场景
  ///
  /// 根据角色性别和原场景意图，选择合适的合规替代场景。
  static String toSafeScene({
    required String originalInstruction,
    required String gender,
    String? characterTag,
  }) {
    // 合规场景模板（按情绪氛围分组）
    final safeScenes = <String>[
      // 日常温馨
      'sitting by a window reading a book, soft afternoon sunlight, peaceful atmosphere',
      'walking through a flower garden, gentle breeze, warm smile',
      'cooking in a cozy kitchen, steam rising from a pot, warm lighting',
      'sitting at a cafe table, holding a coffee cup, looking out the window',
      'lying on grass in a park, looking up at clouds, relaxed expression',
      // 室内休闲
      'sitting on a sofa wrapped in a soft blanket, watching TV, cozy room',
      'standing in a room with fairy lights, wearing comfortable home clothes, warm smile',
      'playing a musical instrument in a sunlit room, focused expression',
      'painting on a canvas in an art studio, creative atmosphere, natural lighting',
      // 外景浪漫
      'standing under cherry blossoms, petals falling, dreamy atmosphere',
      'watching a sunset from a hilltop, golden hour lighting, peaceful expression',
      'walking along a beach at sunset, waves gently lapping, serene mood',
      'standing on a balcony overlooking the city at night, city lights bokeh',
      // 动态活力
      'dancing gracefully in a ballroom, elegant movement, dynamic pose',
      'riding a bicycle through a countryside road, joyful expression, sunny day',
      'stretching after yoga in a garden, calm and centered, morning light',
    ];

    // 根据原始指令的关键词选择最匹配的场景
    final lower = originalInstruction.toLowerCase();
    String selected;

    if (lower.contains('室内') || lower.contains('房间') || lower.contains('家')) {
      selected = safeScenes[5 + (originalInstruction.hashCode % 4).abs()];
    } else if (lower.contains('外') || lower.contains('街') || lower.contains('公园')) {
      selected = safeScenes[9 + (originalInstruction.hashCode % 4).abs()];
    } else if (lower.contains('动') || lower.contains('跑') || lower.contains('跳舞')) {
      selected = safeScenes[13 + (originalInstruction.hashCode % 3).abs()];
    } else {
      selected = safeScenes[(originalInstruction.hashCode % 5).abs()];
    }

    return selected;
  }

  /// 获取被过滤的敏感词列表（用于调试）
  static List<String> findSensitiveTerms(String prompt) {
    final found = <String>{};
    for (final regex in _termReplacements.keys) {
      final matches = regex.allMatches(prompt);
      for (final m in matches) {
        found.add(m.group(0)!);
      }
    }
    for (final regex in _patternReplacements.keys) {
      final matches = regex.allMatches(prompt);
      for (final m in matches) {
        found.add(m.group(0)!);
      }
    }
    return found.toList();
  }

  /// 脱敏主入口
  ///
  /// 将最终 prompt 中的敏感表达替换为等效安全表达。
  /// [prompt] 完整的最终 prompt
  /// [level] 安全级别
  ///
  /// 返回替换后的安全 prompt，语义保持完整。
  static String sanitize({
    required String prompt,
    PromptSafetyLevel level = PromptSafetyLevel.standard,
  }) {
    if (!containsSensitiveContent(prompt) && level != PromptSafetyLevel.strict) {
      return prompt;
    }

    String result = prompt;

    // 1. 替换单词语
    for (final entry in _termReplacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 2. 替换复合模式
    for (final entry in _patternReplacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 3. 严格模式：额外替换边缘词
    if (level == PromptSafetyLevel.strict) {
      for (final entry in _strictReplacements.entries) {
        result = result.replaceAll(entry.key, entry.value);
      }
    }

    // 4. 清理残留（多余逗号/空格）
    result = result.replaceAll(RegExp(r',\s*,+'), ',');
    result = result.replaceAll(RegExp(r'^[\s,]+'), '');
    result = result.replaceAll(RegExp(r'[\s,]+$'), '');
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    if (result != prompt) {
      debugPrint('[Sanitizer] 敏感内容已替换');
    }

    return result;
  }
}
