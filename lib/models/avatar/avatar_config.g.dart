// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'avatar_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AvatarConfig _$AvatarConfigFromJson(Map<String, dynamic> json) => AvatarConfig(
      bodyVariant: json['bodyVariant'] as String? ?? 'default',
      headVariant: json['headVariant'] as String? ?? 'default',
      faceVariant: json['faceVariant'] as String? ?? 'default',
      hairFrontVariant: json['hairFrontVariant'] as String? ?? 'bob',
      hairBackVariant: json['hairBackVariant'] as String? ?? 'bob',
      eyebrowVariant: json['eyebrowVariant'] as String? ?? 'default',
      eyesVariant: json['eyesVariant'] as String? ?? 'default',
      mouthVariant: json['mouthVariant'] as String? ?? 'default',
      shirtVariant: json['shirtVariant'] as String? ?? 'default',
      pantsVariant: json['pantsVariant'] as String? ?? 'default',
      accessoryVariant: json['accessoryVariant'] as String?,
      faceShape: json['faceShape'] == null
          ? const FaceShape()
          : FaceShape.fromJson(json['faceShape'] as Map<String, dynamic>),
      makeup: json['makeup'] == null
          ? const Makeup()
          : Makeup.fromJson(json['makeup'] as Map<String, dynamic>),
      visibleParts: (json['visibleParts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const {
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
            'accessory'
          },
    );

Map<String, dynamic> _$AvatarConfigToJson(AvatarConfig instance) =>
    <String, dynamic>{
      'bodyVariant': instance.bodyVariant,
      'headVariant': instance.headVariant,
      'faceVariant': instance.faceVariant,
      'hairFrontVariant': instance.hairFrontVariant,
      'hairBackVariant': instance.hairBackVariant,
      'eyebrowVariant': instance.eyebrowVariant,
      'eyesVariant': instance.eyesVariant,
      'mouthVariant': instance.mouthVariant,
      'shirtVariant': instance.shirtVariant,
      'pantsVariant': instance.pantsVariant,
      'accessoryVariant': instance.accessoryVariant,
      'faceShape': instance.faceShape,
      'makeup': instance.makeup,
      'visibleParts': instance.visibleParts.toList(),
    };

FaceShape _$FaceShapeFromJson(Map<String, dynamic> json) => FaceShape(
      eyeScale: (json['eyeScale'] as num?)?.toDouble() ?? 0.0,
      eyeSpacing: (json['eyeSpacing'] as num?)?.toDouble() ?? 0.0,
      eyeVertical: (json['eyeVertical'] as num?)?.toDouble() ?? 0.0,
      mouthScale: (json['mouthScale'] as num?)?.toDouble() ?? 0.0,
      mouthVertical: (json['mouthVertical'] as num?)?.toDouble() ?? 0.0,
      eyebrowVertical: (json['eyebrowVertical'] as num?)?.toDouble() ?? 0.0,
      eyebrowTilt: (json['eyebrowTilt'] as num?)?.toDouble() ?? 0.0,
      headScale: (json['headScale'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$FaceShapeToJson(FaceShape instance) => <String, dynamic>{
      'eyeScale': instance.eyeScale,
      'eyeSpacing': instance.eyeSpacing,
      'eyeVertical': instance.eyeVertical,
      'mouthScale': instance.mouthScale,
      'mouthVertical': instance.mouthVertical,
      'eyebrowVertical': instance.eyebrowVertical,
      'eyebrowTilt': instance.eyebrowTilt,
      'headScale': instance.headScale,
    };

Makeup _$MakeupFromJson(Map<String, dynamic> json) => Makeup(
      skinColor: json['skinColor'] == null
          ? const Color(0xFFFFE0D0)
          : const ColorJsonConverter()
              .fromJson((json['skinColor'] as num).toInt()),
      blushColor: json['blushColor'] == null
          ? const Color(0xFFFFB7B2)
          : const ColorJsonConverter()
              .fromJson((json['blushColor'] as num).toInt()),
      lipColor: json['lipColor'] == null
          ? const Color(0xFFFF6B81)
          : const ColorJsonConverter()
              .fromJson((json['lipColor'] as num).toInt()),
      eyeShadowColor: json['eyeShadowColor'] == null
          ? const Color(0xFFE6B8A2)
          : const ColorJsonConverter()
              .fromJson((json['eyeShadowColor'] as num).toInt()),
      irisColor: json['irisColor'] == null
          ? const Color(0xFF6B4F3B)
          : const ColorJsonConverter()
              .fromJson((json['irisColor'] as num).toInt()),
      hairColor: json['hairColor'] == null
          ? const Color(0xFF3E2723)
          : const ColorJsonConverter()
              .fromJson((json['hairColor'] as num).toInt()),
    );

Map<String, dynamic> _$MakeupToJson(Makeup instance) => <String, dynamic>{
      'skinColor': const ColorJsonConverter().toJson(instance.skinColor),
      'blushColor': const ColorJsonConverter().toJson(instance.blushColor),
      'lipColor': const ColorJsonConverter().toJson(instance.lipColor),
      'eyeShadowColor':
          const ColorJsonConverter().toJson(instance.eyeShadowColor),
      'irisColor': const ColorJsonConverter().toJson(instance.irisColor),
      'hairColor': const ColorJsonConverter().toJson(instance.hairColor),
    };
