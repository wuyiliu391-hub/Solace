class LocationRecord {
  final String id;
  final String ownerId;
  final double latitude;
  final double longitude;
  final String? address;
  final String? placeName;
  final String? placeType;
  final DateTime timestamp;
  final bool isUser;
  final String? trajectoryId;
  final int? sequenceIndex;
  final String? emotion;
  final String? activity;

  const LocationRecord({
    required this.id,
    required this.ownerId,
    required this.latitude,
    required this.longitude,
    this.address,
    this.placeName,
    this.placeType,
    required this.timestamp,
    required this.isUser,
    this.trajectoryId,
    this.sequenceIndex,
    this.emotion,
    this.activity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'placeName': placeName,
      'placeType': placeType,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isUser': isUser ? 1 : 0,
      'trajectoryId': trajectoryId,
      'sequenceIndex': sequenceIndex,
      'emotion': emotion,
      'activity': activity,
    };
  }

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] as String,
      ownerId: map['ownerId'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      address: map['address'] as String?,
      placeName: map['placeName'] as String?,
      placeType: map['placeType'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isUser: (map['isUser'] as int) == 1,
      trajectoryId: map['trajectoryId'] as String?,
      sequenceIndex: map['sequenceIndex'] as int?,
      emotion: map['emotion'] as String?,
      activity: map['activity'] as String?,
    );
  }

  LocationRecord copyWith({
    String? id,
    String? ownerId,
    double? latitude,
    double? longitude,
    String? address,
    String? placeName,
    String? placeType,
    DateTime? timestamp,
    bool? isUser,
    String? trajectoryId,
    int? sequenceIndex,
    String? emotion,
    String? activity,
  }) {
    return LocationRecord(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      placeName: placeName ?? this.placeName,
      placeType: placeType ?? this.placeType,
      timestamp: timestamp ?? this.timestamp,
      isUser: isUser ?? this.isUser,
      trajectoryId: trajectoryId ?? this.trajectoryId,
      sequenceIndex: sequenceIndex ?? this.sequenceIndex,
      emotion: emotion ?? this.emotion,
      activity: activity ?? this.activity,
    );
  }
}
