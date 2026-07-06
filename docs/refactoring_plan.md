# Solace 全栈重构执行方案

> 约束：Flutter + Dart，不切换技术栈。每个模块严格对标指定开源项目，1:1 转译。
> 优先级：UI SillyTavern > 主动对话 Muice-Chatbot > 后端 KouriChat

---

## 一、模块-来源映射表（全局唯一，不可混用）

### Layer 1: UI 交互层 → 【对标来源：SillyTavern】

| Solace 新模块 | SillyTavern 来源文件 | 职责 |
|---|---|---|
| `screens/chat/chat_screen.dart` | `public/script.js` (addOneMessage/messageFormatting) | 聊天主页面、消息渲染 |
| `widgets/message_bubble.dart` | `public/index.html:7377` (#message_template) | 消息气泡模板、操作按钮 |
| `widgets/message_actions.dart` | `public/scripts/chats.js` (hide/unhide/copy/edit) | 消息操作：编辑/复制/隐藏/删除 |
| `screens/character/character_edit_screen.dart` | `public/index.html:6039` (#form_create) | 角色卡编辑完整表单 |
| `models/character_card_v2.dart` | `public/scripts/char-data.js` (v2CharData) | 角色卡 v2 数据结构 |
| `screens/settings/world_info_screen.dart` | `public/scripts/world-info.js` | 世界观设定 CRUD |
| `models/world_info_entry.dart` | `public/scripts/world-info.js` (条目字段) | WI 条目数据结构 |
| `services/world_info_engine.dart` | `public/scripts/world-info.js` (checkWorldInfo) | 关键词匹配引擎 |
| `screens/settings/api_settings_screen.dart` | `public/scripts/openai.js` | 多模型 API 设置页 |
| `screens/settings/prompt_manager_screen.dart` | `public/scripts/PromptManager.js` | Prompt 编辑/排序/注入 |
| `models/prompt_entry.dart` | `public/scripts/PromptManager.js` (字段) | Prompt 条目数据结构 |
| `screens/settings/instruct_mode_screen.dart` | `public/scripts/instruct-mode.js` | Instruct 模板设置 |
| `screens/settings/system_prompt_screen.dart` | `public/scripts/sysprompt.js` | 系统提示词预设 |
| `widgets/swipe_handler.dart` | `public/script.js` (swipe_left/right) | 消息滑动翻页 |
| `widgets/drawer_panel.dart` | `public/index.html` (左/右抽屉) | 侧边抽屉面板 |
| `widgets/confirm_dialog.dart` | `public/scripts/templates/confirmDialog.html` | 通用确认弹窗 |
| `widgets/tag_filter.dart` | `public/scripts/filters.js` | 标签过滤组件 |
| `widgets/background_manager.dart` | `public/scripts/backgrounds.js` | 背景图管理 |
| `screens/group_chat/group_chat_screen.dart` | `public/scripts/group-chats.js` | 群聊管理 |

### Layer 2: 主动对话/情绪/记忆层 → 【对标来源：Muice-Chatbot】

| Solace 新模块 | Muice-Chatbot 来源文件 | 职责 |
|---|---|---|
| `services/proactive_scheduler.dart` | `Muice.py:create_a_new_topic()` | 主动对话调度器 |
| `services/emotion_memory_pool.dart` | `llm/faiss_memory.py` | 情绪记忆池 |
| `services/auto_prompt_switcher.dart` | `llm/llmtuner.py:auto_system_prompt()` | 场景化 Prompt 切换 |
| `models/proactive_config.dart` | `configs.yml:active.*` | 主动对话配置 |
| `models/scheduled_task.dart` | `configs.yml:active.shecdule.tasks[]` | 定时任务数据结构 |
| `models/emotion_memory_entry.dart` | `llm/faiss_memory.py` (文档结构) | 情绪记忆条目 |
| `prompts/general_system_prompt.dart` | `llm/llmtuner.py:GENERAL_SYSTEM_PROMPT` | 基础人设模板 |
| `prompts/special_system_prompts.dart` | `llm/llmtuner.py:SPECIAL_SYSTEM_PROMPTS` | 特殊场景模板 |
| `prompts/daily_system_prompt.dart` | `llm/llmtuner.py:DAILY_SYSTEM_PROMPT` | 日常问候模板 |
| `prompts/normal_system_prompt.dart` | `llm/llmtuner.py:NORMAL_SYSTEM_PROMPT` | 普通闲聊模板 |

### Layer 3: 后端服务/模型/存储层 → 【对标来源：KouriChat】

| Solace 新模块 | KouriChat 来源文件 | 职责 |
|---|---|---|
| `services/llm_service.dart` | `src/services/ai/llm_service.py` | 统一 LLM 请求接口 |
| `services/tts_service.dart` | `modules/tts/service.py` | TTS 语音服务 |
| `services/message_handler.dart` | `src/handlers/message.py` | 消息队列/分发/处理 |
| `services/auto_send_handler.dart` | `src/handlers/autosend.py` | 自动消息发送 |
| `repositories/database_service.dart` | `src/services/database.py` | 本地存储服务 |
| `repositories/avatar_manager.dart` | `src/avatar_manager.py` | 多角色账号管理 |
| `models/chat_context.dart` | `src/services/ai/llm_service.py` (chat_contexts) | 上下文窗口 |
| `models/llm_config.dart` | `data/config/__init__.py` (LLMSettings) | LLM 配置结构 |
| `models/app_config.dart` | `data/config/__init__.py` (Config) | 全局配置结构 |
| `models/reminder_task.dart` | `modules/reminder/service.py` (ReminderTask) | 提醒任务结构 |
| `services/reminder_service.dart` | `modules/reminder/service.py` | 提醒服务 |
| `services/content_generator.dart` | `modules/memory/content_generator.py` | 内容生成（日记/信/朋友圈等） |
| `services/emoji_service.dart` | `src/handlers/emoji.py` (EmojiHandler) | 情绪表情包匹配 |
| `services/embedding_service.dart` | `src/services/ai/embedding.py` | 向量嵌入服务 |

---

## 二、新项目目录结构

```
lib/
├── main.dart                          # 入口（对标 KouriChat main.py 启动编排）
├── config/
│   ├── app_config.dart                # 对标 KouriChat Config dataclass
│   ├── llm_config.dart                # 对标 KouriChat LLMSettings
│   └── proactive_config.dart          # 对标 Muice configs.yml:active
├── models/
│   ├── character_card_v2.dart         # 对标 SillyTavern v2CharData
│   ├── world_info_entry.dart          # 对标 SillyTavern WI 条目
│   ├── prompt_entry.dart              # 对标 SillyTavern PromptManager 条目
│   ├── chat_message.dart              # 对标 SillyTavern 消息结构
│   ├── chat_context.dart              # 对标 KouriChat chat_contexts
│   ├── emotion_memory_entry.dart      # 对标 Muice FAISS 文档结构
│   ├── scheduled_task.dart            # 对标 Muice time_topic
│   ├── reminder_task.dart             # 对标 KouriChat ReminderTask
│   └── llm_request.dart               # 对标 KouriChat LLM 请求/响应结构
├── repositories/
│   ├── database_service.dart          # 对标 KouriChat database.py
│   ├── character_repository.dart      # 角色 CRUD（对标 SillyTavern 角色操作）
│   ├── chat_repository.dart           # 聊天记录（对标 KouriChat 持久化）
│   ├── memory_repository.dart         # 记忆存储（对标 Muice FAISS + KouriChat memory）
│   ├── world_info_repository.dart     # 世界观存储（对标 SillyTavern world-info）
│   └── avatar_manager.dart            # 对标 KouriChat avatar_manager.py
├── services/
│   ├── llm_service.dart               # 对标 KouriChat llm_service.py
│   ├── tts_service.dart               # 对标 KouriChat tts/service.py
│   ├── message_handler.dart           # 对标 KouriChat handlers/message.py
│   ├── proactive_scheduler.dart       # 对标 Muice create_a_new_topic()
│   ├── emotion_memory_pool.dart       # 对标 Muice faiss_memory.py
│   ├── auto_prompt_switcher.dart      # 对标 Muice auto_system_prompt()
│   ├── world_info_engine.dart         # 对标 SillyTavern checkWorldInfo()
│   ├── content_generator.dart         # 对标 KouriChat content_generator.py
│   ├── emoji_service.dart             # 对标 KouriChat emoji.py
│   ├── reminder_service.dart          # 对标 KouriChat reminder/service.py
│   └── embedding_service.dart         # 对标 KouriChat embedding.py
├── prompts/
│   ├── general_system_prompt.dart     # 对标 Muice GENERAL_SYSTEM_PROMPT
│   ├── special_system_prompts.dart    # 对标 Muice SPECIAL_SYSTEM_PROMPTS
│   ├── daily_system_prompt.dart       # 对标 Muice DAILY_SYSTEM_PROMPT
│   └── normal_system_prompt.dart      # 对标 Muice NORMAL_SYSTEM_PROMPT
├── screens/
│   ├── chat/
│   │   ├── chat_screen.dart           # 对标 SillyTavern script.js 聊天主页面
│   │   └── chat_settings_screen.dart  # 对标 SillyTavern 聊天设置
│   ├── character/
│   │   ├── character_list_screen.dart # 对标 SillyTavern 角色列表
│   │   └── character_edit_screen.dart # 对标 SillyTavern #form_create
│   ├── settings/
│   │   ├── api_settings_screen.dart   # 对标 SillyTavern openai.js 设置
│   │   ├── prompt_manager_screen.dart # 对标 SillyTavern PromptManager.js
│   │   ├── world_info_screen.dart     # 对标 SillyTavern world-info.js
│   │   ├── instruct_mode_screen.dart  # 对标 SillyTavern instruct-mode.js
│   │   ├── system_prompt_screen.dart  # 对标 SillyTavern sysprompt.js
│   │   └── about_screen.dart
│   ├── group_chat/
│   │   └── group_chat_screen.dart     # 对标 SillyTavern group-chats.js
│   ├── memory/
│   │   └── memory_screen.dart
│   ├── moments/
│   │   └── moments_screen.dart
│   ├── shop/
│   │   └── shop_screen.dart
│   └── profile/
│       └── profile_screen.dart
├── widgets/
│   ├── message_bubble.dart            # 对标 SillyTavern #message_template
│   ├── message_actions.dart           # 对标 SillyTavern chats.js 操作
│   ├── swipe_handler.dart             # 对标 SillyTavern swipe_left/right
│   ├── drawer_panel.dart              # 对标 SillyTavern 抽屉面板
│   ├── tag_filter.dart                # 对标 SillyTavern filters.js
│   ├── confirm_dialog.dart            # 对标 SillyTavern confirmDialog.html
│   ├── background_manager.dart        # 对标 SillyTavern backgrounds.js
│   └── typing_indicator.dart
└── blocs/
    ├── chat/
    │   ├── chat_bloc.dart
    │   ├── chat_event.dart
    │   └── chat_state.dart
    ├── character/
    │   ├── character_bloc.dart
    │   ├── character_event.dart
    │   └── character_state.dart
    ├── theme/
    │   └── theme_bloc.dart
    └── auth/
        └── auth_bloc.dart
```

---

## 三、执行顺序（按依赖关系）

### Phase 1: 数据模型层（无依赖，先建）
1. `models/character_card_v2.dart` ← SillyTavern v2CharData
2. `models/world_info_entry.dart` ← SillyTavern WI 条目字段
3. `models/prompt_entry.dart` ← SillyTavern PromptManager 条目
4. `models/chat_message.dart` ← SillyTavern 消息结构
5. `models/chat_context.dart` ← KouriChat chat_contexts
6. `models/llm_request.dart` ← KouriChat LLM 请求/响应
7. `models/app_config.dart` ← KouriChat Config dataclass
8. `models/proactive_config.dart` ← Muice configs.yml:active
9. `models/scheduled_task.dart` ← Muice time_topic
10. `models/emotion_memory_entry.dart` ← Muice FAISS 文档
11. `models/reminder_task.dart` ← KouriChat ReminderTask

### Phase 2: 仓库层（依赖 Phase 1）
12. `repositories/database_service.dart` ← KouriChat database.py
13. `repositories/character_repository.dart` ← SillyTavern 角色操作
14. `repositories/chat_repository.dart` ← KouriChat 持久化
15. `repositories/memory_repository.dart` ← Muice FAISS + KouriChat memory
16. `repositories/world_info_repository.dart` ← SillyTavern world-info
17. `repositories/avatar_manager.dart` ← KouriChat avatar_manager

### Phase 3: 服务层（依赖 Phase 2）
18. `services/llm_service.dart` ← KouriChat llm_service.py
19. `services/tts_service.dart` ← KouriChat tts/service.py
20. `services/message_handler.dart` ← KouriChat handlers/message.py
21. `services/world_info_engine.dart` ← SillyTavern checkWorldInfo()
22. `services/proactive_scheduler.dart` ← Muice create_a_new_topic()
23. `services/emotion_memory_pool.dart` ← Muice faiss_memory.py
24. `services/auto_prompt_switcher.dart` ← Muice auto_system_prompt()
25. `services/content_generator.dart` ← KouriChat content_generator.py
26. `services/emoji_service.dart` ← KouriChat emoji.py
27. `services/reminder_service.dart` ← KouriChat reminder/service.py
28. `services/embedding_service.dart` ← KouriChat embedding.py
29. `prompts/*.dart` ← Muice llmtuner.py 模板

### Phase 4: BLoC 层（依赖 Phase 3）
30. `blocs/chat/chat_bloc.dart` + event + state
31. `blocs/character/character_bloc.dart` + event + state

### Phase 5: UI 层（依赖 Phase 4）
32-50. 所有 screens/ 和 widgets/ ← SillyTavern 前端逻辑

---

## 四、关键约束确认

- [ ] 每个文件开头标注【对标来源：XXX项目-XX模块】
- [ ] 不自创数据结构，1:1 保留参考项目字段
- [ ] 不自创提示词模板，原样翻译 Muice 模板
- [ ] 不简化功能，保留参考项目全部逻辑
- [ ] 不跨模块混用方案
- [ ] 冲突时优先级：SillyTavern > Muice > KouriChat
