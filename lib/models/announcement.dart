class Announcement {
  final String id;
  final String title;
  final String content;
  final String date;
  final String type; // info | update | important

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.type,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      date: json['date'] as String? ?? '',
      type: json['type'] as String? ?? 'info',
    );
  }

  bool get isImportant => type == 'important';
  bool get isUpdate => type == 'update';
}
