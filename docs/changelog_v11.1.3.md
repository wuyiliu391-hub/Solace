# v11.1.3 更新日志

**版本号**: 11.1.3 (Build 243)
**发布日期**: 2026-06-05

## 🛡️ 乱码污染隔离修复

- 新增固定失败乱码识别，拦截"刚才走神了，能再说一遍吗"的乱码形态
- 聊天上下文与角色记忆 prompt 注入前自动隔离历史乱码，不删除用户聊天记录
- 修复流式异常时 AI 气泡空白/消失、重新生成失败的问题
- Pure AI、普通聊天、重新生成、记忆引擎统一接入乱码防护链路

## 🌐 Chat2API 中转编码修复

- 修复 Chat2API 中转的 UTF-8 请求头与中文编码兼容问题
- 所有 adapter 统一添加 `charset=utf-8` 声明
- body parser 强制 UTF-8 编码

## 📋 技术细节

### 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `lib/utils/message_sanitizer.dart` | 新增 `isKnownFailureFallback()` / `failureFallbackText()`，流式 sanitize 拦截哨兵乱码 |
| `lib/blocs/chat/chat_bloc.dart` | 桥接层统一过滤历史乱码，流式显示防空气泡，保存前最终拦截，重新生成兜底 |
| `lib/blocs/pure_ai/pure_ai_chat_bloc.dart` | 流式显示防乱码，保存前拦截 |
| `lib/services/ai_service.dart` | 构建消息上下文时过滤历史中的乱码消息 |
| `lib/services/memory_engine.dart` | rolling summary / 相关记忆 / fallback 记忆统一过滤乱码 |
| `lib/services/pure_ai_service.dart` | Pure AI 历史消息过滤乱码 |
| `lib/repositories/local_storage_repository.dart` | 新增 `getPromptSafeChatMessages()` / `getPromptSafeMemories()` / `cleanupMojibakeMessages()` |
| `lib/utils/response_decoder.dart` | 增强 `_looksMojibake` GBK 特征字符检测 |

### 防护架构

```
请求 → 桥接层过滤(历史+记忆) → API调用 → 响应清洗 → 保存前拦截
                                                  ↓
                                            检测到乱码 → 重试/兜底
```

### 数据库说明

- 无数据库结构变更，无需迁移函数
- 旧乱码记录保留在数据库中，用户可正常查看
- AI prompt 链路自动隔离污染内容，不会传给模型
- 手动清理方法: `storage.cleanupMojibakeMessages()`
