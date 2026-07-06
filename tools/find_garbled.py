#!/usr/bin/env python3
"""Find remaining garbled chars in constants.dart and fix them"""
import sys

with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'rb') as f:
    data = f.read()

text = data.decode('utf-8')

# Find lines with U+FFFD (replacement character) or other suspicious chars
for i, line in enumerate(text.split('\n'), 1):
    has_garbled = False
    for ch in line:
        if ch == '\ufffd' or (ord(ch) > 127 and ord(ch) < 0x4e00) or (ord(ch) > 0x9fff and ord(ch) < 0xff00):
            has_garbled = True
            break
    if has_garbled:
        hex_parts = []
        for ch in line:
            if ord(ch) > 127:
                hex_parts.append(f'{ch}(U+{ord(ch):04X})')
        out = f"LINE {i}: {' '.join(hex_parts[:15])}\n  TEXT: {line}\n"
        sys.stdout.buffer.write(out.encode('utf-8'))
