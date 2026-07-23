import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'avatar_config.g.dart';

/// 崽崽（Avatar）形象配置
///
/// 描述当前选中的所有装扮、捏脸参数、化妆颜色。
/// 所有字段使用内置索引或枚举，不依赖用户上传文件。
@JsonSerializable()
class AvatarConfig {
  /// 体型变体（决定身高/胖瘦轮廓）
  final String bodyVariant;

  /// 头部轮廓变体
  final String headVariant;

  /// 脸部肤色变体
  final String faceVariant;

  /// 发型变体（前发）
  final String hairFrontVariant;

  /// 发型变体（后发）
  final String hairBackVariant;

  /// 眉毛变体
  final String eyebrowVariant;

  /// 眼睛变体
  final String eyesVariant;

  /// 嘴巴变体
  final String mouthVariant;

  /// 上衣变体
  final String shirtVariant;

  /// 下装变体
  final String pantsVariant;

  /// 饰品变体（null 表示无）
  final String? accessoryVariant;

  /// 捏脸参数
  final FaceShape faceShape;

  /// 化妆参数
  final Makeup makeup;

  /// 部位显隐
  final Set<String> visibleParts;

  const AvatarConfig({
    this.bodyVariant = 'default',
    this.headVariant = 'default',
    this.faceVariant = 'default',
    this.hairFrontVariant = 'bob',
    this.hairBackVariant = 'bob',
    this.eyebrowVariant = 'default',
    this.eyesVariant = 'default',
    this.mouthVariant = 'default',
    this.shirtVariant = 'default',
    this.pantsVariant = 'default',
    this.accessoryVariant,
    this.faceShape = const FaceShape(),
    this.makeup = const Makeup(),
    this.visibleParts = const {
      'body',
      'head',
      'face',
      'hair_back',
      'hair_front',
      'eyebrows',
      'eyes',
      'mouth',
      'shirt',
      'pants',
      'accessory',
    },
  });

  factory AvatarConfig.fromJson(Map<String, dynamic> json) =>
      _$AvatarConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AvatarConfigToJson(this);

  AvatarConfig copyWith({
    String? bodyVariant,
    String? headVariant,
    String? faceVariant,
    String? hairFrontVariant,
    String? hairBackVariant,
    String? eyebrowVariant,
    String? eyesVariant,
    String? mouthVariant,
    String? shirtVariant,
    String? pantsVariant,
    String? accessoryVariant,
    FaceShape? faceShape,
    Makeup? makeup,
    Set<String>? visibleParts,
  }) {
    return AvatarConfig(
      bodyVariant: bodyVariant ?? this.bodyVariant,
      headVariant: headVariant ?? this.headVariant,
      faceVariant: faceVariant ?? this.faceVariant,
      hairFrontVariant: hairFrontVariant ?? this.hairFrontVariant,
      hairBackVariant: hairBackVariant ?? this.hairBackVariant,
      eyebrowVariant: eyebrowVariant ?? this.eyebrowVariant,
      eyesVariant: eyesVariant ?? this.eyesVariant,
      mouthVariant: mouthVariant ?? this.mouthVariant,
      shirtVariant: shirtVariant ?? this.shirtVariant,
      pantsVariant: pantsVariant ?? this.pantsVariant,
      accessoryVariant: accessoryVariant ?? this.accessoryVariant,
      faceShape: faceShape ?? this.faceShape,
      makeup: makeup ?? this.makeup,
      visibleParts: visibleParts ?? this.visibleParts,
    );
  }

  /// 默认配置
  static const AvatarConfig defaultConfig = AvatarConfig();
}

/// 脸部捏脸参数
///
/// 所有值在 [-1, 1] 之间，渲染器根据最大值映射到像素偏移。
@JsonSerializable()
class FaceShape {
  /// 眼睛整体大小
  final double eyeScale;

  /// 两眼间距
  final double eyeSpacing;

  /// 眼睛垂直位置（-1 靠上，1 靠下）
  final double eyeVertical;

  /// 嘴巴大小
  final double mouthScale;

  /// 嘴巴垂直位置
  final double mouthVertical;

  /// 眉毛垂直位置
  final double eyebrowVertical;

  /// 眉毛倾斜度
  final double eyebrowTilt;

  /// 头部整体缩放
  final double headScale;

  const FaceShape({
    this.eyeScale = 0.0,
    this.eyeSpacing = 0.0,
    this.eyeVertical = 0.0,
    this.mouthScale = 0.0,
    this.mouthVertical = 0.0,
    this.eyebrowVertical = 0.0,
    this.eyebrowTilt = 0.0,
    this.headScale = 0.0,
  });

  factory FaceShape.fromJson(Map<String, dynamic> json) =>
      _$FaceShapeFromJson(json);

  Map<String, dynamic> toJson() => _$FaceShapeToJson(this);

  FaceShape copyWith({
    double? eyeScale,
    double? eyeSpacing,
    double? eyeVertical,
    double? mouthScale,
    double? mouthVertical,
    double? eyebrowVertical,
    double? eyebrowTilt,
    double? headScale,
  }) {
    return FaceShape(
      eyeScale: eyeScale ?? this.eyeScale,
      eyeSpacing: eyeSpacing ?? this.eyeSpacing,
      eyeVertical: eyeVertical ?? this.eyeVertical,
      mouthScale: mouthScale ?? this.mouthScale,
      mouthVertical: mouthVertical ?? this.mouthVertical,
      eyebrowVertical: eyebrowVertical ?? this.eyebrowVertical,
      eyebrowTilt: eyebrowTilt ?? this.eyebrowTilt,
      headScale: headScale ?? this.headScale,
    );
  }
}

/// 化妆参数
@JsonSerializable()
class Makeup {
  /// 肤色（脸/身体基础色）
  @ColorJsonConverter()
  final Color skinColor;

  /// 腮红颜色
  @ColorJsonConverter()
  final Color blushColor;

  /// 唇色
  @ColorJsonConverter()
  final Color lipColor;

  /// 眼影颜色
  @ColorJsonConverter()
  final Color eyeShadowColor;

  /// 瞳色（覆盖眼睛素材色调）
  @ColorJsonConverter()
  final Color irisColor;

  /// 发色（覆盖头发素材色调）
  @ColorJsonConverter()
  final Color hairColor;

  const Makeup({
    this.skinColor = const Color(0xFFFFE0D0),
    this.blushColor = const Color(0xFFFFB7B2),
    this.lipColor = const Color(0xFFFF6B81),
    this.eyeShadowColor = const Color(0xFFE6B8A2),
    this.irisColor = const Color(0xFF6B4F3B),
    this.hairColor = const Color(0xFF3E2723),
  });

  factory Makeup.fromJson(Map<String, dynamic> json) => _$MakeupFromJson(json);

  Map<String, dynamic> toJson() => _$MakeupToJson(this);

  Makeup copyWith({
    Color? skinColor,
    Color? blushColor,
    Color? lipColor,
    Color? eyeShadowColor,
    Color? irisColor,
    Color? hairColor,
  }) {
    return Makeup(
      skinColor: skinColor ?? this.skinColor,
      blushColor: blushColor ?? this.blushColor,
      lipColor: lipColor ?? this.lipColor,
      eyeShadowColor: eyeShadowColor ?? this.eyeShadowColor,
      irisColor: irisColor ?? this.irisColor,
      hairColor: hairColor ?? this.hairColor,
    );
  }
}

/// Color ↔ int JSON 转换器
class ColorJsonConverter implements JsonConverter<Color, int> {
  const ColorJsonConverter();

  @override
  Color fromJson(int json) => Color(json);

  @override
  int toJson(Color object) => object.value;
}
