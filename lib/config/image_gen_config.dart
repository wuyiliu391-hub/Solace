import 'package:shared_preferences/shared_preferences.dart';

/// 图像生成全局配置（零硬编码，全部从 SharedPreferences 动态读取）
///
/// 所有可调参数均可通过 [set] 方法修改，无需改动源码。
/// 首次启动时自动写入推荐默认值。
class ImageGenConfig {
  ImageGenConfig._();

  // ─── SharedPreferences Keys ───
  static const _kModelName = 'imggen_model_name';
  static const _kBaseUrl = 'imggen_base_url';
  static const _kImagesPath = 'imggen_images_path';
  static const _kDefaultResolution = 'imggen_default_resolution';
  static const _kDefaultStyle = 'imggen_default_style';
  static const _kPositivePrefix = 'imggen_positive_prefix';
  static const _kNegativePrompt = 'imggen_negative_prompt';
  static const _kTextTimeoutSec = 'imggen_text_timeout_sec';
  static const _kImageTimeoutSec = 'imggen_image_timeout_sec';
  static const _kDefaultSeed = 'imggen_default_seed';
  static const _kReferenceWeight = 'imggen_reference_weight';
  static const _kHandFixEnabled = 'imggen_hand_fix_enabled';
  static const _kControlNetEnabled = 'imggen_controlnet_enabled';
  static const _kApiKey = 'imggen_api_key';

  // ─── 默认值（仅首次启动写入） ───
  static const _defaults = {
    _kModelName: 'gpt-image-2',
    _kBaseUrl: 'https://qwen2apiloliu-chatgpt2api-v2.hf.space/v1',
    _kImagesPath: '/images/generations',
    _kDefaultResolution: '1024x1792',
    _kDefaultStyle: 'anime',
    _kPositivePrefix:
        'masterpiece, best quality, ultra detailed, '
        'soft cinematic lighting, subtle film grain',
    _kNegativePrompt:
        'worst quality, low quality, normal quality, lowres, blurry, '
        'bad anatomy, bad hands, extra fingers, fewer fingers, missing fingers, '
        'extra limbs, fused fingers, too many fingers, long neck, '
        'mutated hands, poorly drawn hands, poorly drawn face, '
        'mutation, deformed, ugly, duplicate, morbid, mutilated, '
        'extra arms, extra legs, malformed limbs, disfigured, '
        'text, watermark, signature, jpeg artifacts, grainy, error, '
        'nsfw, nude, naked, exposed, revealing, suggestive, erotic, '
        'explicit, adult content, sexual, provocative, inappropriate',
    _kTextTimeoutSec: '120',
    _kImageTimeoutSec: '180',
    _kDefaultSeed: '-1',
    _kReferenceWeight: '0.85',
    _kHandFixEnabled: 'true',
    _kControlNetEnabled: 'false',
    _kApiKey: 'chatgpt2api',
  };

  /// 初始化：首次启动写入默认值，后续启动不覆盖
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _defaults.entries) {
      if (!prefs.containsKey(entry.key)) {
        await prefs.setString(entry.key, entry.value);
      }
    }
  }

  // ─── 读取方法 ───

  static Future<String> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? _defaults[key] ?? '';
  }

  static Future<int> getInt(String key) async {
    final raw = await getString(key);
    return int.tryParse(raw) ?? 0;
  }

  static Future<double> getDouble(String key) async {
    final raw = await getString(key);
    return double.tryParse(raw) ?? 0.0;
  }

  static Future<bool> getBool(String key) async {
    final raw = await getString(key);
    return raw.toLowerCase() == 'true';
  }

  // ─── 写入方法 ───

  static Future<void> set(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  // ─── 便捷访问器 ───

  static Future<String> get modelName => getString(_kModelName);
  static Future<String> get baseUrl => getString(_kBaseUrl);
  static Future<String> get imagesPath => getString(_kImagesPath);
  static Future<String> get defaultResolution => getString(_kDefaultResolution);
  static Future<String> get defaultStyle => getString(_kDefaultStyle);
  static Future<String> get positivePrefix => getString(_kPositivePrefix);
  static Future<String> get negativePrompt => getString(_kNegativePrompt);
  static Future<int> get textTimeoutSec => getInt(_kTextTimeoutSec);
  static Future<int> get imageTimeoutSec => getInt(_kImageTimeoutSec);
  static Future<int> get defaultSeed => getInt(_kDefaultSeed);
  static Future<double> get referenceWeight => getDouble(_kReferenceWeight);
  static Future<bool> get handFixEnabled => getBool(_kHandFixEnabled);
  static Future<bool> get controlNetEnabled => getBool(_kControlNetEnabled);

  /// API Key 管理
  static Future<String?> getApiKey() async {
    final key = await getString(_kApiKey);
    return key.isEmpty ? null : key;
  }

  static Future<void> setApiKey(String key) async {
    await set(_kApiKey, key);
  }

  static Future<void> clearApiKey() async {
    await set(_kApiKey, '');
  }

  static Future<bool> hasValidApiKey() async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return false;
    // chatgpt2api 默认 auth-key 或标准前缀 key
    return key == 'chatgpt2api' ||
        (key.length >= 20 &&
            (key.startsWith('sk-') ||
                key.startsWith('ag-') ||
                key.startsWith('agnes-') ||
                key.startsWith('ak-')));
  }

  /// 校验 API Key 格式，返回 null 表示合法，否则返回错误提示
  static String? validateApiKey(String key) {
    if (key.isEmpty) return 'API Key 不能为空';
    if (key == 'chatgpt2api') return null;
    if (key.length < 20) return 'API Key 长度不足';
    if (!(key.startsWith('sk-') ||
        key.startsWith('ag-') ||
        key.startsWith('agnes-') ||
        key.startsWith('ak-'))) {
      return 'API Key 格式不正确，应以 sk-/ag-/agnes-/ak- 开头';
    }
    return null;
  }

  // ─── 性别感知 Prompt 配置 ───
  static const _kGenderFemalePrefix = 'imggen_gender_female_prefix';
  static const _kGenderFemaleAnatomy = 'imggen_gender_female_anatomy';
  static const _kGenderMalePrefix = 'imggen_gender_male_prefix';
  static const _kGenderMaleAnatomy = 'imggen_gender_male_anatomy';
  static const _kGenderOtherPrefix = 'imggen_gender_other_prefix';
  static const _kGenderOtherAnatomy = 'imggen_gender_other_anatomy';
  static const _kResolution4K = 'imggen_resolution_4k';
  static const _kLoraPath = 'imggen_lora_path';

  /// 获取性别感知 Prompt 配置（包含 prefix 和 anatomy_rules）
  static Future<Map<String, String>> get genderPromptConfig async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'female': prefs.getString(_kGenderFemalePrefix) ?? '1girl, beautiful female, feminine features, soft facial structure, delicate hands, slender figure, elegant posture',
      'male': prefs.getString(_kGenderMalePrefix) ?? '1boy, handsome male, masculine features, defined jawline, broad shoulders, tall and lean, confident posture',
      'other': prefs.getString(_kGenderOtherPrefix) ?? '1person, androgynous features, neutral appearance',
      'appearance_rules': 'female anatomy rules from config',
      'anatomy_rules': 'gender-mismatched anatomy terms from config',
    };
  }

  /// 设置性别前缀
  static Future<void> setGenderPrefix(String gender, String prefix) async {
    final key = 'imggen_gender_${gender}_prefix';
    await set(key, prefix);
  }

  /// 4K 分辨率开关
  static Future<bool> get use4KResolution async {
    final raw = await getString(_kResolution4K);
    return raw == 'true';
  }

  static Future<void> setUse4KResolution(bool value) async {
    await set(_kResolution4K, value.toString());
  }

  /// 角色专属 LoRA 路径（可选扩展）
  static Future<String> getLoraPath(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('imggen_lora_${characterId}') ?? '';
  }

  static Future<void> setLoraPath(String characterId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('imggen_lora_${characterId}', path);
  }
}
