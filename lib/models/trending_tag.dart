import 'package:equatable/equatable.dart';

class TrendingTag extends Equatable {
  final String tag;
  final int count;
  final DateTime lastUsedAt;

  const TrendingTag({
    required this.tag,
    required this.count,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tag': tag,
      'count': count,
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  factory TrendingTag.fromMap(Map<String, dynamic> map) {
    return TrendingTag(
      tag: map['tag'] as String,
      count: (map['count'] as int?) ?? 1,
      lastUsedAt: DateTime.parse(map['lastUsedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [tag, count];
}
