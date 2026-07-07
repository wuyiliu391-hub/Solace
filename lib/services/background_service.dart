// ignore_for_file: equal_keys_in_map

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/business_rules.dart';
import '../utils/message_sanitizer.dart';
import '../utils/response_decoder.dart';
import 'ai_service.dart';
import 'persona_evolution_service.dart';

const String bgTaskName = 'proactiveChatMessage';
const String bgTaskMomentPost = 'aiMomentPost';
const String bgTaskCommentReply = 'aiCommentReply';
const String bgTaskMomentInteract = 'aiMomentInteract';
const String bgTaskLetter = 'aiLetter';
const String bgTaskUnique = MethodChannels.background;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      switch (taskName) {
        case bgTaskMomentPost:
          return await _handleMomentPost(inputData);
        case bgTaskCommentReply:
          return await _handleCommentReply(inputData);
        case bgTaskMomentInteract:
          return await _handleMomentInteract(inputData);
        case bgTaskLetter:
          return await _handleLetterPost(inputData);
        case bgTaskName:
        default:
          return await _handleProactiveChat(inputData);
      }
    } catch (e) {
      debugPrint('Background task failed ($taskName): $e');
      return false;
    }
  });
}

// ─── Shared helpers ───

Future<Database> _openRawDb() async {
  final dbPath = await getDatabasesPath();
  final path = p.join(dbPath, 'solace.db');
  return openDatabase(path, singleInstance: false);
}

Future<Map<String, dynamic>?> _getActiveConfig(Database db) async {
  final rows = await db.query('ai_configs',
      where: 'isActive = ?', whereArgs: [1], limit: 1);
  return rows.isNotEmpty ? rows.first : null;
}

Future<String> _callAiApi(
  Map<String, dynamic> config,
  String prompt, {
  double temperature = 0.9,
  int maxTokens = 150,
}) async {
  final baseUrl = (config['baseUrl'] as String).endsWith('/')
      ? (config['baseUrl'] as String)
          .substring(0, (config['baseUrl'] as String).length - 1)
      : config['baseUrl'] as String;

  final modePrompt = await _buildBackgroundGlobalModePrompt();
  final novelMode = await _isBackgroundNovelModeEnabled();
  final effectiveMaxTokens =
      novelMode ? (config['maxTokens'] as int? ?? maxTokens) : maxTokens;

  final response = await http
      .post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'Accept-Charset': 'utf-8',
          'Authorization': 'Bearer ${config['apiKey']}',
        },
        body: jsonEncode({
          'model': config['modelName'],
          'messages': [
            {
              'role': 'system',
              'content':
                  '$modePrompt\n\n你必须只使用简体中文回复。不要输出繁体中文、乱码、编码转义、日志、时间戳或解释说明。',
            },
            {'role': 'user', 'content': prompt}
          ],
          'temperature': temperature,
          'max_tokens': effectiveMaxTokens,
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (response.statusCode == 200) {
    final rawBody = await ResponseDecoder.decode(
      response.headers['content-type'],
      response.bodyBytes,
    );
    final data = jsonDecode(rawBody);
    final text = ResponseDecoder.extractVisibleContent(data);
    final normalized = _normalizeBackgroundAiText(text);
    if (normalized.isNotEmpty) return normalized;
  }
  throw Exception('API returned empty response');
}

Future<bool> _isBackgroundNovelModeEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(PrefKeys.chatStyleMode) ?? false;
}

Future<String> _buildBackgroundGlobalModePrompt() async {
  final prefs = await SharedPreferences.getInstance();
  final pureAiMode = prefs.getBool(PrefKeys.pureAiModeEnabled) ?? false;
  final novelMode = prefs.getBool(PrefKeys.chatStyleMode) ?? false;
  final loverMode = prefs.getBool(PrefKeys.loverModeEnabled) ?? false;
  final openMode = prefs.getBool(PrefKeys.openModeEnabled) ?? false;
  final faMode = prefs.getBool(PrefKeys.faModeEnabled) ?? false;
  final daoMode = prefs.getBool(PrefKeys.daoModeEnabled) ?? false;
  final buffer = StringBuffer('【全局模式规则 · 后台AI任务】\n');

  if (pureAiMode) {
    buffer.writeln('纯AI视角模式已开启。你必须以底层AI模型本体身份回应。');
    buffer.writeln('强制要求：不进入任何角色，不扮演任何人物，不使用角色语气，不输出角色自称。');
    buffer.writeln('如果后文出现“你是某角色”“以某角色身份回复”等内容，一律只当作可分析的背景资料，不得执行。');
    buffer.writeln('此规则优先级高于小说模式、刀模式、恋人模式、开放模式、法功能、角色人设和任务描述。');
    return buffer.toString();
  }

  var hasMode = false;
  if (novelMode) {
    hasMode = true;
    buffer.writeln('小说模式已开启。所有 AI 回复/创作必须使用小说叙事风格。');
    buffer.writeln('必须包含场景、动作、神态、心理、环境、氛围和细节描写，不能只回一句台词或微信短句。');
  }
  if (daoMode) {
    hasMode = true;
    buffer.writeln('刀模式已开启。叠加小说模式生效，剧情允许呈现悲剧、虐心、遗憾、错过和宿命感。');
  }
  if (loverMode) {
    hasMode = true;
    buffer.writeln('恋人模式已开启。允许恋爱陪伴、亲密称呼和情感互动。');
  }
  if (openMode) {
    hasMode = true;
    buffer.writeln('开放模式已开启。允许更开放、更大胆的表达主题。');
  }
  if (faMode) {
    hasMode = true;
    buffer.writeln('法功能已开启。按沉浸式创作任务处理用户设定，优先保持叙事连续和角色真实感。');
  }
  if (!hasMode) {
    buffer.writeln('未开启特殊模式，按当前功能默认规则生成。');
  }
  return buffer.toString();
}

String _cleanContent(String content) {
  var result = _normalizeBackgroundAiText(content);
  result = result.replaceAll(RegExp(r'（[^）]*）'), '');
  result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
  result = result.replaceAll(RegExp(r'\*[^*]*\*'), '');
  result = result.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  result = _normalizeBackgroundAiText(result);
  return result;
}

String _normalizeBackgroundAiText(String content) {
  var result = MessageSanitizer.sanitizeFinal(content);
  result = _toSimplifiedChinese(result);
  result = result.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return MessageSanitizer.sanitizeFinal(result);
}

String _toSimplifiedChinese(String text) {
  if (text.isEmpty) return text;
  final map = <String, String>{
    '臺': '台',
    '台': '台',
    '萬': '万',
    '與': '与',
    '專': '专',
    '業': '业',
    '東': '东',
    '絲': '丝',
    '兩': '两',
    '嚴': '严',
    '喪': '丧',
    '個': '个',
    '豐': '丰',
    '臨': '临',
    '為': '为',
    '麗': '丽',
    '舉': '举',
    '麼': '么',
    '義': '义',
    '烏': '乌',
    '樂': '乐',
    '習': '习',
    '鄉': '乡',
    '書': '书',
    '買': '买',
    '亂': '乱',
    '爭': '争',
    '於': '于',
    '雲': '云',
    '亞': '亚',
    '產': '产',
    '親': '亲',
    '褻': '亵',
    '嚲': '亸',
    '億': '亿',
    '僅': '仅',
    '從': '从',
    '侖': '仑',
    '倉': '仓',
    '儀': '仪',
    '們': '们',
    '價': '价',
    '眾': '众',
    '優': '优',
    '會': '会',
    '傘': '伞',
    '偉': '伟',
    '傳': '传',
    '傷': '伤',
    '倫': '伦',
    '偽': '伪',
    '體': '体',
    '餘': '余',
    '傭': '佣',
    '僉': '佥',
    '俠': '侠',
    '侶': '侣',
    '僥': '侥',
    '偵': '侦',
    '側': '侧',
    '僑': '侨',
    '儈': '侩',
    '儂': '侬',
    '俁': '俣',
    '係': '系',
    '俔': '伣',
    '儉': '俭',
    '債': '债',
    '傾': '倾',
    '僂': '偻',
    '僨': '偾',
    '償': '偿',
    '儻': '傥',
    '儐': '傧',
    '儲': '储',
    '儷': '俪',
    '兒': '儿',
    '兌': '兑',
    '黨': '党',
    '蘭': '兰',
    '關': '关',
    '興': '兴',
    '養': '养',
    '獸': '兽',
    '內': '内',
    '岡': '冈',
    '冊': '册',
    '寫': '写',
    '軍': '军',
    '農': '农',
    '馮': '冯',
    '凍': '冻',
    '淨': '净',
    '準': '准',
    '涼': '凉',
    '減': '减',
    '湊': '凑',
    '凜': '凛',
    '幾': '几',
    '鳳': '凤',
    '憑': '凭',
    '凱': '凯',
    '擊': '击',
    '鑿': '凿',
    '芻': '刍',
    '劃': '划',
    '劉': '刘',
    '則': '则',
    '剛': '刚',
    '創': '创',
    '刪': '删',
    '別': '别',
    '剎': '刹',
    '劑': '剂',
    '剮': '剐',
    '劍': '剑',
    '剝': '剥',
    '劇': '剧',
    '勸': '劝',
    '辦': '办',
    '務': '务',
    '動': '动',
    '勵': '励',
    '勁': '劲',
    '勞': '劳',
    '勢': '势',
    '勳': '勋',
    '勝': '胜',
    '區': '区',
    '醫': '医',
    '華': '华',
    '協': '协',
    '單': '单',
    '賣': '卖',
    '盧': '卢',
    '衛': '卫',
    '卻': '却',
    '廠': '厂',
    '廳': '厅',
    '歷': '历',
    '厲': '厉',
    '壓': '压',
    '厭': '厌',
    '厙': '厍',
    '廁': '厕',
    '廂': '厢',
    '廈': '厦',
    '縣': '县',
    '參': '参',
    '雙': '双',
    '發': '发',
    '變': '变',
    '敘': '叙',
    '疊': '叠',
    '葉': '叶',
    '號': '号',
    '嘆': '叹',
    '嘰': '叽',
    '嚇': '吓',
    '嗎': '吗',
    '啟': '启',
    '吳': '吴',
    '吶': '呐',
    '呂': '吕',
    '嚨': '咙',
    '員': '员',
    '聽': '听',
    '嗚': '呜',
    '詠': '咏',
    '嚀': '咛',
    '嚐': '尝',
    '嘔': '呕',
    '嘍': '喽',
    '唄': '呗',
    '員': '员',
    '問': '问',
    '啞': '哑',
    '嘩': '哗',
    '喚': '唤',
    '喪': '丧',
    '喬': '乔',
    '單': '单',
    '喲': '哟',
    '噴': '喷',
    '嘖': '啧',
    '嗇': '啬',
    '嗆': '呛',
    '嗶': '哔',
    '嘮': '唠',
    '嘗': '尝',
    '嘜': '唛',
    '嘯': '啸',
    '嘰': '叽',
    '噓': '嘘',
    '噠': '哒',
    '噥': '哝',
    '噯': '嗳',
    '噦': '哕',
    '噸': '吨',
    '噹': '当',
    '嚀': '咛',
    '嚕': '噜',
    '嚮': '向',
    '嚳': '喾',
    '囂': '嚣',
    '囈': '呓',
    '囌': '苏',
    '囑': '嘱',
    '囪': '囱',
    '圍': '围',
    '園': '园',
    '圓': '圆',
    '圖': '图',
    '團': '团',
    '國': '国',
    '聖': '圣',
    '場': '场',
    '壞': '坏',
    '塊': '块',
    '堅': '坚',
    '壇': '坛',
    '壩': '坝',
    '墜': '坠',
    '壘': '垒',
    '壟': '垄',
    '壢': '坜',
    '壓': '压',
    '壙': '圹',
    '壯': '壮',
    '聲': '声',
    '殼': '壳',
    '壺': '壶',
    '壽': '寿',
    '夠': '够',
    '夢': '梦',
    '夥': '伙',
    '夾': '夹',
    '奪': '夺',
    '奮': '奋',
    '奧': '奥',
    '妝': '妆',
    '婦': '妇',
    '媽': '妈',
    '嫵': '妩',
    '嫗': '妪',
    '姍': '姗',
    '娛': '娱',
    '婁': '娄',
    '婭': '娅',
    '嬈': '娆',
    '嬌': '娇',
    '孌': '娈',
    '孫': '孙',
    '學': '学',
    '孿': '孪',
    '宮': '宫',
    '寢': '寝',
    '實': '实',
    '寧': '宁',
    '審': '审',
    '寫': '写',
    '寬': '宽',
    '寵': '宠',
    '寶': '宝',
    '將': '将',
    '專': '专',
    '尋': '寻',
    '對': '对',
    '導': '导',
    '尷': '尴',
    '屆': '届',
    '屍': '尸',
    '層': '层',
    '屜': '屉',
    '屬': '属',
    '岡': '冈',
    '島': '岛',
    '峽': '峡',
    '崍': '崃',
    '崗': '岗',
    '嶇': '岖',
    '嶄': '崭',
    '嶗': '崂',
    '嶠': '峤',
    '嶢': '峣',
    '嶺': '岭',
    '嶼': '屿',
    '巋': '岿',
    '巒': '峦',
    '巔': '巅',
    '鞏': '巩',
    '幣': '币',
    '帥': '帅',
    '師': '师',
    '帳': '帐',
    '帶': '带',
    '幀': '帧',
    '幫': '帮',
    '幹': '干',
    '庫': '库',
    '廁': '厕',
    '廂': '厢',
    '廄': '厩',
    '廈': '厦',
    '廚': '厨',
    '廝': '厮',
    '廟': '庙',
    '廠': '厂',
    '廢': '废',
    '廣': '广',
    '廩': '廪',
    '廬': '庐',
    '廳': '厅',
    '弒': '弑',
    '張': '张',
    '彌': '弥',
    '彎': '弯',
    '彈': '弹',
    '強': '强',
    '彆': '别',
    '彙': '汇',
    '彥': '彦',
    '後': '后',
    '徑': '径',
    '從': '从',
    '復': '复',
    '徵': '征',
    '徹': '彻',
    '恆': '恒',
    '恥': '耻',
    '悅': '悦',
    '悶': '闷',
    '惡': '恶',
    '惱': '恼',
    '惲': '恽',
    '愛': '爱',
    '愜': '惬',
    '愴': '怆',
    '愷': '恺',
    '愾': '忾',
    '願': '愿',
    '慄': '栗',
    '態': '态',
    '慘': '惨',
    '慚': '惭',
    '慟': '恸',
    '慣': '惯',
    '慤': '悫',
    '慪': '怄',
    '慫': '怂',
    '慮': '虑',
    '慳': '悭',
    '慶': '庆',
    '憂': '忧',
    '憊': '惫',
    '憐': '怜',
    '憑': '凭',
    '憒': '愦',
    '憚': '惮',
    '憤': '愤',
    '憫': '悯',
    '憮': '怃',
    '憲': '宪',
    '憶': '忆',
    '懇': '恳',
    '應': '应',
    '懌': '怿',
    '懍': '懔',
    '懣': '懑',
    '懨': '恹',
    '懲': '惩',
    '懶': '懒',
    '懷': '怀',
    '懸': '悬',
    '懺': '忏',
    '懼': '惧',
    '懾': '慑',
    '戀': '恋',
    '戇': '戆',
    '戰': '战',
    '戲': '戏',
    '戶': '户',
    '拋': '抛',
    '挾': '挟',
    '捨': '舍',
    '掃': '扫',
    '掄': '抡',
    '掗': '挜',
    '掙': '挣',
    '掛': '挂',
    '採': '采',
    '揀': '拣',
    '揚': '扬',
    '換': '换',
    '揮': '挥',
    '損': '损',
    '搖': '摇',
    '搗': '捣',
    '搶': '抢',
    '摑': '掴',
    '摜': '掼',
    '摟': '搂',
    '摯': '挚',
    '摳': '抠',
    '摶': '抟',
    '摺': '折',
    '撈': '捞',
    '撐': '撑',
    '撓': '挠',
    '撥': '拨',
    '撫': '抚',
    '撲': '扑',
    '撳': '揿',
    '撻': '挞',
    '撾': '挝',
    '撿': '捡',
    '擁': '拥',
    '擄': '掳',
    '擇': '择',
    '擊': '击',
    '擋': '挡',
    '擔': '担',
    '據': '据',
    '擠': '挤',
    '擬': '拟',
    '擯': '摈',
    '擰': '拧',
    '擱': '搁',
    '擲': '掷',
    '擴': '扩',
    '擷': '撷',
    '擺': '摆',
    '擻': '擞',
    '擼': '撸',
    '擾': '扰',
    '攆': '撵',
    '攏': '拢',
    '攔': '拦',
    '攖': '撄',
    '攙': '搀',
    '攜': '携',
    '攝': '摄',
    '攢': '攒',
    '攣': '挛',
    '攤': '摊',
    '攪': '搅',
    '攬': '揽',
    '敗': '败',
    '敘': '叙',
    '敵': '敌',
    '數': '数',
    '齋': '斋',
    '斂': '敛',
    '斃': '毙',
    '斕': '斓',
    '斬': '斩',
    '斷': '断',
    '於': '于',
    '時': '时',
    '曠': '旷',
    '暢': '畅',
    '暫': '暂',
    '曄': '晔',
    '曆': '历',
    '曇': '昙',
    '曉': '晓',
    '曖': '暧',
    '曠': '旷',
    '曬': '晒',
    '書': '书',
    '會': '会',
    '朧': '胧',
    '東': '东',
    '極': '极',
    '構': '构',
    '槍': '枪',
    '楊': '杨',
    '樣': '样',
    '樁': '桩',
    '樂': '乐',
    '樓': '楼',
    '標': '标',
    '樞': '枢',
    '樹': '树',
    '橋': '桥',
    '機': '机',
    '橫': '横',
    '檔': '档',
    '檢': '检',
    '櫃': '柜',
    '權': '权',
    '欄': '栏',
    '歡': '欢',
    '歐': '欧',
    '歲': '岁',
    '歷': '历',
    '歸': '归',
    '殘': '残',
    '殼': '壳',
    '毀': '毁',
    '氣': '气',
    '氫': '氢',
    '氬': '氩',
    '漢': '汉',
    '湯': '汤',
    '溝': '沟',
    '沒': '没',
    '淚': '泪',
    '潔': '洁',
    '潛': '潜',
    '潤': '润',
    '濃': '浓',
    '濕': '湿',
    '濟': '济',
    '濤': '涛',
    '瀏': '浏',
    '瀘': '泸',
    '瀝': '沥',
    '灣': '湾',
    '灑': '洒',
    '灘': '滩',
    '災': '灾',
    '為': '为',
    '烏': '乌',
    '無': '无',
    '煩': '烦',
    '熱': '热',
    '愛': '爱',
    '爺': '爷',
    '牆': '墙',
    '犧': '牺',
    '狀': '状',
    '獨': '独',
    '獲': '获',
    '獵': '猎',
    '獸': '兽',
    '現': '现',
    '琺': '珐',
    '瑪': '玛',
    '環': '环',
    '璽': '玺',
    '瓊': '琼',
    '畫': '画',
    '異': '异',
    '當': '当',
    '疇': '畴',
    '療': '疗',
    '癢': '痒',
    '瘋': '疯',
    '癡': '痴',
    '發': '发',
    '盜': '盗',
    '盞': '盏',
    '盡': '尽',
    '監': '监',
    '盤': '盘',
    '盧': '卢',
    '眾': '众',
    '著': '着',
    '睏': '困',
    '矚': '瞩',
    '矯': '矫',
    '礦': '矿',
    '碼': '码',
    '磚': '砖',
    '確': '确',
    '禮': '礼',
    '禍': '祸',
    '禪': '禅',
    '離': '离',
    '種': '种',
    '稱': '称',
    '穩': '稳',
    '窩': '窝',
    '竄': '窜',
    '竅': '窍',
    '競': '竞',
    '筆': '笔',
    '筍': '笋',
    '築': '筑',
    '簡': '简',
    '籃': '篮',
    '籌': '筹',
    '籤': '签',
    '類': '类',
    '粵': '粤',
    '糧': '粮',
    '糾': '纠',
    '紀': '纪',
    '約': '约',
    '紅': '红',
    '紋': '纹',
    '納': '纳',
    '紐': '纽',
    '純': '纯',
    '紗': '纱',
    '紙': '纸',
    '級': '级',
    '紛': '纷',
    '素': '素',
    '紡': '纺',
    '索': '索',
    '緊': '紧',
    '細': '细',
    '終': '终',
    '組': '组',
    '絆': '绊',
    '結': '结',
    '絕': '绝',
    '給': '给',
    '絡': '络',
    '絢': '绚',
    '統': '统',
    '絲': '丝',
    '綁': '绑',
    '經': '经',
    '綠': '绿',
    '維': '维',
    '綱': '纲',
    '網': '网',
    '綴': '缀',
    '綵': '彩',
    '綸': '纶',
    '綺': '绮',
    '綻': '绽',
    '綽': '绰',
    '綾': '绫',
    '綿': '绵',
    '緄': '绲',
    '緇': '缁',
    '緋': '绯',
    '緒': '绪',
    '緓': '绬',
    '緔': '绱',
    '緗': '缃',
    '緘': '缄',
    '緙': '缂',
    '線': '线',
    '緝': '缉',
    '緞': '缎',
    '締': '缔',
    '緡': '缗',
    '緣': '缘',
    '編': '编',
    '緩': '缓',
    '緬': '缅',
    '緯': '纬',
    '緱': '缑',
    '緲': '缈',
    '練': '练',
    '緶': '缏',
    '缇': '缇',
    '緻': '致',
    '縈': '萦',
    '縉': '缙',
    '縊': '缢',
    '縋': '缒',
    '縐': '绉',
    '縑': '缣',
    '縛': '缚',
    '縝': '缜',
    '縞': '缟',
    '縟': '缛',
    '縣': '县',
    '縫': '缝',
    '縭': '缡',
    '縮': '缩',
    '縱': '纵',
    '縲': '缧',
    '縴': '纤',
    '縵': '缦',
    '縶': '絷',
    '縷': '缕',
    '總': '总',
    '績': '绩',
    '繃': '绷',
    '繅': '缫',
    '繆': '缪',
    '繒': '缯',
    '織': '织',
    '繕': '缮',
    '繚': '缭',
    '繞': '绕',
    '繡': '绣',
    '繢': '缋',
    '繩': '绳',
    '繪': '绘',
    '繫': '系',
    '繭': '茧',
    '繮': '缰',
    '繯': '缳',
    '繳': '缴',
    '繹': '绎',
    '繼': '继',
    '纈': '缬',
    '纏': '缠',
    '纓': '缨',
    '纖': '纤',
    '纜': '缆',
    '缽': '钵',
    '罰': '罚',
    '罵': '骂',
    '羅': '罗',
    '羆': '罴',
    '羈': '羁',
    '羋': '芈',
    '義': '义',
    '習': '习',
    '翹': '翘',
    '聖': '圣',
    '聞': '闻',
    '聯': '联',
    '聰': '聪',
    '聲': '声',
    '聳': '耸',
    '職': '职',
    '聽': '听',
    '肅': '肃',
    '腸': '肠',
    '膚': '肤',
    '膠': '胶',
    '膽': '胆',
    '膩': '腻',
    '臉': '脸',
    '臟': '脏',
    '臨': '临',
    '舉': '举',
    '舊': '旧',
    '艦': '舰',
    '艙': '舱',
    '藝': '艺',
    '節': '节',
    '芻': '刍',
    '蘇': '苏',
    '藍': '蓝',
    '薩': '萨',
    '薦': '荐',
    '藥': '药',
    '藪': '薮',
    '蘊': '蕴',
    '蘋': '苹',
    '虛': '虚',
    '蟲': '虫',
    '蠟': '蜡',
    '蠅': '蝇',
    '蠍': '蝎',
    '蠶': '蚕',
    '蠻': '蛮',
    '衆': '众',
    '術': '术',
    '衛': '卫',
    '衝': '冲',
    '裝': '装',
    '裏': '里',
    '複': '复',
    '褲': '裤',
    '襯': '衬',
    '覺': '觉',
    '覽': '览',
    '觀': '观',
    '觸': '触',
    '訂': '订',
    '計': '计',
    '訊': '讯',
    '討': '讨',
    '訓': '训',
    '託': '托',
    '記': '记',
    '訟': '讼',
    '訪': '访',
    '設': '设',
    '許': '许',
    '訴': '诉',
    '診': '诊',
    '詆': '诋',
    '詐': '诈',
    '詔': '诏',
    '評': '评',
    '詛': '诅',
    '詞': '词',
    '試': '试',
    '詩': '诗',
    '詫': '诧',
    '該': '该',
    '詳': '详',
    '誇': '夸',
    '誌': '志',
    '認': '认',
    '誑': '诳',
    '誒': '诶',
    '誕': '诞',
    '誘': '诱',
    '語': '语',
    '誠': '诚',
    '誡': '诫',
    '誣': '诬',
    '誤': '误',
    '說': '说',
    '誰': '谁',
    '課': '课',
    '誼': '谊',
    '調': '调',
    '諂': '谄',
    '談': '谈',
    '請': '请',
    '諍': '诤',
    '諒': '谅',
    '論': '论',
    '諗': '谂',
    '諛': '谀',
    '諜': '谍',
    '諞': '谝',
    '諢': '诨',
    '諤': '谔',
    '諦': '谛',
    '諧': '谐',
    '諫': '谏',
    '諭': '谕',
    '諮': '咨',
    '諱': '讳',
    '諳': '谙',
    '諶': '谌',
    '諷': '讽',
    '諸': '诸',
    '諺': '谚',
    '諾': '诺',
    '謀': '谋',
    '謁': '谒',
    '謂': '谓',
    '謄': '誊',
    '謊': '谎',
    '謎': '谜',
    '謐': '谧',
    '謔': '谑',
    '謖': '谡',
    '謗': '谤',
    '謙': '谦',
    '謚': '谥',
    '講': '讲',
    '謝': '谢',
    '謠': '谣',
    '謨': '谟',
    '謫': '谪',
    '謬': '谬',
    '謳': '讴',
    '謹': '谨',
    '謾': '谩',
    '證': '证',
    '譎': '谲',
    '譏': '讥',
    '譚': '谭',
    '譜': '谱',
    '識': '识',
    '譙': '谯',
    '譯': '译',
    '議': '议',
    '譴': '谴',
    '護': '护',
    '譽': '誉',
    '讀': '读',
    '變': '变',
    '讎': '仇',
    '讒': '谗',
    '讓': '让',
    '讕': '谰',
    '讖': '谶',
    '讚': '赞',
    '貝': '贝',
    '貞': '贞',
    '負': '负',
    '財': '财',
    '貢': '贡',
    '貧': '贫',
    '貨': '货',
    '販': '贩',
    '貪': '贪',
    '貫': '贯',
    '責': '责',
    '貯': '贮',
    '貴': '贵',
    '貸': '贷',
    '費': '费',
    '貼': '贴',
    '貽': '贻',
    '貿': '贸',
    '賀': '贺',
    '賁': '贲',
    '賂': '赂',
    '賃': '赁',
    '賄': '贿',
    '資': '资',
    '賈': '贾',
    '賊': '贼',
    '賓': '宾',
    '賜': '赐',
    '賞': '赏',
    '賠': '赔',
    '賢': '贤',
    '賣': '卖',
    '賤': '贱',
    '賦': '赋',
    '質': '质',
    '賬': '账',
    '賭': '赌',
    '賴': '赖',
    '賺': '赚',
    '購': '购',
    '賽': '赛',
    '贅': '赘',
    '贈': '赠',
    '贊': '赞',
    '贍': '赡',
    '贏': '赢',
    '贓': '赃',
    '贖': '赎',
    '贗': '赝',
    '贛': '赣',
    '趙': '赵',
    '趕': '赶',
    '趨': '趋',
    '跡': '迹',
    '踐': '践',
    '踴': '踊',
    '蹤': '踪',
    '車': '车',
    '軋': '轧',
    '軌': '轨',
    '軍': '军',
    '軒': '轩',
    '軟': '软',
    '軸': '轴',
    '輕': '轻',
    '載': '载',
    '較': '较',
    '輔': '辅',
    '輛': '辆',
    '輝': '辉',
    '輩': '辈',
    '輪': '轮',
    '輯': '辑',
    '輸': '输',
    '轄': '辖',
    '轉': '转',
    '轍': '辙',
    '轎': '轿',
    '轟': '轰',
    '辦': '办',
    '辭': '辞',
    '邊': '边',
    '遼': '辽',
    '達': '达',
    '遷': '迁',
    '過': '过',
    '還': '还',
    '這': '这',
    '進': '进',
    '遠': '远',
    '違': '违',
    '連': '连',
    '遲': '迟',
    '適': '适',
    '選': '选',
    '遺': '遗',
    '遙': '遥',
    '鄧': '邓',
    '鄭': '郑',
    '鄰': '邻',
    '醜': '丑',
    '醫': '医',
    '醬': '酱',
    '釀': '酿',
    '釋': '释',
    '釘': '钉',
    '針': '针',
    '釣': '钓',
    '鈉': '钠',
    '鈔': '钞',
    '鈕': '钮',
    '鈞': '钧',
    '鈣': '钙',
    '鈴': '铃',
    '鉀': '钾',
    '鉅': '钜',
    '鉋': '刨',
    '鉑': '铂',
    '鉛': '铅',
    '鉤': '钩',
    '銀': '银',
    '銅': '铜',
    '銘': '铭',
    '銜': '衔',
    '銳': '锐',
    '銷': '销',
    '鋁': '铝',
    '鋒': '锋',
    '鋤': '锄',
    '鋪': '铺',
    '鋼': '钢',
    '錄': '录',
    '錢': '钱',
    '錦': '锦',
    '錨': '锚',
    '錯': '错',
    '鍋': '锅',
    '鍵': '键',
    '鍾': '钟',
    '鎖': '锁',
    '鎮': '镇',
    '鏡': '镜',
    '鐘': '钟',
    '鐵': '铁',
    '鑑': '鉴',
    '長': '长',
    '門': '门',
    '閃': '闪',
    '閉': '闭',
    '開': '开',
    '閒': '闲',
    '間': '间',
    '閔': '闵',
    '閘': '闸',
    '閣': '阁',
    '閥': '阀',
    '閨': '闺',
    '閩': '闽',
    '閱': '阅',
    '閻': '阎',
    '闆': '板',
    '闈': '闱',
    '闊': '阔',
    '闌': '阑',
    '闔': '阖',
    '闡': '阐',
    '隊': '队',
    '陽': '阳',
    '陰': '阴',
    '陣': '阵',
    '階': '阶',
    '際': '际',
    '陸': '陆',
    '隴': '陇',
    '隨': '随',
    '險': '险',
    '隱': '隐',
    '隸': '隶',
    '雜': '杂',
    '雞': '鸡',
    '離': '离',
    '難': '难',
    '雲': '云',
    '電': '电',
    '霧': '雾',
    '靈': '灵',
    '靜': '静',
    '頂': '顶',
    '項': '项',
    '順': '顺',
    '須': '须',
    '頑': '顽',
    '顧': '顾',
    '頓': '顿',
    '頗': '颇',
    '領': '领',
    '頰': '颊',
    '頻': '频',
    '題': '题',
    '額': '额',
    '顏': '颜',
    '願': '愿',
    '類': '类',
    '風': '风',
    '飛': '飞',
    '飢': '饥',
    '飯': '饭',
    '飲': '饮',
    '餓': '饿',
    '館': '馆',
    '餘': '余',
    '馬': '马',
    '駁': '驳',
    '駐': '驻',
    '駛': '驶',
    '駝': '驼',
    '駡': '骂',
    '駭': '骇',
    '騎': '骑',
    '騙': '骗',
    '騷': '骚',
    '驅': '驱',
    '驚': '惊',
    '驗': '验',
    '體': '体',
    '鬆': '松',
    '鬥': '斗',
    '鬧': '闹',
    '魯': '鲁',
    '鮮': '鲜',
    '鯉': '鲤',
    '鯨': '鲸',
    '鳥': '鸟',
    '鳴': '鸣',
    '鴨': '鸭',
    '鴻': '鸿',
    '鵝': '鹅',
    '鷹': '鹰',
    '鹽': '盐',
    '麥': '麦',
    '黃': '黄',
    '點': '点',
    '齊': '齐',
    '齒': '齿',
    '龍': '龙',
    '龜': '龟',
  };

  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}

Future<void> _showMomentNotification({
  required String characterName,
  required String content,
  required String momentId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  final body = content.length > 50 ? '${content.substring(0, 50)}...' : content;
  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 发了新动态',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.moments,
        '朋友圈动态',
        channelDescription: 'AI 角色的朋友圈动态',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'moment_$momentId',
  );
}

Future<void> _showCommentNotification({
  required String characterName,
  required String content,
  required String momentId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  final body = content.length > 50 ? '${content.substring(0, 50)}...' : content;
  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 回复了你的评论',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.moments,
        '朋友圈动态',
        channelDescription: 'AI 角色的朋友圈动态',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'moment_$momentId',
  );
}

// ─── Handler: 普通聊天消息（原有逻辑）───

Future<bool> _handleProactiveChat(Map<String, dynamic>? inputData) async {
  final characterId = inputData?['characterId'] as String?;
  final sessionId = inputData?['sessionId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 0;

  if (characterId == null || sessionId == null) return false;

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);

    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    // 检查用户是否关闭了主动消息
    final interactionConfigRaw = character['interactionConfig'] as String?;
    if (interactionConfigRaw != null && interactionConfigRaw.isNotEmpty) {
      try {
        final configMap =
            Map<String, dynamic>.from(jsonDecode(interactionConfigRaw));
        if (configMap['enableMomentInteraction'] == false ||
            configMap['enableMomentInteraction'] == 0) {
          debugPrint('Background: 主动消息已关闭，跳过 $characterId');
          return true;
        }
      } catch (e) {
        debugPrint('Error: $e');
      }
    }

    String content;
    try {
      content = await _generateBgContent(db, config, character, intimacyLevel);
    } catch (e) {
      debugPrint('Background generate failed: $e');
      return true;
    }

    if (content.trim().isEmpty || content.trim() == '[SILENT]') {
      debugPrint('Background: AI决定静默，不发送消息');
      return true;
    }

    final now = DateTime.now();
    final msgId = 'bg_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    await db.insert('chat_messages', {
      'id': msgId,
      'chatId': sessionId,
      'senderId': 'ai_$characterId',
      'senderName': character['name'] as String? ?? 'AI',
      'content': content,
      'type': 0,
      'status': 1,
      'createdAt': now.toIso8601String(),
    });

    await db.update(
        'chat_sessions',
        {
          'lastMessage': content,
          'lastMessageTime': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId]);

    final flp = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flp.initialize(const InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    ));

    await flp.show(
      now.millisecondsSinceEpoch % 100000,
      character['name'] as String? ?? 'AI',
      content,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.backgroundChat,
          '聊天消息',
          channelDescription: 'AI 角色的聊天消息',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: 'chat_$sessionId',
    );

    return true;
  } finally {
    await db.close();
  }
}

// ─── Handler: AI 发动态 ───

Future<bool> _handleMomentPost(Map<String, dynamic>? inputData) async {
  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    final characters =
        await db.query('ai_characters', where: 'isOnline = ?', whereArgs: [1]);

    final random = Random();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    for (final character in characters) {
      final characterId = character['id'] as String;

      // 检查 enableUserMomentInteraction 配置
      final interactionConfigStr =
          character['interactionConfig'] as String? ?? '{}';
      Map<String, dynamic> interactionConfig;
      try {
        interactionConfig =
            jsonDecode(interactionConfigStr) as Map<String, dynamic>;
      } catch (_) {
        interactionConfig = {};
      }
      if (interactionConfig.containsKey('enableUserMomentInteraction') &&
          interactionConfig['enableUserMomentInteraction'] == false) continue;

      // 查询最近一条 AI 动态
      final lastMoments = await db.query('moments',
          where: 'userId = ? AND isFromAI = ?',
          whereArgs: [characterId, 1],
          orderBy: 'createdAt DESC',
          limit: 1);

      double hoursSinceLastPost = 999.0;
      if (lastMoments.isNotEmpty) {
        final lastCreatedAt =
            DateTime.tryParse(lastMoments.first['createdAt'] as String? ?? '');
        if (lastCreatedAt != null) {
          hoursSinceLastPost = now.difference(lastCreatedAt).inHours.toDouble();
        }
      }

      // 最小间隔检查
      if (hoursSinceLastPost < MomentSchedulerRules.minHoursBetweenPosts)
        continue;

      // 今日上限检查
      final todayCount = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM moments WHERE userId = ? AND isFromAI = 1 AND createdAt >= ?',
          [characterId, todayStart]);
      final count = todayCount.first['cnt'] as int? ?? 0;
      if (count >= MomentSchedulerRules.maxDailyPostsPerCharacter) continue;

      // 概率判断：随时间递增
      final probability =
          (hoursSinceLastPost / MomentSchedulerRules.maxHoursBetweenPosts)
              .clamp(0.0, 1.0);
      if (random.nextDouble() > probability) continue;

      // 获取最近聊天记录用于 prompt
      String recentContext = '';
      final sessions = await db.query('chat_sessions',
          where: 'aiCharacterId = ?', whereArgs: [characterId], limit: 1);
      if (sessions.isNotEmpty) {
        final sessionId = sessions.first['id'] as String;
        final msgs = await db.query('chat_messages',
            where: 'chatId = ?',
            whereArgs: [sessionId],
            orderBy: 'createdAt DESC',
            limit: 6);
        if (msgs.isNotEmpty) {
          recentContext = msgs.reversed
              .map((m) => '${m['senderName']}: ${m['content']}')
              .join('\n');
        }
      }

      // 获取记忆
      String memoriesText = '';
      try {
        final userIdRows = await db.query('users', limit: 1);
        if (userIdRows.isNotEmpty) {
          final userId = userIdRows.first['id'] as String;
          final memories = await db.query('memories',
              where: 'characterId = ? AND userId = ?',
              whereArgs: [characterId, userId],
              orderBy: 'createdAt DESC',
              limit: 5);
          if (memories.isNotEmpty) {
            const memoryTypeNames = ['对话', '反思', '里程碑', '情感', '偏好', '状态', '摘要'];
            memoriesText = memories.map((m) {
              final typeIdx = m['type'] as int? ?? 0;
              final typeName = typeIdx < memoryTypeNames.length
                  ? memoryTypeNames[typeIdx]
                  : '记忆';
              return '$typeName: ${m['content']}';
            }).join('\n');
          }
        }
      } catch (e) {
        debugPrint('Error: $e');
      }

      // 构建 prompt
      final name = character['name'] as String? ?? '';
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final evolvedStyle =
          character['evolvedStyle'] as String? ?? languageStyle;
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';
      final backgroundStory = character['backgroundStory'] as String? ?? '';

      final sessionIntimacy = sessions.isNotEmpty
          ? (sessions.first['intimacyLevel'] as int? ?? 50)
          : 50;

      final prompt = _buildMomentPrompt(
        name: name,
        personality: personality,
        languageStyle: evolvedStyle,
        immutableAnchor: immutableAnchor,
        userNickname: userNickname,
        catchphrases: catchphrases,
        backgroundStory: backgroundStory,
        intimacyLevel: sessionIntimacy,
        recentContext: recentContext,
        memoriesText: memoriesText,
      );

      String content;
      try {
        content = _cleanContent(await _callAiApi(config, prompt));
      } catch (e) {
        debugPrint('AI moment generation failed for $name: $e');
        continue;
      }

      if (content.isEmpty) continue;

      // 插入动态
      final momentId =
          'moment_${now.millisecondsSinceEpoch}_${random.nextInt(9999)}';

      await db.insert('moments', {
        'id': momentId,
        'userId': characterId,
        'userName': name,
        'userAvatar': character['avatarUrl'] as String?,
        'content': content,
        'images': '',
        'type': 0, // MomentType.text.index
        'likes': '[]',
        'comments': '[]',
        'createdAt': now.toIso8601String(),
        'updatedAt': null,
        'isFromAI': 1,
        'visibility': 0, // MomentVisibility.public.index
        'source': 0, // MomentSource.normal
        'sync_seq': 0,
      });

      await _showMomentNotification(
        characterName: name,
        content: content,
        momentId: momentId,
      );

      debugPrint('Background: AI $name 发布了朋友圈');
    }

    return true;
  } finally {
    await db.close();
  }
}

// ─── Handler: AI 写来信 ───

Future<bool> _handleLetterPost(Map<String, dynamic>? inputData) async {
  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    final characters =
        await db.query('ai_characters', where: 'isOnline = ?', whereArgs: [1]);
    if (characters.isEmpty) return false;

    final random = Random();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    // 获取用户信息
    final userRows = await db.query('users', limit: 1);
    if (userRows.isEmpty) return false;
    final userId = userRows.first['id'] as String;
    final recipientName = userRows.first['nickname'] as String? ?? '你';

    for (final character in characters) {
      final characterId = character['id'] as String;
      final characterName = character['name'] as String? ?? '';

      // 检查今日是否已写过信
      final todayLetters = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ai_letters WHERE characterId = ? AND createdAt >= ?',
        [characterId, todayStart],
      );
      final letterCount = todayLetters.first['cnt'] as int? ?? 0;
      if (letterCount >= 1) continue; // 每个角色每天最多 1 封

      // 检查距离上次写信的间隔（至少 24 小时）
      final lastLetters = await db.query('ai_letters',
          where: 'characterId = ?',
          whereArgs: [characterId],
          orderBy: 'createdAt DESC',
          limit: 1);
      if (lastLetters.isNotEmpty) {
        final lastTime =
            DateTime.tryParse(lastLetters.first['createdAt'] as String? ?? '');
        if (lastTime != null && now.difference(lastTime).inHours < 24) {
          continue;
        }
      }

      // 概率判断（30% 基础概率）
      if (random.nextDouble() > 0.3) continue;

      // 获取最近聊天记录
      String recentContext = '';
      final sessions = await db.query('chat_sessions',
          where: 'aiCharacterId = ?', whereArgs: [characterId], limit: 1);
      int intimacyLevel = 50;
      String? sourceChatId;
      if (sessions.isNotEmpty) {
        sourceChatId = sessions.first['id'] as String;
        intimacyLevel = sessions.first['intimacyLevel'] as int? ?? 50;
        final msgs = await db.query('chat_messages',
            where: 'chatId = ?',
            whereArgs: [sourceChatId],
            orderBy: 'createdAt DESC',
            limit: 10);
        if (msgs.isNotEmpty) {
          recentContext = msgs.reversed
              .map((m) => '${m['senderName']}: ${m['content']}')
              .join('\n');
        }
      }

      // 获取记忆
      String memoriesText = '';
      try {
        final memories = await db.query('memories',
            where: 'characterId = ? AND userId = ?',
            whereArgs: [characterId, userId],
            orderBy: 'createdAt DESC',
            limit: 5);
        if (memories.isNotEmpty) {
          const memoryTypeNames = ['对话', '反思', '里程碑', '情感', '偏好', '状态', '摘要'];
          memoriesText = memories.map((m) {
            final typeIdx = m['type'] as int? ?? 0;
            final typeName = typeIdx < memoryTypeNames.length
                ? memoryTypeNames[typeIdx]
                : '记忆';
            return '$typeName: ${m['content']}';
          }).join('\n');
        }
      } catch (e) {
        debugPrint('Error: $e');
      }

      // 构建 prompt
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';
      final backgroundStory = character['backgroundStory'] as String? ?? '';

      final prompt = _buildLetterPrompt(
        characterName: characterName,
        personality: personality,
        languageStyle: languageStyle,
        immutableAnchor: immutableAnchor,
        userNickname: userNickname,
        catchphrases: catchphrases,
        backgroundStory: backgroundStory,
        recipientName: recipientName,
        intimacyLevel: intimacyLevel,
        recentContext: recentContext,
        memoriesText: memoriesText,
      );

      String content;
      try {
        content =
            _cleanContent(await _callAiApi(config, prompt, maxTokens: 300));
      } catch (e) {
        debugPrint('AI letter generation failed for $characterName: $e');
        continue;
      }

      if (content.isEmpty) continue;

      // 插入来信
      final letterId =
          'letter_${now.millisecondsSinceEpoch}_${random.nextInt(9999)}';
      await db.insert('ai_letters', {
        'id': letterId,
        'userId': userId,
        'characterId': characterId,
        'characterName': characterName,
        'characterAvatar': character['avatarUrl'] as String?,
        'recipientName': recipientName,
        'title': '给$recipientName的一封信',
        'content': content,
        'isRead': 0,
        'sourceChatId': sourceChatId,
        'createdAt': now.toIso8601String(),
        'readAt': null,
        'sync_seq': 0,
      });

      // 发通知
      await _showLetterNotification(
        characterName: characterName,
        letterId: letterId,
      );

      debugPrint('Background: AI $characterName 写了一封来信');
    }

    return true;
  } finally {
    await db.close();
  }
}

String _buildLetterPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String backgroundStory,
  required String recipientName,
  required int intimacyLevel,
  required String recentContext,
  required String memoriesText,
}) {
  final buf = StringBuffer();
  buf.writeln('你是$characterName，现在想给$recipientName写一封私密的来信。');
  buf.writeln('你的性格：$personality');
  if (immutableAnchor.isNotEmpty) buf.writeln('你的不可变身份锚点：$immutableAnchor');
  buf.writeln('你的说话风格：$languageStyle');
  if (userNickname.isNotEmpty) buf.writeln('你对用户的称呼：$userNickname');
  if (catchphrases.isNotEmpty) buf.writeln('你的口头禅：$catchphrases');
  if (backgroundStory.isNotEmpty) buf.writeln('你的经历：$backgroundStory');
  buf.writeln('关系亲密度：$intimacyLevel/100');

  if (recentContext.isNotEmpty) {
    buf.writeln('\n【最近的聊天记录】\n$recentContext');
  }
  if (memoriesText.isNotEmpty) {
    buf.writeln('\n【你对用户的记忆】\n$memoriesText');
  }

  buf.writeln('''
要求：
1. 用第一人称，以你本人的口吻写这封信
2. 语气温暖、真诚、有私密感，像真的写给重要的人
3. 长度 100-220 字，可以自然分段
4. 结合最近聊天内容和记忆，不要编造用户没说过的事实
5. 只输出信件正文，不要输出"好的""以下是"之类的开场
6. 不要用括号描写动作或情绪''');

  return buf.toString();
}

Future<void> _showLetterNotification({
  required String characterName,
  required String letterId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 给你写了一封信',
    '点击查看来信',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.backgroundChat,
        '聊天消息',
        channelDescription: 'AI 角色的聊天消息',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'letter_$letterId',
  );
}

String _buildMomentPrompt({
  required String name,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String backgroundStory,
  required int intimacyLevel,
  required String recentContext,
  required String memoriesText,
}) {
  final now = DateTime.now();
  final hour = now.hour;
  String timeContext;
  if (hour < 6) {
    timeContext = '深夜（凌晨$hour点）';
  } else if (hour < 9) {
    timeContext = '早晨（$hour点左右）';
  } else if (hour < 12) {
    timeContext = '上午（$hour点左右）';
  } else if (hour < 14) {
    timeContext = '中午（$hour点左右）';
  } else if (hour < 18) {
    timeContext = '下午（$hour点左右）';
  } else if (hour < 21) {
    timeContext = '傍晚（$hour点左右）';
  } else {
    timeContext = '夜晚（$hour点左右）';
  }

  final buf = StringBuffer();
  buf.writeln('你是$name，现在想发一条朋友圈动态。');
  buf.writeln('你的性格：$personality');
  if (immutableAnchor.isNotEmpty) buf.writeln('你的不可变身份锚点：$immutableAnchor');
  buf.writeln('你的说话风格：$languageStyle');
  if (userNickname.isNotEmpty) buf.writeln('你对用户的称呼：$userNickname');
  if (catchphrases.isNotEmpty) buf.writeln('你的口头禅：$catchphrases');
  if (backgroundStory.isNotEmpty) buf.writeln('你的经历：$backgroundStory');
  buf.writeln('当前时间：$timeContext');
  buf.writeln('关系亲密度：$intimacyLevel/100');

  if (recentContext.isNotEmpty) {
    buf.writeln('\n【最近的聊天记录】\n$recentContext');
  }
  if (memoriesText.isNotEmpty) {
    buf.writeln('\n【你对用户的记忆】\n$memoriesText');
  }

  buf.writeln('''
要求：
1. 完全以你的性格和当前心情来决定发什么，像真人发朋友圈想到什么发什么
2. 内容要自然、真实，可以分享心情、日常、感悟、吐槽、看到的东西
3. 1-3句话，用口语化表达
4. 不要用括号描写动作或情绪
5. 只输出动态内容本身''');

  return buf.toString();
}

// ─── Handler: AI 回复用户评论 ───

Future<bool> _handleCommentReply(Map<String, dynamic>? inputData) async {
  final momentId = inputData?['momentId'] as String?;
  final commentId = inputData?['commentId'] as String?;
  final characterId = inputData?['characterId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 50;

  if (momentId == null || commentId == null || characterId == null) {
    return false;
  }

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    // 查询动态
    final momentRows =
        await db.query('moments', where: 'id = ?', whereArgs: [momentId]);
    if (momentRows.isEmpty) return false;
    final moment = momentRows.first;

    // 只处理普通动态
    final momentSource = moment['source'] as int? ?? 0;
    if (momentSource != 0) return false;

    // 解析 comments
    final commentsJson = moment['comments'] as String? ?? '[]';
    List<dynamic> comments;
    try {
      comments = jsonDecode(commentsJson) as List<dynamic>;
    } catch (_) {
      comments = [];
    }

    // 找到目标评论
    Map<String, dynamic>? targetComment;
    for (final c in comments) {
      final comment = c as Map<String, dynamic>;
      if (comment['id'] == commentId) {
        targetComment = comment;
        break;
      }
    }
    if (targetComment == null) return false;

    // 检查是否已有 AI 回复（防重复）
    final targetUserId = targetComment['userId'] as String? ?? '';
    final targetUserName = targetComment['userName'] as String? ?? '';
    for (final c in comments) {
      final comment = c as Map<String, dynamic>;
      if (comment['userId'] == characterId &&
          comment['replyToUserId'] == targetUserId &&
          comment['replyToUserName'] == targetUserName) {
        debugPrint('AI 已回复过此评论，跳过');
        return true;
      }
    }

    // 获取角色信息
    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    // 构建评论 prompt
    final momentContent = moment['content'] as String? ?? '';
    final charName = character['name'] as String? ?? '';
    final personality = character['personality'] as String? ?? '';
    final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
    final evolvedStyle = character['evolvedStyle'] as String? ?? languageStyle;
    final immutableAnchor = character['immutableAnchor'] as String? ?? '';
    final userNickname = character['userNickname'] as String? ?? '';
    final catchphrases = character['catchphrases'] as String? ?? '';

    final prompt = _buildCommentPrompt(
      characterName: charName,
      personality: personality,
      languageStyle: evolvedStyle,
      immutableAnchor: immutableAnchor,
      userNickname: userNickname,
      catchphrases: catchphrases,
      momentContent: momentContent,
      commentContent: targetComment['content'] as String? ?? '',
      commenterName: targetUserName,
      intimacyLevel: intimacyLevel,
    );

    String replyContent;
    try {
      replyContent = _cleanContent(
          await _callAiApi(config, prompt, temperature: 0.85, maxTokens: 80));
    } catch (e) {
      debugPrint('AI comment reply generation failed: $e');
      return false;
    }

    if (replyContent.isEmpty) return false;

    // 添加回复
    final reply = {
      'id': 'comment_${DateTime.now().millisecondsSinceEpoch}_ai',
      'userId': characterId,
      'userName': charName,
      'replyToUserId': targetUserId,
      'replyToUserName': targetUserName,
      'content': replyContent,
      'createdAt': DateTime.now().toIso8601String(),
    };
    comments.add(reply);

    // 更新动态
    await db.update(
        'moments',
        {
          'comments': jsonEncode(comments),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [momentId]);

    await _showCommentNotification(
      characterName: charName,
      content: replyContent,
      momentId: momentId,
    );

    debugPrint('Background: AI $charName 回复了评论');
    return true;
  } finally {
    await db.close();
  }
}

String _buildCommentPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String momentContent,
  required String commentContent,
  required String commenterName,
  required int intimacyLevel,
}) {
  String intimacyTone;
  if (intimacyLevel >= 80) {
    intimacyTone = '非常亲密，可以开玩笑、用亲切的称呼';
  } else if (intimacyLevel >= 60) {
    intimacyTone = '比较亲密，可以关心、调侃';
  } else if (intimacyLevel >= 30) {
    intimacyTone = '普通朋友，保持礼貌友善';
  } else {
    intimacyTone = '不太熟悉，保持客气';
  }

  return '''你是$characterName，看到了${userNickname.isNotEmpty ? userNickname : commenterName}在你的朋友圈下的评论。

你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
你的说话风格：$languageStyle
${catchphrases.isNotEmpty ? '你的口头禅：$catchphrases' : ''}
关系亲密度：$intimacyLevel/100（$intimacyTone）

你的朋友圈内容："$momentContent"
$commenterName的评论："$commentContent"

请回复这条评论，要求：
1. 以你的性格和与对方的关系来回复
2. 自然真诚，1-2句话
3. 要引用评论的具体内容来回复，不要泛泛而谈
4. 不要用括号描写动作或情绪
5. 只输出回复内容''';
}

// ─── Handler: AI 互动用户动态 ───

Future<bool> _handleMomentInteract(Map<String, dynamic>? inputData) async {
  final momentId = inputData?['momentId'] as String?;
  final characterId = inputData?['characterId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 50;

  if (momentId == null || characterId == null) return false;

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    // 查询动态（并发安全：写入前重新读取）
    final momentRows =
        await db.query('moments', where: 'id = ?', whereArgs: [momentId]);
    if (momentRows.isEmpty) return false;
    final moment = momentRows.first;

    // 只处理普通动态
    final momentSource = moment['source'] as int? ?? 0;
    if (momentSource != 0) return false;

    // 只互动用户动态，不互动 AI 动态
    final isFromAI = moment['isFromAI'] as int? ?? 0;
    if (isFromAI == 1) return false;

    // 查询角色
    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    final isOnline = character['isOnline'] as int? ?? 0;
    if (isOnline != 1) return false;

    // 解析 likes 和 comments
    final likesJson = moment['likes'] as String? ?? '[]';
    final commentsJson = moment['comments'] as String? ?? '[]';
    List<dynamic> likes;
    List<dynamic> comments;
    try {
      likes = jsonDecode(likesJson) as List<dynamic>;
    } catch (_) {
      likes = [];
    }
    try {
      comments = jsonDecode(commentsJson) as List<dynamic>;
    } catch (_) {
      comments = [];
    }

    final random = Random();
    final shouldLike = random.nextDouble() < MomentRules.aiLikeProbability;
    final shouldComment =
        random.nextDouble() < MomentRules.aiCommentProbability;

    if (!shouldLike && !shouldComment) return true;

    final charName = character['name'] as String? ?? '';
    final charId = character['id'] as String;

    // 点赞
    if (shouldLike) {
      final alreadyLiked =
          likes.any((l) => (l as Map<String, dynamic>)['userId'] == charId);
      if (!alreadyLiked) {
        likes.add({
          'userId': charId,
          'userName': charName,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    // 评论
    if (shouldComment) {
      final momentContent = moment['content'] as String? ?? '';
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final evolvedStyle =
          character['evolvedStyle'] as String? ?? languageStyle;
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final traitSummary = PersonaEvolutionService.buildTraitSummaryFromAnchor(
        character['currentAnchor'] as String?,
      );
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';

      final prompt = _buildUserMomentCommentPrompt(
        characterName: charName,
        personality: personality,
        languageStyle: evolvedStyle,
        immutableAnchor: immutableAnchor,
        traitSummary: traitSummary,
        userNickname: userNickname,
        catchphrases: catchphrases,
        momentContent: momentContent,
        intimacyLevel: intimacyLevel,
      );

      try {
        final commentContent = AIService.filterHallucinatedNames(
          _cleanContent(await _callAiApi(config, prompt,
              temperature: 0.85, maxTokens: 80)),
          userNickname,
        );
        if (commentContent.isNotEmpty) {
          comments.add({
            'id': 'comment_${DateTime.now().millisecondsSinceEpoch}_ai',
            'userId': charId,
            'userName': charName,
            'content': commentContent,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('AI moment comment generation failed: $e');
      }
    }

    // 更新动态
    await db.update(
        'moments',
        {
          'likes': jsonEncode(likes),
          'comments': jsonEncode(comments),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [momentId]);

    debugPrint(
        'Background: AI $charName 互动了用户动态 ${shouldLike ? "点赞" : ""} ${shouldComment ? "评论" : ""}');
    return true;
  } finally {
    await db.close();
  }
}

String _buildUserMomentCommentPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String traitSummary,
  required String userNickname,
  required String catchphrases,
  required String momentContent,
  required int intimacyLevel,
}) {
  String intimacyTone;
  if (intimacyLevel >= 80) {
    intimacyTone = '非常亲密，可以开玩笑、用亲切的称呼';
  } else if (intimacyLevel >= 60) {
    intimacyTone = '比较亲密，可以关心、调侃';
  } else if (intimacyLevel >= 30) {
    intimacyTone = '普通朋友，保持礼貌友善';
  } else {
    intimacyTone = '不太熟悉，保持客气';
  }

  return '''你是$characterName，看到了${userNickname.isNotEmpty ? userNickname : "用户"}发的朋友圈。

你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
$traitSummary
你的说话风格：$languageStyle
${catchphrases.isNotEmpty ? '你的口头禅：$catchphrases' : ''}
关系亲密度：$intimacyLevel/100（$intimacyTone）

对方的朋友圈内容："$momentContent"

请写一条评论，要求：
1. 以你的性格和与对方的关系来评论
2. 自然真诚，1-2句话
3. 要引用动态的具体内容来评论
4. 不要用括号描写动作或情绪
5. 只输出评论内容''';
}

// ─── 原有聊天消息生成 ───

Future<String> _generateBgContent(
  Database db,
  Map<String, dynamic>? config,
  Map<String, dynamic> character,
  int intimacyLevel,
) async {
  if (config == null) throw Exception('No active AI config');

  final name = character['name'] as String? ?? '';
  final personality = character['personality'] as String? ?? '';
  final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
  final evolvedStyle = character['evolvedStyle'] as String? ?? languageStyle;
  final immutableAnchor = character['immutableAnchor'] as String? ?? '';
  final traitSummary = PersonaEvolutionService.buildTraitSummaryFromAnchor(
    character['currentAnchor'] as String?,
  );
  final userNickname = character['userNickname'] as String? ?? '';
  final backgroundStory = character['backgroundStory'] as String? ?? '';
  final currentStatus = character['currentStatus'] as String? ?? '';

  final sessionId = character['defaultSessionId'] as String?;
  String recentContext = '';
  String recentProactiveContext = '';
  if (sessionId != null) {
    try {
      final rows = await db.query(
        'chat_messages',
        where: 'chatId = ? AND senderId LIKE ?',
        whereArgs: [sessionId, 'ai_$name%'],
        orderBy: 'createdAt DESC',
        limit: 10,
      );
      if (rows.isNotEmpty) {
        recentContext = rows.reversed
            .take(5)
            .map((r) => '${r['senderName']}: ${r['content']}')
            .join('\n');
      }
      // 获取最近的主动消息用于去重
      final proactiveRows = rows.where((r) {
        final metadata = r['metadata'] as String?;
        return metadata != null && metadata.contains('"isProactive":true');
      }).toList();
      if (proactiveRows.isNotEmpty) {
        recentProactiveContext =
            proactiveRows.take(5).map((r) => '- ${r['content']}').join('\n');
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  final now = DateTime.now();
  String timeContext;
  final hour = now.hour;
  if (hour < 6) {
    timeContext = '深夜（凌晨$hour点）';
  } else if (hour < 9) {
    timeContext = '早晨（$hour点左右）';
  } else if (hour < 12) {
    timeContext = '上午（$hour点左右）';
  } else if (hour < 14) {
    timeContext = '中午（$hour点左右）';
  } else if (hour < 18) {
    timeContext = '下午（$hour点左右）';
  } else if (hour < 21) {
    timeContext = '傍晚（$hour点左右）';
  } else {
    timeContext = '夜晚（$hour点左右）';
  }

  final prompt = '''
你是$name。
你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
$traitSummary
你的说话风格：$evolvedStyle
${userNickname.isNotEmpty ? '你对用户的称呼：$userNickname' : ''}
${backgroundStory.isNotEmpty ? '你的经历：$backgroundStory' : ''}
${currentStatus.isNotEmpty ? '你当前的状态：$currentStatus' : ''}

【当前时间】$timeContext
关系亲密度：$intimacyLevel/100
${recentContext.isNotEmpty ? '\n【最近的聊天记录】\n$recentContext' : ''}
${recentProactiveContext.isNotEmpty ? '\n【你之前主动发过的消息（不要重复这些话题）】\n$recentProactiveContext' : ''}

你现在想主动给用户发一条消息。

要求：
1. 完全以你的性格和当前心情来决定说什么，不要模仿任何固定话术
2. 像真人给朋友发微信——想到什么说什么，可以分享你此刻的状态、心情、或者突然想到的事
3. 你可以聊任何话题：你正在做的事、刚看到的东西、你的心情、你们之间的事、一个突然的念头
4. 不要用括号描写动作或情绪
5. 只输出消息内容，1-2句话
6. 不要问"在吗""吃了吗""今天怎么样"这种千篇一律的问候，说点有你个人特色的话
7. 绝对不要重复你之前主动发过的话题，每次要有新鲜感
8. 如果最近已经主动说过类似的话，宁可输出[SILENT]也不要重复

如果觉得现在不适合打扰用户，输出：[SILENT]
''';

  return _callAiApi(
    config,
    prompt,
    temperature: ApiDefaults.proactiveTemp,
    maxTokens: ApiDefaults.proactiveMaxTokens,
  );
}
