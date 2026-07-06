# v15.0.0 更新日志 ⚠️ 半成品

**版本号**: 15.0.0 (Build 259)
**发布日期**: 2026-06-13

> ⚠️ **注意**: 本次更新为半成品版本，部分功能仍在开发中，可能存在不稳定或未完成的特性。

---

## 🤖 自主系统 (新功能)

- 新增"自主"页面，作为底部导航栏第五个标签
- 自主控制面板：主开关、心跳状态、角色列表、手动触发、API统计、日志
- 角色间可互相读取聊天记录和记忆库
- 社交关系二级页面：关系网络、好友申请、社交动态
- 角色基于真实数据回答（支持撒谎但必须知道真实信息）
- 手动立即触发测试功能（朋友圈评论、点赞、串门、加好友）
- 评论和点赞正确写入 Moments 数据库

## 🌐 网络优化

- 新增 DNS-over-HTTPS 支持，绕过 ISP 域名封锁
- 智谱 v4 API 端点兼容性修复（不再强制追加 `/v1`）
- SSE 响应解析修复，正确处理 `data: [DONE]` 标记

## 🔧 系统改进

- PersonaRule 自动生成，任务不再因缺少规则被静默驳回
- 移除 BT 病娇模式底部导航栏入口
- 移除设置页面的新世界模式开关

## 📋 技术细节

### 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `lib/screens/autonomous/autonomous_screen.dart` | 自主控制面板 |
| `lib/screens/autonomous/social_relations_page.dart` | 社交关系页面 |
| `lib/services/core_hub.dart` | PersonaRule 自动生成 |
| `lib/services/social_action_executor.dart` | 朋友圈评论/点赞写入 Moments |
| `lib/services/social_scheduler_service.dart` | 社交调度优化 |
| `lib/utils/doh_client.dart` | DNS-over-HTTPS 客户端 |
| `lib/utils/response_decoder.dart` | SSE 解析修复 |
| `lib/screens/settings/ai_config_screen.dart` | DoH 集成 |
| `lib/services/llm_service.dart` | DoH 集成 |
| `lib/main.dart` | 导航栏更新 |
| `lib/screens/profile/settings_screen.dart` | 移除新世界模式 |

### 已知问题

- 社交关系数据展示可能需要更多优化
- 部分手动触发功能可能不稳定
- 自主页面 UI 需要进一步打磨

---

**⚠️ 半成品声明**: 本次更新包含大量新功能，但部分特性尚未完全成熟。建议用户谨慎使用自主系统相关功能，遇到问题请及时反馈。
