// 库级共享常量（原类内 static 值字段，拆分提升为顶层，全库可见）
part of '../chat_detail_screen.dart';

const int _searchPageSize = 30;

/// 番外文本指令检测（兼容 mufy 格式指令，如 `$现在暂停当前剧情，生成番外小剧场`）。
final RegExp _sideStoryOpenPrefix = RegExp(
  r'^(生成|开启|进入|来一段|来段|写一段|新建)',
  caseSensitive: false,
);
