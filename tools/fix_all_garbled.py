#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fix remaining garbled lines in constants.dart, main.dart, chat_bloc.dart, background_service.dart"""
import sys, os

base = r'C:\Users\Administrator\Desktop\solace\lib'

def fix_file(rel_path, line_fixes):
    """Fix specific lines in a file. line_fixes: dict of {1-indexed_line: new_content}"""
    fpath = os.path.join(base, rel_path)
    with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    
    fixed = 0
    for i, line in enumerate(lines):
        ln = i + 1  # 1-indexed
        if ln in line_fixes:
            new_content = line_fixes[ln]
            if not new_content.endswith('\n'):
                new_content += '\n'
            lines[i] = new_content
            fixed += 1
            sys.stdout.buffer.write(f"  FIXED L{ln}\n".encode('utf-8'))
    
    with open(fpath, 'w', encoding='utf-8', newline='\n') as f:
        f.writelines(lines)
    
    return fixed

total = 0

# === constants.dart ===
sys.stdout.buffer.write(b"\n=== constants.dart ===\n")
total += fix_file(os.path.join('config', 'constants.dart'), {
    87: "  /// 判断当前配置是否为内置 GLM-Z1-9B",
})

# === main.dart ===
sys.stdout.buffer.write(b"\n=== main.dart ===\n")
total += fix_file('main.dart', {
    294: "    // 公告已移除，仅保留版本更新提示（UpdateDialog",
    877: "  // QQ 极简深色 + 微信白色 配色方案",
    914: "  // QQ 极简深色暗色方案",
    970: "    // v10.0 新增服务",
})

# === chat_bloc.dart ===
sys.stdout.buffer.write(b"\n=== chat_bloc.dart ===\n")
total += fix_file(os.path.join('blocs', 'chat', 'chat_bloc.dart'), {
    1369: "    // 4. 获取记忆",
    1527: "    // 7. 存记忆 + 智能提取（非关键）",
    2401: "        // 根据错误类型显示不同的友好提示",
    3394: "    // 清理旧数据（保留最近 N 天）",
    3679: "    // 平静/开心：快速已读",
})

# === background_service.dart ===
sys.stdout.buffer.write(b"\n=== background_service.dart ===\n")
total += fix_file(os.path.join('services', 'background_service.dart'), {
    844: "    '缇': '缇'",
})

sys.stdout.buffer.write(f"\nTotal lines fixed: {total}\n".encode('utf-8'))
