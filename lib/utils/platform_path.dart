/// 条件导出：Web 端用 stub，原生端用真实 path_provider
export 'platform_path_stub.dart' if (dart.library.io) 'platform_path_native.dart';