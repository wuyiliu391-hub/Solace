import '../utils/prefs_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS 服务配置（MiMo VoiceClone）
///
/// 模型 ID 内置，API Key 由用户自行配置
class TTSConfig {
  TTSConfig._();

  static const String baseUrl = 'https://api.xiaomimimo.com/v1';
  static const String model = 'mimo-v2.5-tts-voiceclone';
  static const String defaultFormat = 'wav';
  static const String voiceSampleDir = 'voice_samples';
  static const String ttsCacheDir = 'tts_cache';
  static const int maxCacheFiles = 200;

  /// 稳定模式参数 — 最大限度保证音色一致
  static const double temperature = 0.0;
  static const double topP = 0.5;

  /// 默认风格指令 — 模拟真人自然说话
  /// 允许自然的情绪起伏，但不要刻意夸张
  static const String defaultStyleInstruction =
      '像真人朋友一样自然说话，语速适中，语气亲切自然，有适当的情绪起伏但不夸张。';

  /// 试听文本
  static const String previewText = '你好，我是你的AI伙伴，很高兴认识你。';

  /// 每句最大字符数（MiMo 安全上限 45~50 汉字，适当放宽减少切分）
  static const int maxCharsPerSentence = 50;

  /// 标准语速：1汉字 ≈ 0.32秒
  static const double charsPerSecond = 0.32;

  /// 单次 TTS 接口最大音频时长（秒）
  static const int maxAudioDurationSec = 60;

  /// 情绪关键词 → MiMo 内联标签映射
  static const Map<List<String>, String> emotionKeywords = {
    ['开心', '高兴', '太好了', '哈哈', '嘻嘻', '嘿嘿', '耶', '好棒',
     'haha', 'hehe', 'lol', 'yay', 'awesome', 'great', 'wonderful']:
        '(开心)',
    ['难过', '伤心', '哭', '呜呜', '心疼', '不舍', '想念', '思念',
     'sad', 'cry', 'miss', 'sorry']:
        '(悲伤)',
    ['生气', '愤怒', '气死', '讨厌', '烦死了', '可恶', '混蛋',
     'angry', 'hate', 'annoying']:
        '(愤怒)',
    ['温柔', '乖', '宝贝', '亲爱的', '抱抱', '摸摸头', '好乖',
     'gentle', 'sweet', 'dear', 'honey']:
        '(温柔)',
    ['害羞', '脸红', '不好意思', '讨厌啦', '人家', '羞羞',
     'shy', 'blush', 'embarrassed']:
        '(害羞)',
    ['担心', '小心', '注意', '别忘了', '还好吗', '没事吧', '别着急',
     'careful', 'worried', 'take care']:
        '(担忧)',
    ['天哪', '不会吧', '真的吗', '啊', '哇', '什么', '居然',
     'wow', 'really', 'omg', 'what']:
        '(惊讶)',
    ['唉', '算了', '没办法', '随你吧', '好吧好吧',
     'sigh', 'whatever', 'fine']:
        '(叹气)',
    ['嘛', '啦', '呀', '嗯嗯', '嘿嘿嘿', '才不要', '就要',
     'please', 'come on']:
        '(撒娇)',
  };

  // ── API Key 管理 ──

  static const String _prefKey = 'tts_api_key';
  static String? cachedApiKey;

  /// 获取用户配置的 TTS API Key（同步，使用缓存）
  static Future<String?> getApiKey() async {
    final prefs = await PrefsHelper.instance;
    cachedApiKey = prefs.getString(_prefKey);
    return cachedApiKey;
  }

  /// 保存 TTS API Key
  static Future<void> setApiKey(String key) async {
    cachedApiKey = key;
    final prefs = await PrefsHelper.instance;
    await prefs.setString(_prefKey, key);
  }

  /// 删除 TTS API Key
  static Future<void> clearApiKey() async {
    cachedApiKey = null;
    final prefs = await PrefsHelper.instance;
    await prefs.remove(_prefKey);
  }

  /// 检查是否已配置 API Key
  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// 初始化缓存（应用启动时调用）
  static Future<void> init() async {
    await getApiKey();
  }
}
