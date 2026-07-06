#!/usr/bin/env python3
"""Update local_storage_repository.dart with character image gallery support."""
import re

repo = r'C:\Users\Administrator\Desktop\solace\lib\repositories\local_storage_repository.dart'
with open(repo, 'r', encoding='utf-8-sig') as f:
    content = f.read()

# 1. Add expectedColumns entry for character_image_gallery
old1 = "'createdAt': 'TEXT NOT NULL DEFAULT \"\"',\n    },\n  };\n\n  /// \u4fee\u590d isUser \u5b57\u6bb5"
new1 = "'createdAt': 'TEXT NOT NULL DEFAULT \"\"',\n    },\n    'character_image_gallery': {\n      'characterId': 'TEXT NOT NULL DEFAULT \"\"',\n      'userId': 'TEXT NOT NULL DEFAULT \"\"',\n      'localPath': 'TEXT NOT NULL DEFAULT \"\"',\n      'promptUsed': 'TEXT',\n      'sceneDescription': 'TEXT',\n      'referenceImagePath': 'TEXT',\n      'generationSeed': 'INTEGER NOT NULL DEFAULT -1',\n      'resolution': 'TEXT NOT NULL DEFAULT \"1024x1792\"',\n      'styleLock': 'TEXT NOT NULL DEFAULT \"anime\"',\n      'createdAt': 'TEXT NOT NULL DEFAULT \"\"',\n      'isFavorite': 'INTEGER NOT NULL DEFAULT 0',\n    },\n  };\n\n  /// \u4fee\u590d isUser \u5b57\u6bb5"
if old1 in content:
    content = content.replace(old1, new1)
    print("Step 1: expectedColumns updated")
else:
    print("Step 1 FAILED - pattern not found")

# 2. Add CREATE TABLE for character_image_gallery in _onCreate
old2 = "''' CREATE INDEX idx_moments_userId ON moments(userId) ''');"
new2 = "''' CREATE INDEX idx_moments_userId ON moments(userId) ''');\n    await db.execute(\n        ''' CREATE TABLE IF NOT EXISTS character_image_gallery ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL, userId TEXT NOT NULL, localPath TEXT NOT NULL, promptUsed TEXT, sceneDescription TEXT, referenceImagePath TEXT, generationSeed INTEGER NOT NULL DEFAULT -1, resolution TEXT NOT NULL DEFAULT '1024x1792', styleLock TEXT NOT NULL DEFAULT 'anime', createdAt TEXT NOT NULL, isFavorite INTEGER NOT NULL DEFAULT 0 ) ''');\n    await db.execute(''' CREATE INDEX IF NOT EXISTS idx_gallery_characterId ON character_image_gallery(characterId) ''');"
if old2 in content:
    content = content.replace(old2, new2)
    print("Step 2: _onCreate gallery table added")
else:
    print("Step 2 FAILED")

# 3. Add v40 migration
old3 = "db, 'ai_characters', 'styleLock', 'TEXT NOT NULL DEFAULT \"anime\"');\n    }\n  }\n\n  Future<void> _onCreate"
new3 = "db, 'ai_characters', 'styleLock', 'TEXT NOT NULL DEFAULT \"anime\"');\n    }\n    if (oldVersion < 40) {\n      await db.execute(\n        ''' CREATE TABLE IF NOT EXISTS character_image_gallery ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL, userId TEXT NOT NULL, localPath TEXT NOT NULL, promptUsed TEXT, sceneDescription TEXT, referenceImagePath TEXT, generationSeed INTEGER NOT NULL DEFAULT -1, resolution TEXT NOT NULL DEFAULT '1024x1792', styleLock TEXT NOT NULL DEFAULT 'anime', createdAt TEXT NOT NULL, isFavorite INTEGER NOT NULL DEFAULT 0 ) ''');\n      await db.execute(''' CREATE INDEX IF NOT EXISTS idx_gallery_characterId ON character_image_gallery(characterId) ''');\n    }\n  }\n\n  Future<void> _onCreate"
if old3 in content:
    content = content.replace(old3, new3)
    print("Step 3: v40 migration added")
else:
    print("Step 3 FAILED")

# 4. Update dbVersion
content = content.replace('static const int dbVersion = 39;', 'static const int dbVersion = 40;')
print("Step 4: dbVersion updated to 40")

# 5. Add image gallery methods
insert_method = '''
  /// \u89d2\u8272\u56fe\u7247\u753b\u5eca\u64cd\u4f5c

  Future<void> insertCharacterImage(Map<String, dynamic> image) async {
    final db = await _ensureDb();
    await db.insert('character_image_gallery', image,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCharacterImages(String characterId, {int limit = 50}) async {
    final db = await _ensureDb();
    return await db.query(
      'character_image_gallery',
      where: 'characterId = ?',
      whereArgs: [characterId],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLatestCharacterImage(String characterId) async {
    final db = await _ensureDb();
    final results = await db.query(
      'character_image_gallery',
      where: 'characterId = ?',
      whereArgs: [characterId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> toggleImageFavorite(String imageId, bool isFavorite) async {
    final db = await _ensureDb();
    await db.update(
      'character_image_gallery',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }
'''

idx = content.rfind('btClearDiary')
if idx > 0:
    end_idx = content.find('\n  }\n', idx)
    if end_idx > 0:
        insert_pos = end_idx + 5
        content = content[:insert_pos] + insert_method + content[insert_pos:]
        print(f"Step 5: gallery methods inserted at {insert_pos}")
    else:
        print("Step 5 FAILED - end of method not found")
else:
    print("Step 5 FAILED - btClearDiary not found")

with open(repo, 'w', encoding='utf-8') as f:
    f.write(content)
print("All done!")