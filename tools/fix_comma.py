#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fix missing comma in background_service.dart line 844"""
import sys

fpath = r'C:\Users\Administrator\Desktop\solace\lib\services\background_service.dart'
with open(fpath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "'缇': '缇'" in line and not line.rstrip().endswith(','):
        lines[i] = line.rstrip() + ',\n'
        sys.stdout.buffer.write(f"Fixed line {i+1}: {lines[i]}".encode('utf-8'))
        break

with open(fpath, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(lines)
print("Done")
