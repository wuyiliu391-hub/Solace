import 'dart:math';
import 'package:equatable/equatable.dart';

/// 虚拟位置模型（双人地图）
class VirtualLocation extends Equatable {
  final String id;
  final String characterId;
  final String userId;
  final double userLat;
  final double userLng;
  final double aiLat;
  final double aiLng;
  final String? sceneDescription;
  final double distance;
  final DateTime createdAt;

  const VirtualLocation({
    required this.id, required this.characterId, required this.userId,
    this.userLat = 0, this.userLng = 0, this.aiLat = 0, this.aiLng = 0,
    this.sceneDescription, this.distance = 0, required this.createdAt,
  });

  /// 计算两点间距离（km，Haversine公式）
  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * pi / 180;

  Map<String, dynamic> toMap() => {
    'id': id, 'characterId': characterId, 'userId': userId,
    'userLat': userLat, 'userLng': userLng, 'aiLat': aiLat, 'aiLng': aiLng,
    'sceneDescription': sceneDescription, 'distance': distance,
    'createdAt': createdAt.toIso8601String(),
  };

  factory VirtualLocation.fromMap(Map<String, dynamic> m) => VirtualLocation(
    id: m['id'] as String, characterId: m['characterId'] as String,
    userId: m['userId'] as String,
    userLat: (m['userLat'] as num?)?.toDouble() ?? 0,
    userLng: (m['userLng'] as num?)?.toDouble() ?? 0,
    aiLat: (m['aiLat'] as num?)?.toDouble() ?? 0,
    aiLng: (m['aiLng'] as num?)?.toDouble() ?? 0,
    sceneDescription: m['sceneDescription'] as String?,
    distance: (m['distance'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  List<Object?> get props => [id, characterId, distance];
}
