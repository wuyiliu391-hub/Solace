# Fix unterminated string literals in chat_detail_screen.dart
# The closing quotes were moved to separate lines

with open('lib/screens/chat/chat_detail_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact block
old = '        content: const Text(\n          \'你已经连续使用 Solace 超过 2 小时了。\\n\n\n\'\n          \'AI 陪伴虽然有趣，但也别忘了：\\n\'\n          \'• 起身活动一下，保护眼睛和颈椎\\n\'\n          \'• 与现实中的朋友、家人聊聊天\\n\'\n          \'• 你正在与 AI 互动，不是真实的人\\n\n\n\'\n          \'适度使用，健康生活\',\n'

new = '        content: const Text(\n          \'你已经连续使用 Solace 超过 2 小时了。\\n\\n\'\n          \'AI 陪伴虽然有趣，但也别忘了：\\n\'\n          \'• 起身活动一下，保护眼睛和颈椎\\n\'\n          \'• 与现实中的朋友、家人聊聊天\\n\'\n          \'• 你正在与 AI 互动，不是真实的人\\n\\n\'\n          \'适度使用，健康生活\',\n'

if old in content:
    content = content.replace(old, new, 1)
    with open('lib/screens/chat/chat_detail_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS: Block replaced')
else:
    print('FAIL: Could not find exact old block')
    # Find where the block is
    idx = content.find('content: const Text(')
    if idx > 0:
        # Show context
        end_idx = content.find('style: TextStyle(fontSize: 14, height: 1.6)', idx)
        if end_idx > 0:
            block = content[content.rfind('\n', 0, idx):end_idx]
            print('REPR of block:')
            print(repr(block))
