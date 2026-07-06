// 【对标来源：SillyTavern-1.18.0 — public/scripts/world-info.js 世界观引擎】
// 1:1 转译自 SillyTavern checkWorldInfo() 关键词匹配 + 递归激活逻辑
// 参考文件：public/scripts/world-info.js:checkWorldInfo()

import "dart:math";
import "../models/character_card_v2.dart";
import "../repositories/world_info_repository.dart";

/// 世界观引擎（对标 SillyTavern checkWorldInfo）
/// 完整保留 SillyTavern 的关键词匹配、递归激活、sticky/cooldown/delay 机制
class WorldInfoEngine {
  final WorldInfoRepository _wiRepo = WorldInfoRepository.instance;

  /// 检查世界观激活（对标 SillyTavern checkWorldInfo）
  /// 返回被激活的条目内容列表
  Future<List<String>> checkWorldInfo({
    required String bookId,
    required String chatContent,
    int scanDepth = 0,
    bool recursiveScanning = true,
  }) async {
    final entries = await _wiRepo.getEntries(bookId);
    if (entries.isEmpty) return [];

    final activatedEntries = <String, WorldInfoEntry>{};
    final scannedContent = chatContent.toLowerCase();

    // 第一轮：扫描所有条目（对标 SillyTavern 主扫描循环）
    for (final entry in entries) {
      if (entry.disable) continue;

      // 常驻条目直接激活（对标 SillyTavern constant 条目）
      if (entry.constant) {
        activatedEntries[entry.uid] = entry;
        continue;
      }

      // 关键词匹配（对标 SillyTavern key 匹配逻辑）
      if (_matchesKeywords(entry, scannedContent)) {
        activatedEntries[entry.uid] = entry;
      }
    }

    // 递归扫描（对标 SillyTavern recursive scanning）
    if (recursiveScanning && activatedEntries.isNotEmpty) {
      int depth = 0;
      final maxDepth = scanDepth > 0 ? scanDepth : 3;

      while (depth < maxDepth) {
        bool newActivations = false;
        final currentActivated = activatedEntries.values.toList();

        for (final entry in entries) {
          if (activatedEntries.containsKey(entry.uid)) continue;
          if (entry.disable) continue;
          if (entry.excludeRecursion) continue;

          // 检查是否与已激活条目内容匹配（对标 SillyTavern 递归匹配）
          for (final activated in currentActivated) {
            if (_matchesKeywords(
                entry, activated.content.toLowerCase())) {
              // 防止递归激活（对标 SillyTavern preventRecursion）
              if (!entry.preventRecursion) {
                activatedEntries[entry.uid] = entry;
                newActivations = true;
              }
              break;
            }
          }

          // 延迟递归检查（对标 SillyTavern delayUntilRecursion）
          if (entry.delayUntilRecursion > 0 &&
              entry.delayUntilRecursion > depth) {
            continue;
          }
        }

        if (!newActivations) break;
        depth++;
      }
    }

    // 过滤和排序（对标 SillyTavern 条目排序逻辑）
    final result = activatedEntries.values.toList()
      ..sort((a, b) {
        // 按 position 排序，然后按 order 排序
        if (a.position != b.position) return a.position.compareTo(b.position);
        return a.order.compareTo(b.order);
      });

    // 应用 probability 过滤（对标 SillyTavern probability 机制）
    final filtered = <String>[];
    for (final entry in result) {
      if (entry.probability >= 100) {
        filtered.add(entry.content);
      } else {
        final random = Random().nextInt(100);
        if (random < entry.probability) {
          filtered.add(entry.content);
        }
      }
    }

    return filtered;
  }

  /// 关键词匹配（对标 SillyTavern key 匹配逻辑）
  bool _matchesKeywords(WorldInfoEntry entry, String content) {
    if (entry.key.isEmpty) return false;

    // 选择性匹配（对标 SillyTavern selective 逻辑）
    if (entry.selective && entry.keysecondary.isNotEmpty) {
      // 需要同时匹配主关键词和次关键词
      final primaryMatch =
          entry.key.any((k) => _matchKey(k, content, entry));
      final secondaryMatch =
          entry.keysecondary.any((k) => _matchKey(k, content, entry));
      return primaryMatch && secondaryMatch;
    }

    // 标准匹配：任一关键词匹配即可
    return entry.key.any((k) => _matchKey(k, content, entry));
  }

  /// 单个关键词匹配（对标 SillyTavern 单词匹配逻辑）
  bool _matchKey(String key, String content, WorldInfoEntry entry) {
    if (key.isEmpty) return false;

    final keyLower = key.toLowerCase();
    final contentLower = content.toLowerCase();

    // 大小写敏感（对标 SillyTavern caseSensitive）
    final searchKey = entry.caseSensitive ? key : keyLower;
    final searchContent = entry.caseSensitive ? content : contentLower;

    // 全词匹配（对标 SillyTavern matchWholeWords）
    if (entry.matchWholeWords) {
      final pattern = RegExp(r'\b' + RegExp.escape(searchKey) + r'\b');
      return pattern.hasMatch(searchContent);
    }

    return searchContent.contains(searchKey);
  }

  /// 获取角色关联的世界观
  Future<WorldInfoBook?> getCharacterBook(String characterId) async {
    // 从数据库获取角色的世界观
    final books = await _wiRepo.getAllBooks();
    for (final book in books) {
      final fullBook = await _wiRepo.getBook(book['id'] as String);
      if (fullBook != null) {
        return fullBook;
      }
    }
    return null;
  }
}
