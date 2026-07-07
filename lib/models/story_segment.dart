import 'dart:convert';

/// 段落角色
enum SegmentRole {
  user, // 玩家输入/选择的分支
  narration, // AI 生成的剧情正文
  system, // 系统提示（开场、章节分隔等）
}

extension SegmentRoleX on SegmentRole {
  String get name => switch (this) {
        SegmentRole.user => 'user',
        SegmentRole.narration => 'narration',
        SegmentRole.system => 'system',
      };

  static SegmentRole parse(String? v) => switch (v) {
        'user' => SegmentRole.user,
        'system' => SegmentRole.system,
        _ => SegmentRole.narration,
      };
}

/// 剧情段落 — 一本书的一条剧情记录（对标单聊的一条消息）
class StorySegment {
  final String id;
  final String storyId;
  final String saveId;
  final SegmentRole role;
  final String content; // 正文
  final int narratorRole; // 生成时的叙事视角（NarratorRole.index）
  final List<String> branchOptions; // AI 生成的候选分支
  final String? chosenBranch; // 玩家选中的分支文本
  final int orderIndex; // 剧情顺序
  final DateTime createdAt;
  final int syncSeq;

  const StorySegment({
    required this.id,
    required this.storyId,
    required this.saveId,
    this.role = SegmentRole.narration,
    this.content = '',
    this.narratorRole = 0,
    this.branchOptions = const [],
    this.chosenBranch,
    this.orderIndex = 0,
    required this.createdAt,
    this.syncSeq = 0,
  });

  StorySegment copyWith({
    String? id,
    String? storyId,
    String? saveId,
    SegmentRole? role,
    String? content,
    int? narratorRole,
    List<String>? branchOptions,
    String? chosenBranch,
    int? orderIndex,
    DateTime? createdAt,
    int? syncSeq,
  }) {
    return StorySegment(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      saveId: saveId ?? this.saveId,
      role: role ?? this.role,
      content: content ?? this.content,
      narratorRole: narratorRole ?? this.narratorRole,
      branchOptions: branchOptions ?? this.branchOptions,
      chosenBranch: chosenBranch ?? this.chosenBranch,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  bool get isUser => role == SegmentRole.user;
  bool get isNarration => role == SegmentRole.narration;

  Map<String, dynamic> toMap() => {
        'id': id,
        'storyId': storyId,
        'saveId': saveId,
        'role': role.name,
        'content': content,
        'narratorRole': narratorRole,
        'branchOptions': jsonEncode(branchOptions),
        'chosenBranch': chosenBranch,
        'orderIndex': orderIndex,
        'createdAt': createdAt.toIso8601String(),
        'sync_seq': syncSeq,
      };

  factory StorySegment.fromMap(Map<String, dynamic> map) {
    List<String> options = [];
    final raw = map['branchOptions'];
    if (raw is String && raw.isNotEmpty) {
      try {
        options =
            (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return StorySegment(
      id: map['id'] as String,
      storyId: map['storyId'] as String? ?? '',
      saveId: map['saveId'] as String? ?? '',
      role: SegmentRoleX.parse(map['role'] as String?),
      content: map['content'] as String? ?? '',
      narratorRole: (map['narratorRole'] as num?)?.toInt() ?? 0,
      branchOptions: options,
      chosenBranch: map['chosenBranch'] as String?,
      orderIndex: (map['orderIndex'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }
}
