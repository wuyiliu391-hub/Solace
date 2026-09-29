import 'package:equatable/equatable.dart';

class ShopItem extends Equatable {
  final String id;
  final String name;
  final String category; // 'gift', 'food', 'express'
  final int price;
  final String emoji;
  final String description;
  final List<String> tags;
  final bool isActive;
  /// 用户自定义商品；系统种子为 false
  final bool isCustom;
  final DateTime? createdAt;

  const ShopItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.emoji,
    this.description = '',
    this.tags = const [],
    this.isActive = true,
    this.isCustom = false,
    this.createdAt,
  });

  /// 给 AI 看的自然语言说明（送礼上下文用）
  String get aiReadableLabel {
    final cat = switch (category) {
      'food' => '外卖/食物',
      'express' => '快递/物件',
      _ => '礼物',
    };
    final desc = description.trim();
    if (desc.isEmpty) {
      return '$emoji $name（$cat，价值 $price 金币）';
    }
    return '$emoji $name（$cat，价值 $price 金币）：$desc';
  }

  ShopItem copyWith({
    String? id,
    String? name,
    String? category,
    int? price,
    String? emoji,
    String? description,
    List<String>? tags,
    bool? isActive,
    bool? isCustom,
    DateTime? createdAt,
  }) {
    return ShopItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      emoji: emoji ?? this.emoji,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      isActive: isActive ?? this.isActive,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'emoji': emoji,
      'description': description,
      'tags': tags.join(','),
      'isActive': isActive ? 1 : 0,
      'isCustom': isCustom ? 1 : 0,
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  /// 仅写入 [columns] 中真实存在的字段，彻底避免 no such column。
  Map<String, dynamic> toDbMap(Set<String> columns) {
    final full = toMap();
    if (columns.isEmpty) {
      // 极端兜底：只写最老 schema 的基础列
      return {
        'id': full['id'],
        'name': full['name'],
        'category': full['category'],
        'price': full['price'],
        'emoji': full['emoji'],
        'description': full['description'],
        'tags': full['tags'],
        'isActive': full['isActive'],
      };
    }
    return Map<String, dynamic>.fromEntries(
      full.entries.where((e) => columns.contains(e.key)),
    );
  }

  factory ShopItem.fromMap(Map<String, dynamic> map) {
    DateTime? created;
    final rawCreated = map['createdAt'];
    if (rawCreated is String && rawCreated.isNotEmpty) {
      created = DateTime.tryParse(rawCreated);
    }
    return ShopItem(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'gift',
      price: (map['price'] as num?)?.toInt() ?? 0,
      emoji: map['emoji'] as String? ?? '🎁',
      description: map['description'] as String? ?? '',
      tags: (map['tags'] as String? ?? '')
          .split(',')
          .where((t) => t.isNotEmpty)
          .toList(),
      isActive: (map['isActive'] as int? ?? 1) == 1,
      isCustom: (map['isCustom'] as int? ?? 0) == 1,
      createdAt: created,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, category, price, emoji, description, tags, isActive, isCustom];
}
