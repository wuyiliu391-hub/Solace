#!/usr/bin/env python3
"""Decode the garbled Chinese in constants.dart"""
import sys

with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'rb') as f:
    data = f.read()

# Find the garbled section
target = '鈹'.encode('utf-8')
pos = data.find(target)
if pos < 0:
    print("No garbled text found")
    sys.exit(0)

sample = data[pos:pos+30]
print(f"Raw bytes around first garbled: {sample.hex(' ')}")

# The garbled text: try reverse-encoding
garbled_text = data.decode('utf-8', errors='replace')

# Try each possible encoding chain
for enc in ['gbk', 'gb18030', 'big5', 'cp950', 'shift-jis', 'euc-jp', 'euc-kr', 'latin1', 'cp1252']:
    try:
        intermediate = garbled_text.encode(enc, errors='strict')
        result = intermediate.decode('utf-8', errors='strict')
        # Check if result contains CJK chars (would indicate successful decode)
        cjk_count = sum(1 for c in result if '\u4e00' <= c <= '\u9fff')
        if cjk_count > 10:
            print(f"\n=== REVERSE {enc}: SUCCESS (CJK chars: {cjk_count}) ===")
            lines = result.split('\n')
            for i, line in enumerate(lines[:30], 1):
                sys.stdout.buffer.write(f"{i}: {line}\n".encode('utf-8'))
            break
        else:
            print(f"REVERSE {enc}: CJK={cjk_count}, not enough")
    except Exception as e:
        print(f"REVERSE {enc}: FAILED ({type(e).__name__})")
