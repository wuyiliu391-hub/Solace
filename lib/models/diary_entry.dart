class DiaryEntry {
  final String id;
  final DateTime date;
  final String mood;
  final int moodScore;
  final String content;
  final String? authorId;
  final String? authorName;
  final String? authorAvatar;

  DiaryEntry({
    required this.id,
    required this.date,
    required this.mood,
    required this.moodScore,
    required this.content,
    this.authorId,
    this.authorName,
    this.authorAvatar,
  });

  bool get isFromAI => authorId != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'mood': mood,
    'moodScore': moodScore,
    'content': content,
    if (authorId != null) 'authorId': authorId,
    if (authorName != null) 'authorName': authorName,
    if (authorAvatar != null) 'authorAvatar': authorAvatar,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    mood: json['mood'] as String,
    moodScore: json['moodScore'] as int,
    content: json['content'] as String,
    authorId: json['authorId'] as String?,
    authorName: json['authorName'] as String?,
    authorAvatar: json['authorAvatar'] as String?,
  );
}
