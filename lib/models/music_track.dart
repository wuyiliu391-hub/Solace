/// 音乐轨道模型 — 用于音乐共情模式
class MusicTrack {
  final int id;
  final String name;
  final String artistName;
  final String? albumName;
  final int? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  /// 用户自定义的唱片中心封面图路径
  String? coverImagePath;

  /// 解析后的同步歌词行
  List<LyricLine>? _parsedSynced;

  MusicTrack({
    required this.id,
    required this.name,
    required this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
    this.coverImagePath,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: _toInt(json['id'], 0),
      name: _toStr(json['name'], _toStr(json['trackName'], '')),
      artistName: _toStr(json['artistName'], ''),
      albumName: _toStrOrNull(json['albumName']),
      duration: _toIntOrNull(json['duration']),
      instrumental: json['instrumental'] == true,
      plainLyrics: _toStrOrNull(json['plainLyrics']),
      syncedLyrics: _toStrOrNull(json['syncedLyrics']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artistName': artistName,
        'albumName': albumName,
        'duration': duration,
        'instrumental': instrumental,
        'plainLyrics': plainLyrics,
        'syncedLyrics': syncedLyrics,
      };

  /// 解析同步歌词为带时间戳的行列表
  List<LyricLine> get parsedSyncedLyrics {
    if (_parsedSynced != null) return _parsedSynced!;
    _parsedSynced = _parseLrc(syncedLyrics);
    return _parsedSynced!;
  }

  /// 根据当前播放位置获取对应的歌词行索引
  int getLyricIndex(Duration position) {
    final lines = parsedSyncedLyrics;
    if (lines.isEmpty) return -1;
    final ms = position.inMilliseconds.toDouble();
    for (int i = lines.length - 1; i >= 0; i--) {
      if (ms >= lines[i].timestampMs) return i;
    }
    return -1;
  }

  static List<LyricLine> _parseLrc(String? lrc) {
    if (lrc == null || lrc.isEmpty) return [];
    final result = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match == null) continue;
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      final msStr = match.group(3)!;
      final ms = int.parse(msStr.length == 2 ? '${msStr}0' : msStr);
      final text = match.group(4)!.trim();
      if (text.isEmpty) continue;
      result.add(LyricLine(
        timestampMs: (min * 60000 + sec * 1000 + ms).toDouble(),
        text: text,
      ));
    }
    result.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return result;
  }

  /// 普通歌词按行拆分为无时间戳行
  List<LyricLine> get plainLyricLines {
    if (plainLyrics == null || plainLyrics!.isEmpty) return [];
    return plainLyrics!
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((text) => LyricLine(timestampMs: 0, text: text.trim()))
        .toList();
  }
}

class LyricLine {
  final double timestampMs;
  final String text;

  const LyricLine({required this.timestampMs, required this.text});
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int _toInt(dynamic v, int fallback) => _toIntOrNull(v) ?? fallback;

String? _toStrOrNull(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

String _toStr(dynamic v, String fallback) => _toStrOrNull(v) ?? fallback;