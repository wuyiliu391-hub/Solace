const fs = require('fs');
const path = 'lib/repositories/local_storage_repository.dart';

// 读取已有的 Part 1 + Part 2
let content = fs.readFileSync(path, 'utf8');

// 追加剩余的所有内容
content += `
  static Future<void> reconcileSchema(Database db) async {
    for (final entry in expectedColumns.entries) {
      final table = entry.key;
      final expectedCols = entry.value;
      try {
        final existingRows = await db.rawQuery('PRAGMA table_info(\$table)');
        if (existingRows.isEmpty) {
          debugPrint('自动修复: \$table 表不存在，尝试创建..');
          await createMissingTable(db, table);
          continue;
        }
        final existingCols = existingRows.map((r) => r['name'] as String).toSet();
        for (final colEntry in expectedCols.entries) {
          final colName = colEntry.key;
          final colDef = colEntry.value;
          if (!existingCols.contains(colName)) {
            debugPrint('自动修复: 给\$table 表添加缺失的 \$colName 列(\$colDef)');
            await db.execute('ALTER TABLE \$table ADD COLUMN \$colName \$colDef');
          }
        }
      } catch (e) {
        debugPrint('校验 \$table 表结构失败: \$e');
      }
    }
  }
`;

fs.writeFileSync(path, content, 'utf8');
console.log('Part 3 (reconcileSchema) appended');
