import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 缓存助手
/// 避免每次调用 SharedPreferences.getInstance() 都走异步查找
class PrefsHelper {
  static SharedPreferences? _cached;

  /// 获取缓存的 SharedPreferences 实例
  /// 首次调用会异步初始化，后续调用直接返回缓存
  static Future<SharedPreferences> get instance async {
    _cached ??= await SharedPreferences.getInstance();
    return _cached!;
  }

  /// 同步获取已缓存的实例（必须先调用过 instance）
  static SharedPreferences? get cached => _cached;

  /// 预热缓存（在 app 启动时调用）
  static Future<void> warmUp() async {
    _cached ??= await SharedPreferences.getInstance();
  }

  /// 清除缓存（测试用）
  static void reset() {
    _cached = null;
  }
}
