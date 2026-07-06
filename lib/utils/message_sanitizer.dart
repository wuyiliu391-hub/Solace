/// AI 消息清洗器 — 过滤 SSE 流中残留的日志/时间戳元素
class MessageSanitizer {
  MessageSanitizer._();

  // ── 预编译正则（按匹配概率从高到低排列） ──

  /// 带括号时间戳 (M/D HH:MM)  (MM/DD HH:MM)  (YYYY/M/D HH:MM) 全角半角
  /// 尾部可选冒号 如 (6/1 00:28)或尾部冒号 (6/1 00:28):
  static final _timestampInParens = RegExp(
    r'[\(\（]\s*\d{1,4}/\d{1,2}(?:/\d{1,2})?\s+\d{1,2}:\d{2}(?::\d{2})?:?\s*[\)\）]',
  );

  /// 裸时间戳前有行首/逗号/分号/空白/换行，后方也类似，可用于 3/4 或 1:2
  /// 匹配: "6/1 00:28"  "06/01 00:28:30"  "2026/6/1 0:28"
  static final _bareTimestamp = RegExp(
    r'(?<=^|[\s,;，。！？\n\r])(\d{1,4}/\d{1,2}(?:/\d{1,2})?\s+\d{1,2}:\d{2}(?::\d{2})?:?)(?=$|[\s,;，。！？\n\r])',
    multiLine: true,
  );

  /// 连续重复的带括号时间戳刷屏（≥2 个）
  static final _repeatedParensTs = RegExp(
    r'(?:[\(\（]\s*\d{1,4}/\d{1,2}(?:/\d{1,2})?\s+\d{1,2}:\d{2}(?::\d{2})?:?\s*[\)\）]\s*){2,}',
  );

  /// 连续重复的裸时间戳刷屏（≥2 个）
  static final _repeatedBareTs = RegExp(
    r'(?:\d{1,4}/\d{1,2}(?:/\d{1,2})?\s+\d{1,2}:\d{2}(?::\d{2})?:?\s+){2,}',
  );

  /// 日志行：行首或带时间戳的元素
  /// 匹配: [2026-06-01 00:28:15]  2026/06/01 00:28  [00:28] 等
  static final _logLinePattern = RegExp(
    r'(?:^|\n)\s*(?:\[\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?\]'
    r'|\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?'
    r'|\[\d{1,2}:\d{2}(?::\d{2})?\])\s*(?=\n|$)',
    multiLine: true,
  );

  /// 带日志前缀: INFO/DEBUG/WARN/ERROR + 时间
  static final _debugLogLine = RegExp(
    r'(?:^|\n)\s*(?:\[(?:INFO|DEBUG|WARN|ERROR|TRACE)\]'
    r'|(?:INFO|DEBUG|WARN|ERROR|TRACE)[\s:]).*(?=\n|$)',
    multiLine: true,
    caseSensitive: false,
  );

  /// 数字片段/长数字串（8 个字符以上无英文的词）
  static final _numericDebris = RegExp(r'(?:^|\s)[\d\-/:.]{8,}(?:\s|$)');

  /// UTF-8 中文被错误按 GBK/Big5 一类编码解释后，常会变成这些“伪中文”片段。
  /// 例如：用户 -> 鐢ㄦ埛，你 -> 浣犮，回复 -> 鍥炲。
  static final _cjkMojibakeMarker = RegExp(
    r'鐢ㄦ埛|浣犲|浣犮|鍥炲|璇|锛+|銆|涓€|鏄|鏈|冨|勫|熻|€|�'
    r'|锛堝|堝垰|垰鎵|鎵嶈|嶈蛋|蛋绁|绁炰|炰簡|簡锛|鍐堝|鍐鍐|鍐璇|鍐鐢',
  );

  /// 内部状态标签：模型偶尔会把状态块当正文输出，例如 [STATUS]...[/STATUS]
  static final _statusBlock = RegExp(
    r'\[\s*STATUS\s*\][\s\S]*?\[\s*/\s*STATUS\s*\]',
    caseSensitive: false,
    multiLine: true,
  );

  /// 不完整状态标签：只清掉标签本身，避免误删正常正文
  static final _statusTag = RegExp(
    r'\[\s*/?\s*STATUS\s*\]',
    caseSensitive: false,
  );

  /// 内部上下文/系统指令泄漏。命中后按行清理 role 标记与控制块，避免后台
  /// prompt、状态锚点、历史拼接标记进入用户侧气泡。
  static final _internalControlLeakMarker = RegExp(
    r'system\s*:\s*Focus on the latest message from user'
    r'|【\s*当前会话状态锚点[^】]*】'
    r'|【\s*小模型上下文锚点\s*】'
    r'|【\s*最近连续对话\s*】'
    r'|【\s*用户当前消息\s*】'
    r'|【\s*已确认状态\s*】'
    r'|最近连续对话'
    r'|<\s*internal_context\b'
    r'|<\s*/\s*internal_context\s*>'
    r'|\b(?:system|user|assistant)\s*:',
    caseSensitive: false,
    multiLine: true,
  );

  static final _internalControlLine = RegExp(
    r'^\s*(?:'
    r'(?:system|user|assistant)\s*:'
    r'|用户\s*[:：]'
    r'|AI\s*[:：]'
    r'|【\s*(?:当前会话状态锚点[^】]*|小模型上下文锚点|最近连续对话|用户当前消息|已确认状态|禁止|后台控制指令|内部上下文)[^】]*】'
    r'|后台控制指令\s*[:：]'
    r'|下面是刚刚发生的连续对话事实'
    r'|最近连续对话\s*[:：]?'
    r'|[-•]\s*(?:用户/角色|你必须|下面是|回复前|当前亲密等级|用户本轮消息|关键记忆|最近对话|回复要求)'
    r'|<\s*/?\s*internal_context\b[^>]*>'
    r').*$',
    caseSensitive: false,
    multiLine: true,
  );

  /// 推理标签：部分深度模型会把 <think> 内容混进正文，甚至把闭合标签错写成 <think>。
  static final _completeThinkBlock = RegExp(
    r'<\s*(?:think|thinking)\s*>[\s\S]*?<\s*/\s*(?:think|thinking)\s*>',
    caseSensitive: false,
  );

  static final _malformedThinkBlock = RegExp(
    r'<\s*(?:think|thinking)\s*>([\s\S]*?)<\s*(?:think|thinking)\s*>',
    caseSensitive: false,
  );

  static final _thinkTag = RegExp(
    r'<\s*/?\s*(?:think|thinking)\s*>',
    caseSensitive: false,
  );

  /// 推理过程泄漏检测：模型把内部思考当正文输出（无 <think> 标签）。
  /// 匹配常见的中文推理开头模式。
  static final _reasoningLeakPattern = RegExp(
    r'^(?:好的[，,]?\s*)?(?:我(?:需要|要|应该|得)(?:仔细)?(?:分析|考虑|思考|理解|判断|确认|确保|检查|看看|想想|理解一下|分析一下))'
    r'|^(?:让我(?:先)?(?:分析|思考|考虑|想想|看看|理解|仔细看看))'
    r'|^(?:首先[，,]?\s*(?:我(?:需要|要)|让我)(?:分析|考虑|看看))'
    r'|^(?:用户(?:说|发送了?|输入了?|提到了?|想表达|想要|可能是在|的意思是))'
    r'|^(?:根据用户(?:的)?(?:消息|输入|问题|说法|表达))'
    r'|^(?:考虑到(?:当前|用户|对话|之前|整体))'
    r'|^(?:这(?:很可能|应该|可能)(?:是|意味着|说明|表示))'
    r'|^(?:结合(?:之前|当前|用户|对话)(?:的)?(?:对话|历史|情境|上下文|消息))'
    r'|^(?:我需要确保(?:回复|回答|我的回复)(?:符合|满足|遵循))'
    r'|^(?:从(?:对话|整体|当前|用户)(?:的)?(?:角度|情境|上下文|语气)来看)',
    caseSensitive: false,
    multiLine: true,
  );

  /// 推理过程中的分析关键词密度检测
  static final _reasoningKeywordDensity = RegExp(
    r'(?:分析|推理|思考|判断|理解|确保|符合|情境|上下文|用户说|这意味着|很可能|应该是|考虑到|结合之前|需要.*回复|内部|角色设定)',
    caseSensitive: false,
  );

  /// 内心/舞台指令标签：只移除标签本身，保留后面的自然语言内容。
  static final _innerThoughtLabel = RegExp(
    r'(^|[\n\r\s（(\[])(?:ST|内心\s*OS|内心独白|心理活动|旁白|舞台指令)\s*[:：]\s*',
    caseSensitive: false,
    multiLine: true,
  );

  /// 裸露的 ST 标签：常由模型把内部标记当正文输出导致。
  static final _bareStToken = RegExp(
    r'(^|[\s\n\r，。！？、,.!?;；:：\[\]（）()])ST(?=$|[\s\n\r，。！？、,.!?;；:：\[\]（）()])',
    caseSensitive: false,
    multiLine: true,
  );

  /// 断裂片段：清掉类似 "( , ..."、"（，……" 这类只剩半截标点的残片。
  static final _brokenPunctuationFragment = RegExp(
    r'[（(]\s*[,，、.。…\s]+(?:[）)])?',
  );

  static const _traditionalToSimplified = <String, String>{
    '愛': '爱',
    '礙': '碍',
    '罷': '罢',
    '備': '备',
    '筆': '笔',
    '邊': '边',
    '變': '变',
    '別': '别',
    '並': '并',
    '補': '补',
    '才': '才',
    '參': '参',
    '層': '层',
    '產': '产',
    '嘗': '尝',
    '場': '场',
    '長': '长',
    '車': '车',
    '稱': '称',
    '遲': '迟',
    '齒': '齿',
    '衝': '冲',
    '醜': '丑',
    '處': '处',
    '傳': '传',
    '創': '创',
    '從': '从',
    '錯': '错',
    '達': '达',
    '帶': '带',
    '單': '单',
    '當': '当',
    '擔': '担',
    '導': '导',
    '燈': '灯',
    '點': '点',
    '電': '电',
    '動': '动',
    '斷': '断',
    '對': '对',
    '隊': '队',
    '兒': '儿',
    '發': '发',
    '髮': '发',
    '範': '范',
    '飛': '飞',
    '費': '费',
    '風': '风',
    '復': '复',
    '複': '复',
    '該': '该',
    '幹': '干',
    '乾': '干',
    '個': '个',
    '給': '给',
    '夠': '够',
    '關': '关',
    '觀': '观',
    '廣': '广',
    '歸': '归',
    '國': '国',
    '過': '过',
    '還': '还',
    '後': '后',
    '壞': '坏',
    '歡': '欢',
    '會': '会',
    '機': '机',
    '極': '极',
    '幾': '几',
    '記': '记',
    '際': '际',
    '繼': '继',
    '價': '价',
    '見': '见',
    '間': '间',
    '簡': '简',
    '將': '将',
    '講': '讲',
    '較': '较',
    '節': '节',
    '結': '结',
    '緊': '紧',
    '進': '进',
    '經': '经',
    '舊': '旧',
    '覺': '觉',
    '開': '开',
    '課': '课',
    '來': '来',
    '裡': '里',
    '裏': '里',
    '離': '离',
    '歷': '历',
    '聯': '联',
    '練': '练',
    '臉': '脸',
    '戀': '恋',
    '兩': '两',
    '靈': '灵',
    '樓': '楼',
    '錄': '录',
    '亂': '乱',
    '嗎': '吗',
    '買': '买',
    '賣': '卖',
    '滿': '满',
    '們': '们',
    '夢': '梦',
    '麵': '面',
    '難': '难',
    '惱': '恼',
    '腦': '脑',
    '內': '内',
    '妳': '你',
    '寧': '宁',
    '頻': '频',
    '憑': '凭',
    '氣': '气',
    '錢': '钱',
    '淺': '浅',
    '親': '亲',
    '請': '请',
    '輕': '轻',
    '慶': '庆',
    '確': '确',
    '讓': '让',
    '熱': '热',
    '認': '认',
    '軟': '软',
    '灑': '洒',
    '傷': '伤',
    '聲': '声',
    '師': '师',
    '時': '时',
    '實': '实',
    '識': '识',
    '試': '试',
    '適': '适',
    '書': '书',
    '說': '说',
    '歲': '岁',
    '雖': '虽',
    '隨': '随',
    '態': '态',
    '談': '谈',
    '體': '体',
    '條': '条',
    '聽': '听',
    '頭': '头',
    '圖': '图',
    '團': '团',
    '網': '网',
    '為': '为',
    '衛': '卫',
    '溫': '温',
    '問': '问',
    '無': '无',
    '誤': '误',
    '習': '习',
    '戲': '戏',
    '細': '细',
    '係': '系',
    '嚇': '吓',
    '鹹': '咸',
    '顯': '显',
    '現': '现',
    '線': '线',
    '想': '想',
    '項': '项',
    '響': '响',
    '像': '像',
    '寫': '写',
    '謝': '谢',
    '心': '心',
    '興': '兴',
    '虛': '虚',
    '學': '学',
    '壓': '压',
    '亞': '亚',
    '樣': '样',
    '頁': '页',
    '業': '业',
    '醫': '医',
    '陰': '阴',
    '應': '应',
    '擁': '拥',
    '優': '优',
    '於': '于',
    '與': '与',
    '語': '语',
    '遠': '远',
    '願': '愿',
    '雲': '云',
    '運': '运',
    '暫': '暂',
    '臟': '脏',
    '責': '责',
    '這': '这',
    '著': '着',
    '真': '真',
    '隻': '只',
    '種': '种',
    '眾': '众',
    '週': '周',
    '豬': '猪',
    '轉': '转',
    '準': '准',
    '狀': '状',
    '總': '总',
    '組': '组',
    '鑽': '钻',
  };

  // Some models occasionally output a built-in sticker asset id as plain text
  // instead of the required [STICKER:id] tag. Hide that internal id before
  // saving/displaying the message while keeping the natural-language text.
  static final _bareBuiltinStickerId = RegExp(
    r'(^|[\s，。！？、,.!?;；:：])puppy_[a-z0-9_]+(?=$|[\s，。！？、,.!?;；:：])',
    caseSensitive: false,
    multiLine: true,
  );

  /// 用于计算时间戳 token 匹配（括号 + 数字）
  static final _tsTokenCounter = RegExp(
    r'[\(\（]?\s*\d{1,4}/\d{1,2}(?:/\d{1,2})?\s+\d{1,2}:\d{2}(?::\d{2})?:?\s*[\)\）]?',
  );

  // ── 对外 API（流式/非流式均调用） ──

  /// 检测并移除无标签的推理过程泄漏。
  /// 如果文本以推理模式开头且分析关键词密度高，判定为推理泄漏并清空。
  static String stripReasoningLeak(String text) {
    if (text.isEmpty) return text;
    final trimmed = text.trim();

    // 检测开头是否匹配推理模式
    if (_reasoningLeakPattern.hasMatch(trimmed)) {
      // 计算分析关键词密度
      final keywordMatches =
          _reasoningKeywordDensity.allMatches(trimmed).length;
      final textLength = trimmed.length;
      // 关键词密度 > 3% 或前 100 字内有 2+ 个关键词 → 判定为推理泄漏
      if (keywordMatches >= 3 ||
          (textLength > 0 && keywordMatches / (textLength / 10) > 0.03) ||
          (textLength >= 50 &&
              _reasoningKeywordDensity
                      .allMatches(
                          trimmed.substring(0, 100.clamp(0, textLength)))
                      .length >=
                  2)) {
        return '';
      }
    }
    return text;
  }

  /// 流式清洗：高频调用，只去时间戳相关
  /// 保持原结构，仅删减多余的时间戳
  static String sanitizeStream(String text) {
    if (text.isEmpty) return text;
    if (isKnownFailureFallback(text)) return '';
    String result = text;

    // 1. 推理标签
    result = stripReasoningTags(result)[0];

    // 1b. 无标签推理过程泄漏
    result = stripReasoningLeak(result);

    // 2. 内部状态标签
    result = result.replaceAll(_statusBlock, '');
    result = result.replaceAll(_statusTag, '');
    result = result.replaceAll(
        RegExp(r'<BT_ACTION>[\s\S]*?</BT_ACTION>', caseSensitive: false, dotAll: true),
        '');
    result = stripInternalControlLeaks(result);

    // 3. 刷屏级重复时间戳（带括号 + 裸时间戳）
    result = result.replaceAll(_repeatedParensTs, ' ');
    result = result.replaceAll(_repeatedBareTs, ' ');

    // 4. 散落的带括号时间戳
    result = result.replaceAll(_timestampInParens, '');

    // 5. 散落的裸时间戳
    result = result.replaceAll(_bareTimestamp, '');

    // 6. 日志行
    result = result.replaceAll(_logLinePattern, '');
    result = result.replaceAll(_debugLogLine, '');

    // 7. 内心/舞台指令泄漏标签与断裂标点片段
    result = result.replaceAllMapped(
      _innerThoughtLabel,
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      _bareStToken,
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAll(_brokenPunctuationFragment, '');

    // 8. 合并多余空白
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    result = toSimplifiedChinese(result);
    result = result.trim();

    return result;
  }

  /// 去除正文中的推理标签，并把标签里的内容提取出来。
  ///
  /// 返回值：[清理后的正文, 提取出的推理内容]。
  /// 兼容：
  /// - <think>...</think>
  /// - <thinking>...</thinking>
  /// - <think>...<think>（模型把闭合标签错写成开启标签）
  /// - 流式过程中暂时未闭合的开头 <think>
  static List<String> stripReasoningTags(String text) {
    if (text.isEmpty) return [text, ''];

    var result = text;
    final reasoningParts = <String>[];

    void collect(String raw) {
      final cleaned = raw.replaceAll(_thinkTag, '').trim();
      if (cleaned.isNotEmpty) {
        reasoningParts.add(cleaned);
      }
    }

    for (final match in _completeThinkBlock.allMatches(result).toList()) {
      collect(match.group(0) ?? '');
    }
    result = result.replaceAll(_completeThinkBlock, '');

    for (final match in _malformedThinkBlock.allMatches(result).toList()) {
      collect(match.group(1) ?? '');
    }
    result = result.replaceAll(_malformedThinkBlock, '');

    final unclosed = _thinkTag.firstMatch(result);
    if (unclosed != null) {
      final before = result.substring(0, unclosed.start);
      final after = result.substring(unclosed.end);
      collect(after);
      result = before;
    }

    result = result.replaceAll(_thinkTag, '');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return [result, reasoningParts.join('\n').trim()];
  }

  static String _collapseBlankLines(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }

  static String stripInternalControlLeaks(String text) {
    if (text.isEmpty) return text;
    if (!_internalControlLeakMarker.hasMatch(text)) return text;

    var result = text
        .replaceAll(
            RegExp(r'<\s*internal_context\b[^>]*>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<\s*/\s*internal_context\s*>', caseSensitive: false), '');

    final lines = result.split(RegExp(r'\r?\n'));
    final kept = <String>[];
    var skipNextUserPayload = false;
    for (final line in lines) {
      if (skipNextUserPayload) {
        skipNextUserPayload = false;
        if (line.trim().isNotEmpty) continue;
      }
      if (_internalControlLine.hasMatch(line)) {
        if (line.contains('用户当前消息')) {
          skipNextUserPayload = true;
        }
        continue;
      }
      kept.add(line);
    }
    result = kept.join('\n');

    result = result.replaceAll(_internalControlLeakMarker, '');
    return _collapseBlankLines(result);
  }

  /// 最终清洗：在保存前按消息前后执行
  static String sanitizeFinal(String text) {
    if (text.isEmpty) return text;
    String result = text;

    // 1. 全量格式清洗
    result = sanitizeStream(result);

    // 2. 数字碎片
    result = result.replaceAll(_numericDebris, ' ');
    result = stripInternalControlLeaks(result);

    // 3. Remove leaked built-in sticker ids such as "puppy_wait".
    result = result.replaceAllMapped(
      _bareBuiltinStickerId,
      (match) => match.group(1) ?? '',
    );

    // 4. 二次清理内部标签与断裂片段。
    result = result.replaceAllMapped(
      _innerThoughtLabel,
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      _bareStToken,
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAll(_brokenPunctuationFragment, '');

    // 5. 清理孤立的半截标点行
    result = result
        .split('\n')
        .where((line) => !RegExp(r'^\s*[,，、.。…()（）]+\s*$').hasMatch(line))
        .join('\n');

    // 6. 再次合并空白
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
    result = _collapseBlankLines(result);
    result = toSimplifiedChinese(result);
    result = result.trim();

    return result;
  }

  /// 信件/朋友圈等非聊天专用清洗。比 sanitizeFinal 更强力，过滤推理泄漏行和设定重复。
  static String sanitizeForContent(String text) {
    if (text.isEmpty) return text;
    String result = sanitizeFinal(text);

    // 1. 移除推理泄漏行、身份设定重复行
    final leakLines = RegExp(
      r'^(好的[，,]?\s*)?(我(?:需要|要|应该|得)(?:仔细)?(?:分析|考虑|思考|理解|判断|确认|确保|检查|看看|想想|理解一下|分析一下))'
      r'|^(让我(?:先)?(?:分析|思考|考虑|想想|看看|理解|仔细看看))'
      r'|^(首先[，,]?\s*(?:我(?:需要|要)|让我)(?:分析|考虑|看看))'
      r'|^(用户(?:说|发送了?|输入了?|提到了?|想表达|想要|可能是在|的意思是))'
      r'|^(根据用户(?:的)?(?:消息|输入|问题|说法|表达))'
      r'|^(作为AI|作为一个AI|根据要求|根据角色设定|按照设定|基于我的设定|根据我的身份|根据我的角色)'
      r'|^(这(?:封信|是)?(?:可能|应该|需要|符合|根据|按照|基于))'
      r'|^(结合(?:之前|当前|用户|对话)(?:的)?(?:对话|历史|情境|上下文))'
      r'|^(以下|以上|下面|接下来|然后是)',
      caseSensitive: false, multiLine: true,
    );
    result = result.split('\n')
        .where((line) => !leakLines.hasMatch(line.trim()))
        .join('\n');

    // 2. 移除"好的""嗯"等开头残留
    result = result.replaceAllMapped(
      RegExp(r'^(?:好的[，,.]?\s*|嗯[，,.]?\s*|好的嗯[，,.]?\s*)+', multiLine: true),
      (_) => '',
    );

    // 3. 压缩多余空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    result = result.trim();

    return result;
  }

  static bool isLikelyCjkMojibake(String text) {
    if (text.isEmpty) return false;
    if (isKnownFailureFallback(text)) return true;

    final markerCount = _cjkMojibakeMarker.allMatches(text).length;
    if (markerCount >= 2) return true;

    final cjkCount = RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;
    if (cjkCount < 4) return false;

    final suspiciousChars =
        RegExp(r'[鐢浣鍥璇锛銆€鏄鏈冨勫熻堝垰鎵嶈蛋绁炰簡鍐]').allMatches(text).length;
    return suspiciousChars >= 4 && suspiciousChars / cjkCount > 0.35;
  }

  /// 固定失败兜底句的乱码形态。
  /// 这类文本不是模型内容，而是上游/中转/流式异常时的失败哨兵，绝不能进入显示、历史或记忆。
  static bool isKnownFailureFallback(String text) {
    if (text.isEmpty) return false;
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains('刚才走神了') && normalized.contains('再说一遍')) {
      return true;
    }
    return normalized.contains('锛堝垰鎵嶈蛋绁炰簡') ||
        normalized.contains('锛岃兘鍐嶈') ||
        normalized.contains('涓€閬嶅悧') ||
        normalized.contains('燂級');
  }

  /// 检测文本是否是 API 网关/服务商的错误信息
  static bool isGatewayError(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    return lower.contains('an error occurred') ||
        lower.contains('reference:') ||
        lower.contains('error code:') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable') ||
        lower.contains('api error');
  }

  /// 检测多脚本混杂的无意义乱码文本（混合 4+ 书写系统的文本）
  static bool isLikelyUnreadableGibberish(String text) {
    if (text.isEmpty) return false;
    if (isLikelyCjkMojibake(text)) return true;
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 32) return false;
    final cjkCount = RegExp(r'[一-鿿]').allMatches(normalized).length;
    final cyrillicCount = RegExp(r'[Ѐ-ӿ]').allMatches(normalized).length;
    final greekCount = RegExp(r'[Ͱ-Ͽ]').allMatches(normalized).length;
    final kanaCount = RegExp(r'[぀-ヿ]').allMatches(normalized).length;
    final hangulCount = RegExp(r'[가-힯]').allMatches(normalized).length;
    final latinWordCount = RegExp(r'\b[A-Za-z]{3,}\b').allMatches(normalized).length;
    final rareSymbolCount = RegExp(r'[Δ#®@{}\[\]<>$%^&*=|\\]').allMatches(normalized).length;
    final codeKeywordCount = RegExp(
      r'\b(?:Threshold|Trace|Setup|font|extract|dependence|Access|Config|Debug|Error|Token|Delta|Stream|Json|Widget|State|Render|Build|Function|Class|Import|Export)\b',
      caseSensitive: false,
    ).allMatches(normalized).length;
    final knownFragmentHit = RegExp(
      r'опного|сопцен|iiemale|font[—-]extract|吕础|指泰国|利率牵引',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (knownFragmentHit) return true;
    var scriptGroups = 0;
    if (cjkCount >= 2) scriptGroups++;
    if (latinWordCount >= 2) scriptGroups++;
    if (cyrillicCount >= 2) scriptGroups++;
    if (greekCount >= 1) scriptGroups++;
    if (kanaCount >= 2) scriptGroups++;
    if (hangulCount >= 2) scriptGroups++;
    if (cyrillicCount >= 3 && cjkCount >= 2 && latinWordCount >= 2) return true;
    if (cyrillicCount >= 3 && codeKeywordCount >= 2) return true;
    if (codeKeywordCount >= 4 && cjkCount >= 4 && rareSymbolCount >= 2) return true;
    if (scriptGroups >= 4 && rareSymbolCount >= 2 && latinWordCount >= 3) return true;
    return false;
  }

  static String failureFallbackText() => '网络刚才有点不稳，我重新想一下怎么回复你。';

  static String toSimplifiedChinese(String text) {
    if (text.isEmpty) return text;

    var result = text;
    for (final entry in _traditionalToSimplified.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  /// 去除同一条回复内部的重复段落，并剔除对近期 AI 回复的整段复读。
  static String removeRepeatedContent(
    String text, {
    Iterable<String> previousMessages = const [],
    String fallback = '',
  }) {
    if (text.isEmpty) return text;

    final original = sanitizeFinal(text);
    var result = _collapseDuplicateBlocks(original);

    for (final previous in previousMessages) {
      final cleanedPrevious = sanitizeFinal(previous);
      if (cleanedPrevious.length < 24) continue;

      final previousBlocks = _splitBlocks(cleanedPrevious)
          .where((block) => _normalizeForCompare(block).length >= 18)
          .toList();
      for (final block in previousBlocks) {
        if (result.contains(block)) {
          result = result.replaceAll(block, '');
        }
      }

      if (cleanedPrevious.length >= 40 && result.contains(cleanedPrevious)) {
        result = result.replaceAll(cleanedPrevious, '');
      }
    }

    result = _collapseDuplicateBlocks(result);
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
    result = _collapseBlankLines(result);

    if (result.isEmpty && fallback.isNotEmpty) {
      return sanitizeFinal(fallback);
    }
    return result;
  }

  static String _collapseDuplicateBlocks(String text) {
    final blocks = _splitBlocks(text);
    if (blocks.length <= 1) return text.trim();

    final seen = <String>{};
    final kept = <String>[];
    for (final block in blocks) {
      final normalized = _normalizeForCompare(block);
      if (normalized.length >= 18) {
        if (seen.contains(normalized)) continue;
        seen.add(normalized);
      }
      kept.add(block.trim());
    }
    return kept.join('\n\n').trim();
  }

  static List<String> _splitBlocks(String text) {
    return text
        .split(RegExp(r'\n\s*\n|(?<=。)|(?<=！)|(?<=？)|(?<=! )|(?<=\? )'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();
  }

  static String _normalizeForCompare(String text) {
    return sanitizeFinal(text)
        .replaceAll(RegExp(r'[\s\n\r\t，。！？、,.!?;；:："“”‘’\[\]（）()…~～\-—_]'), '')
        .toLowerCase();
  }

  /// 判断文本是否主要是时间戳/日志（用于判断是否为无效消息）
  static bool isMostlyTimestamps(String text) {
    if (text.isEmpty) return false;

    // 方法1：清洗后内容不足原长 30%
    final cleaned = sanitizeStream(text);
    if (cleaned.length < text.length * 0.3) return true;

    // 方法2：时间戳 token 数量超过总非空白 token 的 50%
    final tsMatches = _tsTokenCounter.allMatches(text).length;
    final totalTokens =
        text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).length;
    if (totalTokens > 0 && tsMatches > totalTokens * 0.5) return true;

    return false;
  }
}
