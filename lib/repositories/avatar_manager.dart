// 【对标来源：KouriChat-1.4.3.2 — src/avatar_manager.py 角色设定管理】
// 1:1 转译自 KouriChat avatar_manager 的 8 段式 Markdown 角色设定读写逻辑
// 参考文件：src/avatar_manager.py:load_avatar()、save_avatar()

import "dart:convert";
import "dart:io";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "../models/character_card_v2.dart";
import "database_service.dart";

/// 角色设定管理器（对标 KouriChat avatar_manager）
/// 完整保留 KouriChat 8 段式 Markdown 角色设定结构
/// 任务/角色/外表/经历/性格/经典台词/喜好/备注
class AvatarManager {
  static AvatarManager? _instance;
  static AvatarManager get instance => _instance ??= AvatarManager._();
  AvatarManager._();

  final DatabaseService _db = DatabaseService.instance;

  /// 8 段式角色设定结构（对标 KouriChat section_mapping）
  /// 英文 key -> 中文 Markdown 标题
  static const Map<String, String> sectionMapping = {
    'task': '任务',
    'role': '角色',
    'appearance': '外表',
    'experience': '经历',
    'personality': '性格',
    'classic_lines': '经典台词',
    'preferences': '喜好',
    'notes': '备注',
  };

  /// 中文标题 -> 英文 key（反向映射）
  static final Map<String, String> _reverseMapping =
      sectionMapping.map((k, v) => MapEntry(v, k));

  /// 加载角色设定（对标 KouriChat load_avatar）
  /// 返回 8 段式结构的 Map<String, String>
  Future<Map<String, String>> loadAvatar(String characterId) async {
    // 从数据库读取角色
    final db = await _db.database;
    final rows = await db.query(
      'characters',
      where: 'id = ?',
      whereArgs: [characterId],
      limit: 1,
    );

    if (rows.isEmpty) return {};

    final row = rows.first;

    // 将 CharacterCardV2 字段映射到 8 段式结构
    return {
      'task': _buildTaskSection(row),
      'role': _buildRoleSection(row),
      'appearance': row['description'] as String? ?? '',
      'experience': _buildExperienceSection(row),
      'personality': row['personality'] as String? ?? '',
      'classic_lines': _buildClassicLinesSection(row),
      'preferences': '',
      'notes': row['creatorNotes'] as String? ?? '',
    };
  }

  /// 从 Markdown 内容加载（对标 KouriChat load_avatar 解析逻辑）
  Map<String, String> loadAvatarFromMarkdown(String content) {
    final sections = <String, String>{};
    String? currentSection;
    final currentContent = <String>[];

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        // 找到新部分，保存之前的内容（对标 KouriChat 逐行解析）
        if (currentSection != null) {
          sections[currentSection] = currentContent.join('\n').trim();
          currentContent.clear();
        }

        // 获取新部分标题（对标 KouriChat section_mapping.get）
        final sectionTitle = trimmed.substring(2).trim();
        currentSection = _reverseMapping[sectionTitle];
      } else if (currentSection != null && trimmed.isNotEmpty) {
        currentContent.add(trimmed);
      }
    }

    // 保存最后一个部分（对标 KouriChat 最后一段处理）
    if (currentSection != null && currentContent.isNotEmpty) {
      sections[currentSection] = currentContent.join('\n').trim();
    }

    return sections;
  }

  /// 保存角色设定（对标 KouriChat save_avatar）
  /// 将 8 段式结构写回数据库
  Future<void> saveAvatar(
    String characterId,
    Map<String, String> sections,
  ) async {
    final db = await _db.database;

    // 将 8 段式结构映射回 CharacterCardV2 字段（对标 KouriChat 字段映射）
    await db.update(
      'characters',
      {
        'description': sections['appearance'] ?? '',
        'personality': sections['personality'] ?? '',
        'creatorNotes': sections['notes'] ?? '',
        'scenario': sections['task'] ?? '',
        'systemPrompt': _buildSystemPrompt(sections),
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [characterId],
    );
  }

  /// 保存 Markdown 格式（对标 KouriChat save_avatar Markdown 构建）
  String buildMarkdown(Map<String, String> sections) {
    final buffer = StringBuffer();
    for (final entry in sectionMapping.entries) {
      final content = sections[entry.key] ?? '';
      if (content.isNotEmpty) {
        buffer.writeln('# ${entry.value}');
        buffer.writeln(content);
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  /// 导出角色设定为 Markdown 文件
  Future<String> exportToMarkdown(
      String characterId, String characterName) async {
    final sections = await loadAvatar(characterId);
    final markdown = buildMarkdown(sections);

    final dir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(dir.path, 'avatars', characterName));
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }

    final file = File(p.join(avatarDir.path, 'avatar.md'));
    await file.writeAsString(markdown, encoding: utf8);
    return file.path;
  }

  /// 从 Markdown 文件导入角色设定
  Future<Map<String, String>> importFromMarkdown(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return {};

    final content = await file.readAsString(encoding: utf8);
    return loadAvatarFromMarkdown(content);
  }

  // ──────────── 私有辅助方法 ────────────

  /// 构建任务段落（对标 KouriChat scenario -> task）
  String _buildTaskSection(Map<String, dynamic> row) {
    final scenario = row['scenario'] as String? ?? '';
    final systemPrompt = row['systemPrompt'] as String? ?? '';
    if (scenario.isNotEmpty) return scenario;
    if (systemPrompt.isNotEmpty) return systemPrompt;
    return '';
  }

  /// 构建角色段落（对标 KouriChat name + creator -> role）
  String _buildRoleSection(Map<String, dynamic> row) {
    final name = row['name'] as String? ?? '';
    final creator = row['creator'] as String? ?? '';
    final parts = <String>[];
    if (name.isNotEmpty) parts.add('名称: $name');
    if (creator.isNotEmpty) parts.add('创建者: $creator');
    return parts.join('\n');
  }

  /// 构建经历段落（对标 KouriChat firstMes -> experience）
  String _buildExperienceSection(Map<String, dynamic> row) {
    return row['firstMes'] as String? ?? '';
  }

  /// 构建经典台词段落（对标 KouriChat mesExample -> classic_lines）
  String _buildClassicLinesSection(Map<String, dynamic> row) {
    return row['mesExample'] as String? ?? '';
  }

  /// 构建系统提示词（从 8 段式合成）
  String _buildSystemPrompt(Map<String, String> sections) {
    final parts = <String>[];
    if (sections['task']?.isNotEmpty == true) {
      parts.add('[任务]\n${sections['task']}');
    }
    if (sections['role']?.isNotEmpty == true) {
      parts.add('[角色]\n${sections['role']}');
    }
    if (sections['personality']?.isNotEmpty == true) {
      parts.add('[性格]\n${sections['personality']}');
    }
    if (sections['appearance']?.isNotEmpty == true) {
      parts.add('[外表]\n${sections['appearance']}');
    }
    if (sections['experience']?.isNotEmpty == true) {
      parts.add('[经历]\n${sections['experience']}');
    }
    if (sections['classic_lines']?.isNotEmpty == true) {
      parts.add('[经典台词]\n${sections['classic_lines']}');
    }
    if (sections['preferences']?.isNotEmpty == true) {
      parts.add('[喜好]\n${sections['preferences']}');
    }
    if (sections['notes']?.isNotEmpty == true) {
      parts.add('[备注]\n${sections['notes']}');
    }
    return parts.join('\n\n');
  }
}
