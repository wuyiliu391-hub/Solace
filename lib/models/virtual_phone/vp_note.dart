import 'package:equatable/equatable.dart';

/// 虚拟手机 · 备忘录/日记
///
/// 角色写给自己的私密心事。这里最能体现「TA 私下里怎么看待用户」。
class VpNote extends Equatable {
  final String id;
  final String phoneId;
  final String characterId;

  final String title;
  final String body;

  /// 虚构的日期文本（如 "3月12日"），只做展示
  final String dateLabel;

  /// 是否与用户相关（用于 UI 上做一点小标记）
  final bool aboutUser;

  final int orderIndex;

  const VpNote({
    required this.id,
    required this.phoneId,
    required this.characterId,
    this.title = '',
    this.body = '',
    this.dateLabel = '',
    this.aboutUser = false,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'phoneId': phoneId,
        'characterId': characterId,
        'title': title,
        'body': body,
        'dateLabel': dateLabel,
        'aboutUser': aboutUser ? 1 : 0,
        'orderIndex': orderIndex,
      };

  factory VpNote.fromMap(Map<String, dynamic> map) => VpNote(
        id: map['id'] as String,
        phoneId: map['phoneId'] as String,
        characterId: map['characterId'] as String,
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        dateLabel: map['dateLabel'] as String? ?? '',
        aboutUser: (map['aboutUser'] == 1 || map['aboutUser'] == true),
        orderIndex: (map['orderIndex'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, title, body, aboutUser];
}
