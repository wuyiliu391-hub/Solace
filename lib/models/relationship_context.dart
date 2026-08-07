class RelationshipContext {
  final String chatId;
  final double trust;
  final String? boundary;
  final String? unresolvedConflict;
  final String? recentImportantEvent;
  final DateTime updatedAt;

  const RelationshipContext({
    required this.chatId,
    this.trust = 0.5,
    this.boundary,
    this.unresolvedConflict,
    this.recentImportantEvent,
    required this.updatedAt,
  });

  bool get hasConflict => unresolvedConflict?.isNotEmpty == true;

  RelationshipContext copyWith({
    double? trust,
    String? boundary,
    bool clearBoundary = false,
    String? unresolvedConflict,
    bool clearConflict = false,
    String? recentImportantEvent,
    DateTime? updatedAt,
  }) =>
      RelationshipContext(
        chatId: chatId,
        trust: (trust ?? this.trust).clamp(0.0, 1.0),
        boundary: clearBoundary ? null : boundary ?? this.boundary,
        unresolvedConflict: clearConflict
            ? null
            : unresolvedConflict ?? this.unresolvedConflict,
        recentImportantEvent: recentImportantEvent ?? this.recentImportantEvent,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'chatId': chatId,
        'trust': trust,
        'boundary': boundary,
        'unresolvedConflict': unresolvedConflict,
        'recentImportantEvent': recentImportantEvent,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RelationshipContext.fromMap(Map<String, dynamic> map) =>
      RelationshipContext(
        chatId: map['chatId']?.toString() ?? '',
        trust: ((map['trust'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
        boundary: map['boundary']?.toString(),
        unresolvedConflict: map['unresolvedConflict']?.toString(),
        recentImportantEvent: map['recentImportantEvent']?.toString(),
        updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}
