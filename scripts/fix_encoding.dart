import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  final path = r'c:\Users\Administrator\Desktop\Solace\lib\services\ai_service.dart';
  final bytes = await File(path).readAsBytes();
  print('File bytes: ${bytes.length}');

  // Try to decode as UTF-8 first
  String text;
  try {
    text = utf8.decode(bytes, allowMalformed: true);
    print('UTF-8 decode (with malformed): ${text.length} chars');
  } catch (e) {
    print('UTF-8 decode failed: $e');
    return;
  }

  // Count garbled-looking characters (high Unicode codepoints that look like CJK mojibake)
  int garbledCount = 0;
  int normalCount = 0;
  for (int i = 0; i < text.length && i < 1000; i++) {
    final cp = text.codeUnitAt(i);
    if (cp > 0x4E00 && cp < 0x9FFF) {
      normalCount++; // Normal CJK
    } else if (cp > 0x9300 && cp < 0x9FFF) {
      garbledCount++; // Possible mojibake CJK range
    }
  }
  print('First 1000 chars: normal=$normalCount, garbled-range=$garbledCount');

  // Sample some garbled text
  final sampleIdx = text.indexOf('鍒');
  if (sampleIdx >= 0) {
    print('Sample garbled text at $sampleIdx:');
    print('  "${text.substring(sampleIdx, sampleIdx + 30).replaceAll('\n', '\\n')}"');
    
    // Get the bytes of this garbled text
    final sampleBytes = utf8.encode(text.substring(sampleIdx, sampleIdx + 30));
    print('  Bytes hex: ${sampleBytes.sublist(0, 30).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  // Try reverse mojibake: UTF-8 -> Latin-1 interpretation
  // Take garbled UTF-8 text, re-encode each char's codepoint as Latin-1 byte
  // This reverses: Original UTF-8 -> (read as Latin-1 -> write as UTF-8)
  print('\n--- Attempting mojibake fix ---');
  
  // Method: for each CJK character in the garbled range,
  // convert its codepoint to bytes (as if it were UTF-8 encoded),
  // then try to interpret those bytes as another encoding
  
  // Actually, let me try the classic reverse:
  // 1. Take the garbled text as UTF-8 string
  // 2. Encode it back to Latin-1 bytes (this reverses the "read as Latin-1" step)
  // 3. Decode those bytes as UTF-8 (this gets the original Chinese)
  
  try {
    // Try: text chars -> encode each char as latin1 byte -> decode as utf8
    final latin1Bytes = <int>[];
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      if (cp < 256) {
        latin1Bytes.add(cp);
      } else {
        // For multi-byte UTF-8 chars, we need to encode them as UTF-8 first,
        // then treat those bytes as latin1
        final encoded = utf8.encode(String.fromCharCode(cp));
        latin1Bytes.addAll(encoded);
      }
    }
    
    final fixed = utf8.decode(latin1Bytes, allowMalformed: true);
    print('After latin1 reversal: ${fixed.length} chars');
    
    // Check if the sample is now readable Chinese
    final fixedSample = fixed.substring(sampleIdx, sampleIdx + 30);
    print('Fixed sample: "$fixedSample"');
    
    // Count how many readable Chinese chars we have now
    int readableCount = 0;
    for (int i = 0; i < 500 && i < fixed.length; i++) {
      final cp = fixed.codeUnitAt(i);
      if (cp >= 0x4E00 && cp <= 0x9FFF) readableCount++;
    }
    print('Readable Chinese in first 500 chars: $readableCount');
    
    if (readableCount > 5) {
      print('\nSUCCESS! Writing fixed file...');
      // Write with BOM so editors recognize UTF-8
      final bom = [0xEF, 0xBB, 0xBF];
      final fixedBytes = utf8.encode(fixed);
      final outputBytes = Uint8List(bom.length + fixedBytes.length);
      outputBytes.setRange(0, bom.length, bom);
      outputBytes.setRange(bom.length, outputBytes.length, fixedBytes);
      await File(path).writeAsBytes(outputBytes);
      print('Done! File written with UTF-8 BOM.');
    } else {
      print('\nLatin-1 reversal did not produce readable Chinese.');
    }
  } catch (e) {
    print('Latin-1 reversal failed: $e');
  }

  // Method 2: Try Windows-1252 (CP1252) reversal
  // CP1252 is similar to Latin-1 but has different mappings for 0x80-0x9F
  try {
    final cp1252Bytes = <int>[];
    // CP1252 special mappings for 0x80-0x9F
    const cp1252Special = {
      0x20AC: 0x80, // €
      0x201A: 0x82, // ‚
      0x0192: 0x83, // ƒ
      0x201E: 0x84, // „
      0x2026: 0x85, // …
      0x2020: 0x86, // †
      0x2021: 0x87, // ‡
      0x02C6: 0x88, // ˆ
      0x2030: 0x89, // ‰
      0x0160: 0x8A, // Š
      0x2039: 0x8B, // ‹
      0x0152: 0x8C, // Œ
      0x017D: 0x8E, // Ž
      0x2018: 0x91, // '
      0x2019: 0x92, // '
      0x201C: 0x93, // "
      0x201D: 0x94, // "
      0x2022: 0x95, // •
      0x2013: 0x96, // –
      0x2014: 0x97, // —
      0x02DC: 0x98, // ˜
      0x2122: 0x99, // ™
      0x0161: 0x9A, // š
      0x203A: 0x9B, // ›
      0x0153: 0x9C, // œ
      0x017E: 0x9E, // ž
      0x0178: 0x9F, // Ÿ
    };
    
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      if (cp < 128) {
        cp1252Bytes.add(cp);
      } else if (cp1252Special.containsKey(cp)) {
        cp1252Bytes.add(cp1252Special[cp]!);
      } else if (cp < 256) {
        cp1252Bytes.add(cp);
      } else {
        // Multi-byte char: encode as UTF-8 first
        final encoded = utf8.encode(String.fromCharCode(cp));
        cp1252Bytes.addAll(encoded);
      }
    }
    
    final fixed2 = utf8.decode(cp1252Bytes, allowMalformed: true);
    print('\nCP1252 reversal: ${fixed2.length} chars');
    
    int readable2 = 0;
    for (int i = 0; i < 500 && i < fixed2.length; i++) {
      final cp = fixed2.codeUnitAt(i);
      if (cp >= 0x4E00 && cp <= 0x9FFF) readable2++;
    }
    print('Readable Chinese in first 500 chars: $readable2');
    
    if (readable2 > 5) {
      print('Fixed sample: "${fixed2.substring(sampleIdx, sampleIdx + 30)}"');
    }
  } catch (e) {
    print('CP1252 reversal failed: $e');
  }
}