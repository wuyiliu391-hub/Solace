"""
Fix AI time perception: move time context from _buildSystemPrompt head to tail,
and enhance 【此刻时间】 reminder in _buildMessages.
"""
import re

path = r'c:\Users\Administrator\Desktop\Solace\lib\services\ai_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# === Step 1: Find and extract the time injection block at the START of _buildSystemPrompt ===
# The block starts with "final timeNow = DateTime.now();" and ends before "拉黑状态" or character info
# Pattern: from "final timeNow" to the last time constraint line

# Find the time injection block - it starts after the method signature area
# and is characterized by timeNow, timePeriod, and buffer.writeln with 当前时间
time_block_pattern = re.compile(
    r'(    final timeNow = DateTime\.now\(\);\n'
    r'    final timeHour = timeNow\.hour;\n'
    r'    String timePeriod;\n'
    r'    if \(timeHour >= 5 && timeHour < 8\) \{\n'
    r"      timePeriod = '清晨';\n"
    r'    \} else if \(timeHour >= 8 && timeHour < 12\) \{\n'
    r"      timePeriod = '上午';\n"
    r'    \} else if \(timeHour >= 12 && timeHour < 14\) \{\n'
    r"      timePeriod = '中午';\n"
    r'    \} else if \(timeHour >= 14 && timeHour < 18\) \{\n'
    r"      timePeriod = '下午';\n"
    r'    \} else if \(timeHour >= 18 && timeHour < 22\) \{\n'
    r"      timePeriod = '晚上';\n"
    r'    \} else \{\n'
    r"      timePeriod = '深夜';\n"
    r'    \}\n'
    r".*?"  # buffer.writeln with 当前时间
    r"    buffer\.writeln\('请根据当前真实时间来调整你的回复，不要说错时段。'\);\n"
    r".*?"  # time constraints
    r"(?:    buffer\.writeln\('【时间约束】.*?'\);\n)*?"  # all constraint lines
    r"    \}\n"  # closing brace of last else/if
    r"\n)"  # trailing blank line
)

# Simpler approach: find the block by markers
start_marker = '    final timeNow = DateTime.now();\n'
end_marker_content = "    buffer.writeln('请根据当前真实时间来调整你的回复，不要说错时段。');"

start_idx = content.find(start_marker)
if start_idx == -1:
    print("ERROR: Could not find time injection start marker")
    exit(1)

print(f"Found time injection start at char offset {start_idx}")

# Find the end of the time constraint block
# After "请根据当前真实时间来调整你的回复", there are if/else if blocks for time constraints
# The block ends with a closing } followed by an empty line
search_from = start_idx
end_marker = content.find(end_marker_content, search_from)
if end_marker == -1:
    print("ERROR: Could not find end marker")
    exit(1)

print(f"Found end marker at char offset {end_marker}")

# Find the end of the time constraint if/else block
# After the end_marker, find the last closing } of the constraint block
constraint_end = end_marker + len(end_marker_content)
brace_depth = 0
i = constraint_end
last_close_brace = -1
while i < len(content):
    if content[i] == '{':
        brace_depth += 1
    elif content[i] == '}':
        if brace_depth == 0:
            last_close_brace = i
            break
        brace_depth -= 1
    i += 1

if last_close_brace == -1:
    print("ERROR: Could not find end of time constraint block")
    exit(1)

# Find the newline after the closing brace
block_end = content.find('\n', last_close_brace) + 1
# Skip trailing blank line
while block_end < len(content) and content[block_end] == '\n':
    block_end += 1

time_block = content[start_idx:block_end]
print(f"\nExtracted time block ({len(time_block)} chars):")
print(time_block[:200] + "...")
print("...")

# === Step 2: Remove the time block from its current position ===
content_without_time = content[:start_idx] + content[block_end:]
print(f"\nRemoved time block from position {start_idx}")

# === Step 3: Insert the time block before "return buffer.toString()" in _buildSystemPrompt ===
# Find the return statement that belongs to _buildSystemPrompt (the first one after the removed block)
return_marker = '\n    return buffer.toString();\n'
# Adjust index since we removed content
adjusted_start = start_idx if start_idx < len(content_without_time) else len(content_without_time) - 1
return_idx = content_without_time.find(return_marker, max(0, adjusted_start - 1000))
if return_idx == -1:
    # Try finding it from the beginning
    return_idx = content_without_time.find(return_marker)
    
if return_idx == -1:
    print("ERROR: Could not find return buffer.toString()")
    exit(1)

print(f"Found return statement at char offset {return_idx}")

# Insert time block before return
new_content = content_without_time[:return_idx] + '\n' + time_block + content_without_time[return_idx:]
print("Inserted time block before return statement")

# === Step 4: Enhance 【此刻时间】 reminder in _buildMessages ===
old_reminder = """      final timeReminder = '【此刻时间：\${now.year}年\${now.month}月\${now.day}日 """
# The actual code uses string interpolation - let me find it differently

# Find the timeReminder in _buildMessages
reminder_pattern = re.compile(
    r"(      final timeReminder = '【此刻时间：\$\{now\.year\}年\$\{now\.month\}月\$\{now\.day\}日 ')"
    r"(\n          '\$\{now\.hour\.toString\(\)\.padLeft\(2, '0'\)\}:\$\{now\.minute\.toString\(\)\.padLeft\(2, '0'\)\}】';)"
)

# Simpler: find by the unique text
reminder_start = new_content.find("final timeReminder = '【此刻时间")
if reminder_start == -1:
    print("WARNING: Could not find timeReminder - trying alternative")
    reminder_start = new_content.find("timeReminder")
    
if reminder_start != -1:
    # Find the end of the timeReminder assignment (the semicolon)
    reminder_end = new_content.find("';", reminder_start) + 2
    old_reminder_text = new_content[reminder_start:reminder_end]
    print(f"\nFound timeReminder at offset {reminder_start}:")
    print(old_reminder_text[:100])
    
    # Find the messages.add that uses timeReminder
    add_start = new_content.find("messages.add({", reminder_end)
    add_end = new_content.find("});", add_start) + 3
    old_add_text = new_content[add_start:add_end]
    
    # Replace with enhanced version
    new_reminder_block = """      final timeReminder = '【此刻时间：\${now.year}年\${now.month}月\${now.day}日 '
          '\${now.hour.toString().padLeft(2, '0')}:\${now.minute.toString().padLeft(2, '0')}】\\n'
          '这是你此刻回复的唯一真实时间参考，请严格据此判断时间段，不要说错时间。';
      messages.add({
        'role': 'system',
        'content': timeReminder,
      });"""
    
    new_content = new_content[:reminder_start] + new_reminder_block + new_content[add_end:]
    print("Enhanced timeReminder with stronger anchoring")
else:
    print("ERROR: Could not find timeReminder at all")
    exit(1)

# === Step 5: Write the result ===
with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"\nDone! File written successfully.")
print(f"Original size: {len(content)} chars")
print(f"New size: {len(new_content)} chars")