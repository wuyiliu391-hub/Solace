/// 角色性别 Prompt 配置（从 ImageGenConfig 动态读取，零硬编码）
///
/// 男性角色和女性角色有不同的外貌描述规则和排除规则。
/// 这些配置存储在 SharedPreferences 中，可通过设置页面修改。
class GenderPromptDefaults {
  GenderPromptDefaults._();

  /// 性别感知配置的 SharedPreferences key
  static const String kGenderConfigPrefix = 'imggen_gender_';

  /// 默认配置（首次启动时写入）
  static const Map<String, Map<String, String>> defaults = {
    'female': {
      'label': '女性',
      'prefix': '1girl, beautiful female, feminine features, soft facial structure, '
          'delicate hands, slender figure, elegant posture',
      'appearance_rules': '''女性角色生成规则：
- 五官柔和，具有女性特征（柳眉、杏眼、小巧鼻梁、樱桃唇）
- 身材纤细，有女性曲线
- 手部纤细修长
- 禁止生成：喉结、男性肌肉线条、胡须、方形下颌、过粗的眉毛''',
      'anatomy_rules': 'male anatomy, masculine features, beard, facial hair, '
          'Adam\'s apple, broad shoulders, muscular male body, flat chest',
    },
    'male': {
      'label': '男性',
      'prefix': '1boy, handsome male, masculine features, defined jawline, '
          'broad shoulders, tall and lean, confident posture',
      'appearance_rules': '''男性角色生成规则：
- 五官立体硬朗，具有男性特征（剑眉、深邃眼神、挺拔鼻梁、清晰下颌线）
- 身材匀称，肩膀宽阔
- 手部骨节分明
- 禁止生成：女性妆容（口红、眼影、腮红）、女性胸部特征、过细的眉毛、过于柔美的面部轮廓''',
      'anatomy_rules': 'female anatomy, breasts, feminine curves, makeup, lipstick, '
          'blush, eyeshadow, narrow shoulders, delicate feminine face, '
          'cleavage, female body shape',
    },
    'other': {
      'label': '其他',
      'prefix': '1person, androgynous features, neutral appearance',
      'appearance_rules': '''中性角色生成规则：
- 五官中性化，兼具柔美与硬朗
- 身材匀称自然
- 无明显性别特征偏向''',
      'anatomy_rules': 'extreme masculine features, extreme feminine features, '
          'exaggerated gender characteristics',
    },
  };
}