import '../../utils/message_sanitizer.dart';
import '../../models/bt_agent_action.dart';

/// 响应清洗工具 — 纯函数，无副作用，无外部状态依赖
///
/// 职责：
/// 1. 清理 AI 输出中的控制标签（STATUS、BT_ACTION、internal_context）
/// 2. 繁简转换
/// 3. 流式展示专用清洗（cleanForStreamDisplay）
///
/// 从 AIService 提取，保持与原逻辑 100% 一致。
class ResponseCleaner {
  const ResponseCleaner._();

  /// 非流式完整响应清洗（对应原 AIService._cleanResponse）
  ///
  /// [faMode] 为 true 时保留 *动作* 和 [方括号] 格式
  static String cleanFinal(String content, {required bool faMode}) {
    String cleaned = MessageSanitizer.stripReasoningTags(content)[0];
    cleaned = MessageSanitizer.stripInternalControlLeaks(cleaned);
    cleaned = stripBtAgentPayloads(cleaned, preserveVisibleText: true);
    cleaned = MessageSanitizer.stripReasoningLeak(cleaned);

    cleaned = cleaned.replaceAll(
        RegExp(r'\[STATUS\].*?\[/STATUS\]',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[/?\s*STATUS\s*\]', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[STICK\w*[^\]]*\]', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r'<internal_context[\s\S]*?</internal_context>',
            caseSensitive: false,
            dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r'internal_context[\s\S]{0,200}visibility[\s\S]{0,100}private',
            caseSensitive: false,
            dotAll: true),
        '');

    if (!faMode) {
      cleaned = cleaned.replaceAll(RegExp(r'\*[^*]*\*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\([a-zA-Z\s]+\)'), '');
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.trim();
    cleaned = MessageSanitizer.stripInternalControlLeaks(cleaned);
    cleaned = cleaned.replaceAll(RegExp(r'^[，,、；;\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[，,、；;\s]+$'), '');
    cleaned = convertToSimplifiedChinese(cleaned);
    cleaned = cleaned.replaceAll(
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');

    if (MessageSanitizer.isLikelyUnreadableGibberish(cleaned)) {
      cleaned = '';
    }

    if (cleaned.isEmpty) {
      cleaned = '嗯，让我想想该怎么回答你。';
    }

    return cleaned;
  }

  /// 流式展示专用清洗 — 实时处理每个 chunk
  ///
  /// 返回 [cleanedText, extractedReasoning]（与原 AIService.cleanForStreamDisplay 完全一致）
  static List<String> cleanForStreamDisplay(String content) {
    final reasoningParts = MessageSanitizer.stripReasoningTags(content);
    String cleaned =
        MessageSanitizer.stripInternalControlLeaks(reasoningParts[0]);
    final extractedReasoning = reasoningParts[1];

    cleaned = cleaned.replaceAll(
        RegExp(r'\[STATUS\].*?\[/STATUS\]',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[/?\s*STATUS\s*\]', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'<BT_ACTION>.*?</BT_ACTION>',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(
            r'<internal_context[\s\S]*?</internal_context>',
            caseSensitive: false,
            dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');
    cleaned = cleaned.trim();
    cleaned = convertToSimplifiedChinese(cleaned);

    return [cleaned, extractedReasoning];
  }

  /// 繁体→简体字符映射（常见字，修正原版错误映射）
  static String convertToSimplifiedChinese(String text) {
    const map = {
      '愛': '爱', '們': '们', '個': '个', '時': '时', '說': '说',
      '話': '话', '為': '为', '會': '会', '對': '对', '來': '来',
      '國': '国', '過': '过', '後': '后', '開': '开', '見': '见',
      '問': '问', '題': '题', '點': '点', '這': '这', '麼': '么',
      '著': '着', '還': '还', '沒': '没', '聽': '听', '覺': '觉',
      '請': '请', '讓': '让', '給': '给', '與': '与', '嘆': '叹',
      '嘩': '哗', '嘰': '叽', '嘵': '哓', '嘷': '嗥', '嘸': '呒',
      '當': '当', '應': '应', '該': '该', '夠': '够', '須': '须',
      '並': '并', '經': '经', '壞': '坏', '錯': '错', '實': '实',
      '際': '际', '現': '现', '裡': '里', '內': '内', '東': '东',
      '邊': '边', '間': '间', '處': '处', '體': '体', '統': '统',
      '組': '组', '織': '织', '結': '结', '構': '构', '機': '机',
      '設': '设', '計': '计', '劃': '划', '圖': '图', '書': '书',
      '學': '学', '習': '习', '業': '业', '較': '较', '長': '长',
      '舊': '旧', '種': '种', '類': '类', '別': '别', '號': '号',
      '稱': '称', '親': '亲', '鄰': '邻', '師': '师', '級': '级',
      '週': '周', '鐘': '钟', '頭': '头', '腳': '脚', '憶': '忆',
      '識': '识', '訴': '诉', '講': '讲', '談': '谈', '樂': '乐',
      '傷': '伤', '閒': '闲', '滿': '满', '節': '节', '頁': '页',
      '錄': '录', '誰': '谁', '於': '于', '從': '从', '進': '进',
      '歸': '归', '離': '离', '關': '关', '閉': '闭', '買': '买',
      '賣': '卖', '價': '价', '錢': '钱', '費': '费', '報': '报',
      '風': '风', '雲': '云', '霧': '雾', '電': '电', '氣': '气',
      '聲': '声', '畫': '画', '戲': '戏', '劇': '剧', '視': '视',
      '頻': '频', '網': '网', '絡': '络', '線': '线', '車': '车',
      '飛': '飞', '場': '场', '樓': '楼', '門': '门', '牆': '墙',
      '階': '阶', '層': '层', '頂': '顶', '緣': '缘', '圍': '围',
      '圓': '圆', '狀': '状', '態': '态', '況': '况', '虛': '虚',
      '確': '确', '誤': '误', '斷': '断', '釋': '释', '顯': '显',
      '隱': '隐', '觀': '观', '檢': '检', '驗': '验', '測': '测',
      '試': '试', '尋': '寻', '趕': '赶', '達': '达', '極': '极',
      '數': '数', '減': '减', '變': '变', '轉': '转', '換': '换',
      '動': '动', '繼': '继', '續': '续', '連': '连', '補': '补',
      '歲': '岁', '紀': '纪', '廣': '广', '廳': '厅', '廚': '厨',
      '衛': '卫', '臥': '卧', '陽': '阳', '陰': '阴', '麵': '面',
      '裏': '里', '鬆': '松', '膩': '腻', '軟': '软', '緊': '紧',
      '細': '细', '淺': '浅', '寬': '宽', '遠': '远', '醜': '丑',
      '惡': '恶', '鹹': '咸', '豐': '丰', '藏': '藏',
    };

    String result = text;
    for (final entry in map.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
