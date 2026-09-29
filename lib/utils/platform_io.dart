/// 条件导出：Web 端用 stub，原生端用真实 dart:io
export 'platform_io_stub.dart' if (dart.library.io) 'platform_io_native.dart';