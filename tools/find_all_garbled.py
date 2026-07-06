#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find all lines with garbled Chinese patterns (double-encoded UTF-8→GBK→UTF-8)"""
import sys, os

base = r'C:\Users\Administrator\Desktop\solace\lib'
garbled_markers = ['鈹', '鍐', '纭', '鍒', '鍚', '閫', '鏅', '灏', '鏈', '鍐欎', '鍙', '涓', '璇', '绾', '缇', '璁板', '璁哄', '鍏', '浜烘', '鍘熻', '鏋', '鑾峰', '瀵硅', '鎸夌', '鎻愬彇', '鍒嗘瀽', '缁存姢', '鎺ㄨ崘', '鍐呯', '鎴愬姛', '澶勭', '杩斿洖', '璁剧', '杈撳叆']

for root, dirs, files in os.walk(base):
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        fpath = os.path.join(root, fname)
        with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
        
        garbled_lines = []
        for i, line in enumerate(lines):
            # Skip lines that only have ─ (U+2500) - those are fine
            stripped = line.replace('─', '').strip()
            if not stripped:
                continue
            for marker in garbled_markers:
                if marker in line:
                    rel = fpath.replace(base + os.sep, '')
                    garbled_lines.append((i+1, line.rstrip()))
                    break
        
        if garbled_lines:
            rel = fpath.replace(base + os.sep, '')
            sys.stdout.buffer.write(f"\n=== {rel} ({len(garbled_lines)} garbled lines) ===\n".encode('utf-8'))
            for ln, text in garbled_lines[:20]:
                sys.stdout.buffer.write(f"  L{ln}: {text[:100]}\n".encode('utf-8'))
            if len(garbled_lines) > 20:
                sys.stdout.buffer.write(f"  ... and {len(garbled_lines)-20} more\n".encode('utf-8'))
