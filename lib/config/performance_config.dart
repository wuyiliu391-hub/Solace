// 性能优化 -- 耗电与老手机兼容
// 全局性能配置：所有可调参数集中管理，方便针对不同设备调整

class PerformanceConfig {
  PerformanceConfig._();

  // ─── 心跳与定时器 ───
  /// 心跳间隔（秒）— 原值过短会频繁唤醒 CPU
  static const int heartbeatIntervalSeconds = 120;

  /// UI 自动刷新间隔（秒）
  static const int uiRefreshIntervalSeconds = 30;

  /// 数据库缓存过期时间（秒）
  static const int dbCacheExpirySeconds = 30;

  // ─── 动画与视觉效果 ───
  /// 是否启用动画（老手机可以关闭以节省 GPU）
  static bool enableAnimations = true;

  /// 是否启用复杂视觉效果（模糊、阴影等）
  static bool enableComplexEffects = true;

  // ─── 并发控制 ───
  /// 最大同时运行的 Timer 数量（防止后台 Timer 堆积）
  static const int maxConcurrentTimers = 3;

  // ─── 缓存上限 ───
  /// 消息列表最大缓存数量（减少内存占用）
  static const int maxCachedMessages = 100;

  /// 社交记忆最大加载数量
  static const int maxSocialMemories = 50;

  /// 朋友圈动态最大加载数量
  static const int maxMoments = 50;

  // ─── 启动优化 ───
  /// 非关键服务延迟初始化的等待时间（秒）
  static const int deferredInitDelaySeconds = 5;

  // ─── 图片优化 ───
  /// 图片加载最大宽高（像素），超过则缩放
  static const int imageMaxDimension = 1200;

  /// 图片 JPEG 压缩质量（0-100）
  static const int imageJpegQuality = 75;
}
