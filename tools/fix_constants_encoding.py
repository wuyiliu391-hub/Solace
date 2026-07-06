#!/usr/bin/env python3
"""Fix double-encoded constants.dart using raw byte manipulation.
Encoding chain: Original UTF-8 bytes → read as Windows CP936 (GBK) → saved as UTF-8
To reverse: current UTF-8 → encode each char back to CP936 bytes → decode as UTF-8
Special handling for € (U+20AC) which maps to byte 0x80 in CP936.
"""
import sys

# Read current file
with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'rb') as f:
    data = f.read()

text = data.decode('utf-8')

# Build the byte buffer by reversing the double encoding
byte_buf = bytearray()
fixed_count = 0

for ch in text:
    code = ord(ch)
    
    # ASCII: pass through (same in UTF-8 and GBK)
    if code < 128:
        byte_buf.append(code)
        continue
    
    # Special: € (U+20AC) came from byte 0x80 in CP936
    if ch == '\u20ac':
        byte_buf.append(0x80)
        fixed_count += 1
        continue
    
    # For other non-ASCII chars, try to encode as GBK
    # This reverses: GBK-decoded-char → GBK bytes (= original UTF-8 bytes)
    try:
        gbk_bytes = ch.encode('gbk')
        byte_buf.extend(gbk_bytes)
        fixed_count += 1
    except UnicodeEncodeError:
        # Can't encode as GBK - this char is probably legitimate (not garbled)
        # Keep its UTF-8 encoding
        byte_buf.extend(ch.encode('utf-8'))

# Now decode the collected bytes as UTF-8
try:
    fixed_text = byte_buf.decode('utf-8', errors='replace')
    
    # Write the fixed file
    with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'w', encoding='utf-8', newline='\n') as f:
        f.write(fixed_text)
    
    # Show sample
    lines = fixed_text.split('\n')
    sys.stdout.buffer.write(f"Fixed {fixed_count} garbled positions\n".encode('utf-8'))
    sys.stdout.buffer.write(f"Total lines: {len(lines)}\n\n".encode('utf-8'))
    
    for i, line in enumerate(lines[:10], 1):
        sys.stdout.buffer.write(f"{i}: {line}\n".encode('utf-8'))
    print("---")
    for i, line in enumerate(lines, 1):
        if 'GlmModeParams' in line or 'buildExtraParams' in line or 'isGlmZ19B' in line:
            sys.stdout.buffer.write(f"{i}: {line}\n".encode('utf-8'))
    print("---")
    # Show some more sections
    for i, line in enumerate(lines[69:92], 70):
        sys.stdout.buffer.write(f"{i}: {line}\n".encode('utf-8'))
    
except Exception as e:
    sys.stdout.buffer.write(f"ERROR: {e}\n".encode('utf-8'))
