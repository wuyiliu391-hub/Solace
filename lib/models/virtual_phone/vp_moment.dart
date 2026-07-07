import 'package:equatable/equatable.dart';

/// 虚拟手机 · 社交动态（角色的朋友圈/生活片段，文字为主）
class VpMoment extends Equatable {
  final String id;
  final String phoneId;
  final String characterId;

  /// 正文
  final String content;

  /// 虚构的发布时间文本（如 "2小时前"），只做展示
  final String timeLabel;

  /// 虚构的点赞数（纯展示）
  final int likes;

  /// 虚构的评论（"某人：内容" 的简单列表，用 \n 分隔）
  final String comments;

  final int orderIndex;

  const VpMoment({
    required this.id,
    required this.phoneId,
    required this.characterId,
    this.content = '',
    this.timeLabel = '',
    this.likes = 0,
    this.comments = '',
    this.orderIndex = 0,
  });

  List<String> get commentList =>
      comments.split('\n').where((e) => e.trim().isNotEmpty).toList();

  Map<String, dynamic> toMap() => {
        'id': id,
        'phoneId': phoneId,
        'characterId': characterId,
        'content': content,
        'timeLabel': timeLabel,
        'likes': likes,
        'comments': comments,
        'orderIndex': orderIndex,
      };

  factory VpMoment.fromMap(Map<String, dynamic> map) => VpMoment(
        id: map['id'] as String,
        phoneId: map['phoneId'] as String,
        characterId: map['characterId'] as String,
        content: map['content'] as String? ?? '',
        timeLabel: map['timeLabel'] as String? ?? '',
        likes: (map['likes'] as int?) ?? 0,
        comments: map['comments'] as String? ?? '',
        orderIndex: (map['orderIndex'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, content, timeLabel, likes];
}
