import 'dart:convert';
import 'dart:math';

class StringGuard {
  StringGuard._();

  static const _keyFragmentA = <int>[
    0x3E, 0xB7, 0x9A, 0x1F, 0xC4, 0xD8, 0x62, 0x50,
    0x91, 0x2A, 0x7E, 0x4B, 0xF3, 0x08, 0xC5, 0x6D,
  ];

  static const _keyFragmentB = <int>[
    0x12, 0x84, 0x7F, 0x53, 0xE9, 0x0B, 0xAC, 0x36,
    0xD4, 0x18, 0x65, 0x9C, 0x2E, 0xF1, 0x4A, 0x87,
  ];

  static int _gen(int i) {
    final r = Random(0x9E3B + i * 0x7A1F);
    return r.nextInt(256);
  }

  static List<int> get _fullKey {
    return List<int>.generate(
      _keyFragmentA.length,
      (i) => (_keyFragmentA[i] ^ _keyFragmentB[i] ^ (0x5C + i * 0x8D) & 0xFF) ^ _gen(i),
    );
  }

  static String decrypt(String encrypted) {
    final raw = base64.decode(encrypted);
    final key = _fullKey;
    final bytes = List<int>.generate(
      raw.length,
      (i) => raw[i] ^ key[i % key.length],
    );
    return utf8.decode(bytes);
  }

  static String encrypt(String plain) {
    final bytes = utf8.encode(plain);
    final key = _fullKey;
    final encrypted = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return base64.encode(encrypted);
  }
}
