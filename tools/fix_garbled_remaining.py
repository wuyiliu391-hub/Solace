#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fix remaining garbled lines by line number"""
import sys

with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Map line number (1-indexed) -> correct replacement line content
# Use the context around each garbled line to identify it
fixes = {}

for i, line in enumerate(lines):
    n = i + 1  # 1-indexed
    
    # Line 73: nvidiaStep37FlashProvider value
    if "nvidiaStep37FlashProvider = " in line and "Step" in line:
        fixes[i] = "  static const String nvidiaStep37FlashProvider = '内置最新 Step 模型';\n"
    
    # Line 85: siliconflowGlmZ19BRemark value
    if "siliconflowGlmZ19BRemark = " in line:
        fixes[i] = "  static const String siliconflowGlmZ19BRemark = '硅基流动社区模型，9B 推理模型，适合作为第二内置备用模型';\n"
    
    # Line 87: isGlmZ19B doc comment
    if "isGlmZ19B" in line and "///" in line:
        fixes[i] = "  /// 判断当前配置是否为内置 GLM-Z1-9B\n"
    
    # Line 94: GlmModeParams class doc comment (merged with class declaration)
    if "GlmModeParams" in line and "class" in line and "///" in line:
        fixes[i] = "/// GLM-Z1-9B 各模式专属参数（仅对内置 GLM 模型生效）\nclass GlmModeParams {\n"
    
    # Line 101: 普通聊天模式 section comment
    if "chatTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "聊" in line:
            fixes[i] = "  // ─── 普通聊天模式 ───\n"
    
    # Line 108: 小说模式 section comment
    if "novelTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "小" in line:
            fixes[i] = "  // ─── 小说模式 ───\n"
    
    # Line 115: 朋友圈模式 section comment
    if "momentTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "朋" in line:
            fixes[i] = "  // ─── 朋友圈模式 ───\n"
    
    # Line 129: 反思模式 section comment
    if "reflectionTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "反" in line:
            fixes[i] = "  // ─── 反思模式 ───\n"
    
    # Line 143: 语音通话模式 section comment
    if "voiceTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "话" in line:
            fixes[i] = "  // ─── 语音通话模式 ───\n"
    
    # Line 150: 纯AI模式 section comment
    if "pureAiTemperature" in lines[i+1] if i+1 < len(lines) else False:
        if "// ───" in line and "AI" in line:
            fixes[i] = "  // ─── 纯AI模式 ───\n"
    
    # Line 199: buildExtraParams doc comment (merged with method)
    if "buildExtraParams" in line and "///" in line:
        fixes[i] = "  /// 构建 GLM-Z1-9B 的额外请求参数（top_p, top_k, frequency_penalty, thinking_budget）\n  static Map<String, dynamic> buildExtraParams({\n"
    
    # Line 305: Core Hub 中层
    if "Core Hub" in line and "// ───" in line:
        fixes[i] = "  // ─── Core Hub 中层 ───\n"
    
    # Line 391: memoryPromptCap doc comment
    if "memoryPromptCap" in line:
        fixes[i] = "  /// buildConsolidatedMemoryPrompt 等实时路径加载记忆上限\n  static const int memoryPromptCap = 200;\n"
    
    # Line 393: memoryMaintenanceCap doc comment
    if "memoryMaintenanceCap" in line:
        fixes[i] = "  /// 后台维护任务（裁出/清理/合并/统计）加载记忆上限\n  static const int memoryMaintenanceCap = 500;\n"

# Apply fixes
result_lines = []
for i, line in enumerate(lines):
    if i in fixes:
        replacement = fixes[i]
        # Handle multi-line replacements (like GlmModeParams and buildExtraParams)
        result_lines.append(replacement)
        sys.stdout.buffer.write(f"FIXED line {i+1}: {replacement[:60].strip()}\n".encode('utf-8'))
    else:
        result_lines.append(line)

# Write back
with open(r'C:\Users\Administrator\Desktop\solace\lib\config\constants.dart', 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(result_lines)

sys.stdout.buffer.write(f"\nFixed {len(fixes)} lines\n".encode('utf-8'))
