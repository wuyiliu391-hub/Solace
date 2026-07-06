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

  const ShopItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.emoji,
    this.description = '',
    this.tags = const [],
    this.isActive = true,
  });

  ShopItem copyWith({
    String? id,
    String? name,
    String? category,
    int? price,
    String? emoji,
    String? description,
    List<String>? tags,
    bool? isActive,
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
    };
  }

  factory ShopItem.fromMap(Map<String, dynamic> map) {
    return ShopItem(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      price: map['price'] as int,
      emoji: map['emoji'] as String,
      description: map['description'] as String? ?? '',
      tags: (map['tags'] as String? ?? '').split(',').where((t) => t.isNotEmpty).toList(),
      isActive: (map['isActive'] as int? ?? 1) == 1,
    );
  }

  @override
  List<Object?> get props => [id, name, category, price, emoji, description, tags, isActive];
}
