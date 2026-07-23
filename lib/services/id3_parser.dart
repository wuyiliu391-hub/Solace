import 'dart:convert';
import 'dart:io';

/// ID3 标签解析结果
class Id3Info {
  final String? title;
  final String? artist;
  final String? album;
  final String? year;

  const Id3Info({this.title, this.artist, this.album, this.year});

  bool get hasEnough => title != null && artist != null;
}

/// 纯 Dart ID3 标签解析器 — 零依赖，支持 ID3v1 + ID3v2.3/2.4
class Id3Parser {
  /// 从本地文件读取 ID3 标签
  static Future<Id3Info> fromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const Id3Info();
      final raf = await file.open(mode: FileMode.read);

      try {
        // 优先 ID3v2（文件头部），回退 ID3v1（文件尾部）
        final v2 = await _parseV2(raf);
        if (v2 != null && v2.hasEnough) return v2;

        final v1 = await _parseV1(raf);
        return v1;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return const Id3Info();
    }
  }

  /// 从 mp3 文件名推测歌名（当 ID3 不可用时）
  static Id3Info fromFileName(String fileName) {
    final name = fileName.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false), '');
    final parts = name.split(RegExp(r'\s*[-–—]\s*'));
    if (parts.length >= 2) {
      return Id3Info(artist: parts[0].trim(), title: parts.sublist(1).join(' - ').trim());
    }
    return Id3Info(title: name.trim());
  }

  // ── ID3v2 解析 ──

  static Future<Id3Info?> _parseV2(RandomAccessFile raf) async {
    await raf.setPosition(0);
    final header = await raf.read(10);
    if (header.length < 10) return null;

    // 检查 "ID3" 魔数
    if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) return null;

    // 版本: header[3]=主版本, header[4]=修订版本
    final majorVersion = header[3];
    if (majorVersion < 2 || majorVersion > 4) return null;

    // 标志字节
    final flags = header[5];

    // 标签大小（4 字节，每字节只用低 7 位，synchsafe）
    final tagSize = _synchSafeInt(header, 6);

    // 是否有扩展头（bit 6 of flags）
    final hasExtendedHeader = (flags & 0x40) != 0;

    int offset = 10;
    if (hasExtendedHeader) {
      await raf.setPosition(offset);
      final extHeaderSizeBytes = await raf.read(4);
      if (extHeaderSizeBytes.length < 4) return null;
      final extSize = majorVersion == 4
          ? _synchSafeInt(extHeaderSizeBytes, 0)
          : (extHeaderSizeBytes[0] << 24) |
              (extHeaderSizeBytes[1] << 16) |
              (extHeaderSizeBytes[2] << 8) |
              extHeaderSizeBytes[3];
      offset += extSize;
    }

    // 读取帧
    final maxRead = tagSize.clamp(0, 65536); // 安全上限 64KB
    await raf.setPosition(offset);
    final frameData = await raf.read(maxRead);

    String? title, artist, album, year;
    int pos = 0;

    while (pos + 10 <= frameData.length) {
      String frameId;
      int frameSize;

      if (majorVersion == 2) {
        // ID3v2.2: 3 字节帧 ID
        if (pos + 6 > frameData.length) break;
        frameId = latin1.decode(frameData.sublist(pos, pos + 3));
        frameSize = (frameData[pos + 3] << 16) | (frameData[pos + 4] << 8) | frameData[pos + 5];
        pos += 6;
      } else {
        // ID3v2.3/2.4: 4 字节帧 ID
        frameId = latin1.decode(frameData.sublist(pos, pos + 4));
        pos += 4;

        // 帧大小（v2.4 是 synchsafe，v2.3 是普通大端）
        if (pos + 4 > frameData.length) break;
        final sizeBytes = frameData.sublist(pos, pos + 4);
        frameSize = majorVersion == 4
            ? _synchSafeInt(sizeBytes, 0)
            : (sizeBytes[0] << 24) | (sizeBytes[1] << 16) | (sizeBytes[2] << 8) | sizeBytes[3];
        pos += 4;

        // 跳过帧标志（2 字节）
        if (pos + 2 > frameData.length) break;
        pos += 2;
      }

      if (frameSize <= 0 || pos + frameSize > frameData.length) break;

      final frameContent = frameData.sublist(pos, pos + frameSize);
      pos += frameSize;

      // 跳过空帧
      if (frameContent.isEmpty) continue;

      // 文本帧：第一个字节是编码标记
      final encoding = frameContent[0];
      String text;
      try {
        if (encoding == 0x01 || encoding == 0x02) {
          // UTF-16 (with or without BOM)
          final bom = frameContent.length >= 3
              ? (frameContent[1] == 0xFF && frameContent[2] == 0xFE)
              : false;
          final start = bom ? 3 : 1;
          text = utf8.decode(frameContent.sublist(start), allowMalformed: true);
        } else {
          // ISO-8859-1 or UTF-8
          text = encoding == 0x03
              ? utf8.decode(frameContent.sublist(1))
              : latin1.decode(frameContent.sublist(1));
        }
      } catch (_) {
        try {
          text = latin1.decode(frameContent.sublist(1));
        } catch (_) {
          continue;
        }
      }
      text = text.replaceAll('\x00', '').trim();
      if (text.isEmpty) continue;

      switch (frameId) {
        case 'TIT2':
        case 'TT2':
          title = text;
        case 'TPE1':
        case 'TP1':
          artist = text;
        case 'TALB':
        case 'TAL':
          album = text;
        case 'TYER':
        case 'TYE':
          year = text;
      }

      if (title != null && artist != null) break;
    }

    if (title != null || artist != null) {
      return Id3Info(title: title, artist: artist, album: album, year: year);
    }
    return null;
  }

  // ── ID3v1 解析 ──

  static Future<Id3Info> _parseV1(RandomAccessFile raf) async {
    try {
      final length = await raf.length();
      if (length < 128) return const Id3Info();

      await raf.setPosition(length - 128);
      final data = await raf.read(128);
      if (data.length < 128) return const Id3Info();

      // 检查 "TAG" 标识
      if (data[0] != 0x54 || data[1] != 0x41 || data[2] != 0x47) {
        return const Id3Info();
      }

      final title = _trimNull(latin1.decode(data.sublist(3, 33)));
      final artist = _trimNull(latin1.decode(data.sublist(33, 63)));
      final album = _trimNull(latin1.decode(data.sublist(63, 93)));
      final year = _trimNull(latin1.decode(data.sublist(93, 97)));

      return Id3Info(title: title, artist: artist, album: album, year: year);
    } catch (_) {
      return const Id3Info();
    }
  }

  // ── 工具 ──

  static int _synchSafeInt(List<int> bytes, int offset) {
    return (bytes[offset] << 21) |
        (bytes[offset + 1] << 14) |
        (bytes[offset + 2] << 7) |
        bytes[offset + 3];
  }

  static String _trimNull(String s) {
    final idx = s.indexOf('\x00');
    return (idx >= 0 ? s.substring(0, idx) : s).trim();
  }
}