import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

/// 歌词搜索服务 — 封装 LRCLib.net API（免费公开，无需 API Key）
class LyricsService {
  static const _baseUrl = 'https://lrclib.net/api';

  LyricsService._();
  static final instance = LyricsService._();

  Future<http.Response> _get(Uri uri) async {
    try {
      return await http.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[LyricsService] HTTP error: $e');
      return http.Response('', 500);
    }
  }

  /// 搜索歌曲
  Future<List<MusicTrack>> search(String query, {int limit = 10}) async {
    final uri = Uri.parse('$_baseUrl/search?q=${Uri.encodeComponent(query)}&limit=$limit');
    final response = await _get(uri);
    if (response.statusCode != 200) return [];
    try {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((j) => MusicTrack.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[LyricsService] search parse error: $e');
      return [];
    }
  }

  /// 直接从歌名+歌手获取歌词（带同步时间戳）
  Future<MusicTrack?> getLyrics(String artistName, String trackName) async {
    final uri = Uri.parse('$_baseUrl/get?artist_name=${Uri.encodeComponent(artistName)}&track_name=${Uri.encodeComponent(trackName)}');
    final response = await _get(uri);
    if (response.statusCode != 200) return null;
    try {
      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return MusicTrack.fromJson(data);
    } catch (e) {
      debugPrint('[LyricsService] getLyrics parse error: $e');
      return null;
    }
  }

  /// 按 ID 获取歌词
  Future<MusicTrack?> getById(int id) async {
    final uri = Uri.parse('$_baseUrl/get/$id');
    final response = await _get(uri);
    if (response.statusCode != 200) return null;
    try {
      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return MusicTrack.fromJson(data);
    } catch (e) {
      debugPrint('[LyricsService] getById parse error: $e');
      return null;
    }
  }
}