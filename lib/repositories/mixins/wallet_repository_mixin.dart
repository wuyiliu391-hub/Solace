//  本文件预留用于 Repository 域拆分。
// Dart 3 中 `mixin on ClassName` + `class ClassName with Mixin` 在同一库中会产生
// recursive_interface_inheritance 错误。
//
// 后续拆分方案：使用 Delegate 模式而非 Mixin。
// wallet_repository_delegate.dart 将作为独立类接收 LocalStorageRepository 实例并委托。
//
// 见 lib/repositories/ 目录下的后续实现。
