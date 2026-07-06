class ImageDescription {
  final String? sceneLabel;
  final List<String> objects;
  final String dominantColors;
  final String lighting;
  final String composition;
  final String? extractedText;
  final String? faceInfo;
  final String atmosphere;
  final bool hasPeople;
  final String sceneType;
  final String objectComplexity;
  final String contrast;
  final String texture;
  final String mood;

  const ImageDescription({
    this.sceneLabel,
    this.objects = const [],
    this.dominantColors = '未知',
    this.lighting = '正常',
    this.composition = '未知',
    this.extractedText,
    this.faceInfo,
    this.atmosphere = '普通',
    this.hasPeople = false,
    this.sceneType = '未知',
    this.objectComplexity = '未知',
    this.contrast = '对比度适中',
    this.texture = '未知',
    this.mood = '普通',
  });

  String toDescription() {
    final parts = <String>[];

    if (objects.isNotEmpty) {
      final objStr = objects.join('、');
      parts.add('这张照片里有$objStr');
    } else if ((sceneLabel?.isNotEmpty) == true) {
      parts.add('这张照片里有$sceneLabel');
    } else if (sceneType != '未知' && sceneType != '日常场景') {
      parts.add('这是一张$sceneType照片');
    } else {
      parts.add('这是一张照片');
    }

    if (hasPeople) {
      parts.add('画面中有人物');
    }

    if (dominantColors != '未知') {
      parts.add('主色调为$dominantColors');
    }

    parts.add('光线$lighting');

    if (composition != '未知') {
      parts.add('${composition}构图');
    }

    if (contrast != '对比度适中') {
      parts.add(contrast);
    }

    if (texture != '未知') {
      parts.add('质感$texture');
    }

    if (objectComplexity != '未知') {
      parts.add('画面$objectComplexity');
    }

    if ((extractedText?.isNotEmpty) == true) {
      parts.add('图片中包含文字："$extractedText"');
    }

    if ((faceInfo?.isNotEmpty) == true) {
      parts.add('人脸信息：$faceInfo');
    }

    return parts.join('，');
  }

  String toCompactDescription() {
    final parts = <String>[];
    if (objects.isNotEmpty) {
      parts.add(objects.join('、'));
    } else if ((sceneLabel?.isNotEmpty) == true) {
      parts.add(sceneLabel ?? '');
    } else if (sceneType != '未知') {
      parts.add(sceneType);
    }
    if (hasPeople) {
      parts.add('有人物');
    }
    if (dominantColors != '未知') {
      parts.add('$dominantColors色调');
    }
    if (mood != '普通') {
      parts.add(mood);
    }
    return parts.join('，');
  }
}