import 'package:equatable/equatable.dart';

/// 虚拟手机 · 联系人
///
/// 角色手机通讯录里的一个虚构联系人。用户本人也会作为一个 isUser=true 的联系人存在。
class VpContact extends Equatable {
  final String id;
  final String phoneId;
  final String characterId;

  final String name;

  /// 与角色的关系（如：母亲 / 大学室友 / 前同事 / 恋人）
  final String relation;

  /// 备注/印象（角色给这个人打的标签）
  final String note;

  /// 头像用的强调色（ARGB int）
  final int accentColor;

  /// 是否是「用户本人」在角色手机里的联系人条目
  final bool isUser;

  /// 是否置顶
  final bool pinned;

  final int orderIndex;

  const VpContact({
    required this.id,
    required this.phoneId,
    required this.characterId,
    required this.name,
    this.relation = '',
    this.note = '',
    this.accentColor = 0xFF007AFF,
    this.isUser = false,
    this.pinned = false,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'phoneId': phoneId,
        'characterId': characterId,
        'name': name,
        'relation': relation,
        'note': note,
        'accentColor': accentColor,
        'isUser': isUser ? 1 : 0,
        'pinned': pinned ? 1 : 0,
        'orderIndex': orderIndex,
      };

  factory VpContact.fromMap(Map<String, dynamic> map) => VpContact(
        id: map['id'] as String,
        phoneId: map['phoneId'] as String,
        characterId: map['characterId'] as String,
        name: map['name'] as String? ?? '',
        relation: map['relation'] as String? ?? '',
        note: map['note'] as String? ?? '',
        accentColor: (map['accentColor'] as int?) ?? 0xFF007AFF,
        isUser: (map['isUser'] == 1 || map['isUser'] == true),
        pinned: (map['pinned'] == 1 || map['pinned'] == true),
        orderIndex: (map['orderIndex'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, name, relation, isUser];
}
