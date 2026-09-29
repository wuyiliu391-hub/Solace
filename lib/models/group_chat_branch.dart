import 'package:equatable/equatable.dart';

/// 群聊聊天记录（分支）— 对标 SillyTavern group.chats[chatId]
class GroupChatBranch extends Equatable {
  final String branchId;
  final String groupId;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? parentBranchId;
  final String? forkMessageId;
  final String? checkpointMessageId;

  const GroupChatBranch({
    required this.branchId,
    required this.groupId,
    this.name = '默认聊天',
    required this.createdAt,
    this.updatedAt,
    this.parentBranchId,
    this.forkMessageId,
    this.checkpointMessageId,
  });

  GroupChatBranch copyWith({
    String? branchId,
    String? groupId,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? parentBranchId,
    String? forkMessageId,
    String? checkpointMessageId,
  }) {
    return GroupChatBranch(
      branchId: branchId ?? this.branchId,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentBranchId: parentBranchId ?? this.parentBranchId,
      forkMessageId: forkMessageId ?? this.forkMessageId,
      checkpointMessageId: checkpointMessageId ?? this.checkpointMessageId,
    );
  }

  Map<String, dynamic> toMap() => {
        'branchId': branchId,
        'groupId': groupId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'parentBranchId': parentBranchId,
        'forkMessageId': forkMessageId,
        'checkpointMessageId': checkpointMessageId,
      };

  factory GroupChatBranch.fromMap(Map<String, dynamic> map) {
    final ca = map['createdAt'];
    final ua = map['updatedAt'];
    return GroupChatBranch(
      branchId: map['branchId'] as String,
      groupId: (map['groupId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '默认聊天',
      createdAt: ca is String
          ? (DateTime.tryParse(ca) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: ua is String ? DateTime.tryParse(ua) : null,
      parentBranchId: map['parentBranchId']?.toString(),
      forkMessageId: map['forkMessageId']?.toString(),
      checkpointMessageId: map['checkpointMessageId']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        branchId,
        groupId,
        name,
        createdAt,
        updatedAt,
        parentBranchId,
        forkMessageId,
        checkpointMessageId
      ];
}
