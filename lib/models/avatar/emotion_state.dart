import 'avatar_config.dart';

/// 崽崽情绪枚举（7 种）
///
/// 每种情绪对应一组 eyes/eyebrows/mouth 变体组合，
/// 渲染时通过 [EmotionState.applyTo] 叠加到基础 [AvatarConfig] 上。
enum Emotion {
  happy,
  sad,
  angry,
  surprised,
  shy,
  playful,
  calm,
}

/// 单种情绪对应的面部变体组合
class _EmotionVariants {
  final String eyes;
  final String eyebrow;
  final String mouth;

  const _EmotionVariants({
    required this.eyes,
    required this.eyebrow,
    required this.mouth,
  });
}

/// 情绪 → 面部变体映射表
///
/// 对应关系：
/// - happy:     eyes=doe,     eyebrows=curved, mouths=smile
/// - sad:       eyes=sleepy,  eyebrows=flat,   mouths=frown
/// - angry:     eyes=slim,    eyebrows=flat,   mouths=frown
/// - surprised: eyes=round,   eyebrows=thick,  mouths=open
/// - shy:       eyes=default, eyebrows=curved, mouths=pout
/// - playful:   eyes=doe,     eyebrows=curved, mouths=pout
/// - calm:      eyes=default, eyebrows=default, mouths=default（不覆盖基础配置）
const Map<Emotion, _EmotionVariants> _emotionVariants = {
  Emotion.happy: _EmotionVariants(eyes: 'doe', eyebrow: 'curved', mouth: 'smile'),
  Emotion.sad: _EmotionVariants(eyes: 'sleepy', eyebrow: 'flat', mouth: 'frown'),
  Emotion.angry: _EmotionVariants(eyes: 'slim', eyebrow: 'flat', mouth: 'frown'),
  Emotion.surprised:
      _EmotionVariants(eyes: 'round', eyebrow: 'thick', mouth: 'open'),
  Emotion.shy:
      _EmotionVariants(eyes: 'default', eyebrow: 'curved', mouth: 'pout'),
  Emotion.playful:
      _EmotionVariants(eyes: 'doe', eyebrow: 'curved', mouth: 'pout'),
  Emotion.calm:
      _EmotionVariants(eyes: 'default', eyebrow: 'default', mouth: 'default'),
};

/// 情绪状态管理器
///
/// 跟踪当前情绪 + 持续时间，到期后自动衰减回 [Emotion.calm]。
///
/// 使用方式：
/// ```dart
/// final state = EmotionState();
/// state.trigger(Emotion.happy, Duration(seconds: 3));
/// // ... 在每帧调用 update() 检查是否过期 ...
/// final effectiveConfig = state.applyTo(baseConfig);
/// ```
class EmotionState {
  Emotion _current = Emotion.calm;
  DateTime? _expiresAt;

  /// 当前情绪
  Emotion get current => _current;

  /// 是否有活跃情绪（非 calm）
  bool get isActive => _current != Emotion.calm;

  /// 剩余持续时间（calm 或已过期返回 Duration.zero）
  Duration get remaining {
    if (_expiresAt == null) return Duration.zero;
    final left = _expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  EmotionState();

  /// 触发一种情绪，持续 [duration] 后自动衰减回 calm。
  /// 若 [emotion] 为 calm 或 [duration] 为 Duration.zero，立即回到 calm。
  void trigger(Emotion emotion, Duration duration) {
    _current = emotion;
    if (emotion == Emotion.calm || duration == Duration.zero) {
      _expiresAt = null;
      _current = Emotion.calm;
    } else {
      _expiresAt = DateTime.now().add(duration);
    }
  }

  /// 每帧调用，检查情绪是否过期并自动衰减回 calm。
  void update() {
    if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
      _current = Emotion.calm;
      _expiresAt = null;
    }
  }

  /// 立即重置为 calm。
  void reset() {
    _current = Emotion.calm;
    _expiresAt = null;
  }

  /// 把当前情绪的面部变体叠加到 [base] 配置上，返回新配置。
  ///
  /// 当情绪为 calm 时不覆盖任何变体（返回原配置）。
  /// 这样眨眼、待机等系统可以在情绪之上继续叠加。
  AvatarConfig applyTo(AvatarConfig base) {
    if (_current == Emotion.calm) return base;
    final v = _emotionVariants[_current]!;
    return base.copyWith(
      eyesVariant: v.eyes,
      eyebrowVariant: v.eyebrow,
      mouthVariant: v.mouth,
    );
  }
}

/// 顶层映射函数：把 [EmotionState] 转成 [AvatarConfig]。
///
/// 返回基于 [AvatarConfig.defaultConfig] 的配置，只设置情绪对应的面部变体。
/// 若需要叠加到已有配置，请使用 [EmotionState.applyTo]。
AvatarConfig emotionToConfig(EmotionState state) {
  if (state.current == Emotion.calm) return AvatarConfig.defaultConfig;
  final v = _emotionVariants[state.current]!;
  return AvatarConfig.defaultConfig.copyWith(
    eyesVariant: v.eyes,
    eyebrowVariant: v.eyebrow,
    mouthVariant: v.mouth,
  );
}
