import 'package:equatable/equatable.dart';

/// 用户自定义人设（一人扮演多角色）
class UserPersona extends Equatable {
  final String id;
  final String name;
  final String? avatarPath;
  final String handle; // @handle
  final String? gender;
  final String? bio;
  final bool isDefault; // 是否为默认身份
  final DateTime createdAt;

  const UserPersona({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.handle,
    this.gender,
    this.bio,
    this.isDefault = false,
    required this.createdAt,
  });

  UserPersona copyWith({
    String? id,
    String? name,
    String? avatarPath,
    String? handle,
    String? gender,
    String? bio,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return UserPersona(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarPath: avatarPath ?? this.avatarPath,
      handle: handle ?? this.handle,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatarPath': avatarPath,
      'handle': handle,
      'gender': gender,
      'bio': bio,
      'isDefault': isDefault ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserPersona.fromMap(Map<String, dynamic> map) {
    return UserPersona(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarPath: map['avatarPath'] as String?,
      handle: map['handle'] as String,
      gender: map['gender'] as String?,
      bio: map['bio'] as String?,
      isDefault: map['isDefault'] == 1 || map['isDefault'] == true,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, name, handle, gender, isDefault];
}
