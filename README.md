# Solace

<p align="center">
  <img src="assets/app_icon.svg" width="120" alt="Solace Logo">
</p>

<p align="center">
  <strong>AI 陪伴应用 · 多角色聊天 · 情感记忆引擎 · 隐私优先</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-%3E%3D3.0.0-blue?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/Version-17.0.0-orange" alt="Version">
</p>

---

## 目录

- [简介](#简介)
- [功能特性](#功能特性)
- [技术架构](#技术架构)
- [快速开始](#快速开始)
- [项目结构](#项目结构)
- [配置说明](#配置说明)
- [构建与部署](#构建与部署)
- [数据库设计](#数据库设计)
- [贡献指南](#贡献指南)
- [作者心里话](#作者心里话)
- [许可证](#许可证)

---

## 简介

**Solace** 是一款基于 Flutter 的 AI 陪伴应用，支持多角色聊天、情感记忆引擎、人生模拟系统等功能。项目采用**隐私优先**的设计理念，所有用户数据纯本地存储，不依赖任何云端服务。

### 核心理念

- **隐私优先**：所有数据存储在本地 SQLite，不上传任何用户数据
- **多角色体验**：每个 AI 角色拥有独立的人格、记忆、情感系统
- **情感智能**：基于心理学模型的情感引擎，追踪角色动态情绪变化
- **记忆进化**：艾宾浩斯遗忘曲线驱动的记忆系统，角色会随时间成长

---

## 功能特性

### 🗣️ 多角色聊天

- 支持创建多个 AI 角色，每个角色拥有独立人设
- 流式/非流式双模式 AI 回复
- 多模型切换（OpenAI 兼容接口）
- 语音通话、语音消息、TTS 语音合成

### 🧠 情感记忆引擎

- **情感引擎**：7 种基础情绪（平静/开心/悲伤/愤怒/担忧/玩味/害羞），含强度衰减
- **记忆引擎**：基于艾宾浩斯遗忘曲线，自动提取/衰减/整合记忆
- **人格进化**：每 200 轮对话触发人格微调，核心锚点保护
- **亲密度系统**：0-100 级，每日上限，高级别减速，48 小时衰减

### 🏛️ 人生模拟系统

- 完整生命周期：婴儿 → 幼儿 → 童年 → 青年 → 中年 → 老年 → 暮年
- 人格五因子动态演化（开放性/尽责性/外向性/宜人性/神经质）
- 马斯洛需求层次可视化
- 人生事件时间线记录
- 数字永生机制

### 💬 社交系统

- AI 角色间自主社交（互读聊天记录、记忆库）
- 关系图谱可视化
- 朋友圈动态（AI 自动生成、互相点赞评论）
- 群聊支持（酒馆模式）

### 🎨 其他功能

- 心情日记、塔罗牌、幸运转盘
- 虚拟地图（AI 位置模拟）
- 商店系统（虚拟商品、订单追踪）
- 纯 AI 聊天模式（通用问答）
- 本地文件导入/导出备份

---

## 技术架构

### 技术栈

| 层级 | 技术 |
|------|------|
| 框架 | Flutter 3.x / Dart >=3.0.0 |
| 状态管理 | BLoC (flutter_bloc) |
| 数据存储 | SQLite (sqflite) / SharedPreferences |
| AI 接口 | OpenAI 兼容 API |
| 语音 | record + flutter_tts |
| 图片 | image_picker + image_cropper |

### 架构模式

```
┌─────────────────────────────────────────────┐
│                   UI 层                      │
│  Screens → BlocBuilder → State              │
├─────────────────────────────────────────────┤
│                 BLoC 层                      │
│  Event → Bloc → State (Emitter 模式)        │
├─────────────────────────────────────────────┤
│                Service 层                    │
│  AIService / MemoryEngine / EmotionEngine   │
│  BackgroundScheduler / WorldEngine          │
├─────────────────────────────────────────────┤
│              Repository 层                   │
│  LocalStorageRepository (唯一数据访问点)     │
├─────────────────────────────────────────────┤
│                数据层                        │
│  SQLite (solace.db) / SharedPreferences     │
└─────────────────────────────────────────────┘
```

### 核心服务

| 服务 | 职责 |
|------|------|
| `AIService` | 构建 prompt（含记忆/情感/亲密/场景上下文），调用 AI API |
| `MemoryEngine` | 从对话提取记忆，构建关系画像，按上下文检索相关记忆 |
| `EmotionEngine` | 追踪角色动态情感，含强度衰减和情绪记忆 |
| `WorldEngine` | 全生命周期数字生命世界引擎 |
| `BackgroundScheduler` | AI 主动消息（基于性格、亲密等级、沉默时长） |
| `PersonaEvolutionService` | 人设进化服务（每 200 轮触发） |

---

## 快速开始

### 环境要求

- Flutter >= 3.0.0
- Dart >= 3.0.0
- Android Studio / VS Code
- Android SDK (API Level >= 23)

### 安装

```bash
# 克隆仓库
git clone https://github.com/your-username/solace.git
cd solace

# 安装依赖
flutter pub get

# 运行调试版本
flutter run
```

### 配置 AI 服务

Solace 使用 OpenAI 兼容的 API 接口。首次运行后，在 **设置 → AI 配置** 中填写：

1. **API Base URL**：你的 AI 服务端点
2. **API Key**：你的 API 密钥
3. **Model Name**：模型名称（如 `gpt-4o`）

支持的内置模型：
- NVIDIA Step-3.7-Flash（需配置 NVIDIA API Key）
- SiliconFlow GLM-Z1-9B（需配置 SiliconFlow API Key）

---

## 项目结构

```
solace/
├── lib/                              # Dart 源码
│   ├── main.dart                     # 入口文件，初始化链
│   ├── blocs/                        # BLoC 状态管理
│   │   ├── auth/                     # 认证 BLoC
│   │   ├── chat/                     # 聊天 BLoC
│   │   ├── group_chat/               # 群聊 BLoC
│   │   ├── memory/                   # 记忆 BLoC
│   │   ├── moments/                  # 动态 BLoC
│   │   ├── pure_ai/                  # 纯 AI 聊天 BLoC
│   │   ├── shop/                     # 商店 BLoC
│   │   └── theme/                    # 主题 BLoC
│   ├── config/                       # 配置文件
│   │   ├── constants.dart            # 常量、版本号
│   │   ├── business_rules.dart       # 业务规则
│   │   └── app_config.dart           # 环境配置
│   ├── data/                         # 静态数据（角色模板等）
│   ├── models/                       # 数据模型（60+ 文件）
│   ├── repositories/                 # 数据仓库层
│   ├── screens/                      # UI 页面
│   │   ├── auth/                     # 认证页面
│   │   ├── chat/                     # 聊天页面
│   │   ├── character/                # 角色管理
│   │   ├── discover/                 # 发现页面
│   │   ├── group_chat/               # 群聊页面
│   │   ├── map/                      # 虚拟地图
│   │   ├── memory/                   # 记忆页面
│   │   ├── moments/                  # 动态页面
│   │   ├── profile/                  # 个人中心
│   │   ├── settings/                 # 设置页面
│   │   ├── shop/                     # 商店页面
│   │   └── world/                    # 人生系统
│   ├── services/                     # 业务服务（100+ 文件）
│   ├── utils/                        # 工具函数
│   └── widgets/                      # 可复用组件
├── android/                          # Android 平台代码
├── web/                              # Web 平台代码
├── windows/                          # Windows 平台代码
├── assets/                           # 静态资源
├── test/                             # 测试代码
├── solace/                           # Cloudflare Pages 部署文件
│   ├── _worker.js                    # Worker（版本检查、公告）
│   └── version.json                  # 版本信息
└── pubspec.yaml                      # Flutter 配置
```

---

## 配置说明

### 版本号同步

发布新版本时，以下 5 个文件的版本号必须保持一致：

| 文件 | 位置 |
|------|------|
| `pubspec.yaml` | `version: x.x.x+xxx` |
| `lib/config/constants.dart` | `AppVersion.version` / `AppVersion.build` |
| `lib/screens/settings/about_screen.dart` | 引用 `AppVersion` |
| `solace/version.json` | `version` / `build` |
| `solace/_worker.js` | `VERSION_DATA.latestVersion` / `buildNumber` |

### 数据库迁移

数据库版本迁移代码位于 `lib/repositories/local_storage_repository.dart` 的 `_onUpgrade` 方法中。每次修改数据库结构时：

1. 在 `_onUpgrade` 中添加迁移函数
2. 在 `expectedColumns` 中声明新列
3. 在 `createMissingTable` 中添加新表（如果是新表）

---

## 构建与部署

### 构建 Release APK

```bash
flutter build apk --release --target-platform android-arm64 --no-shrink
```

### 部署到 Cloudflare Pages

```bash
# 设置 Token
export CLOUDFLARE_API_TOKEN="your-token"

# 一键部署
bash deploy.sh
```

部署脚本自动完成：复制 APK → gzip 压缩 → 上传到 Cloudflare Pages。

### ADB 安装

```bash
# 覆盖安装（保留数据）
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 数据库设计

当前数据库版本：**v36**，包含 15+ 张表：

| 表名 | 用途 |
|------|------|
| `users` | 用户信息 |
| `ai_characters` | AI 角色配置 |
| `ai_configs` | AI 模型配置 |
| `chat_sessions` | 聊天会话 |
| `chat_messages` | 聊天消息 |
| `memories` | 记忆数据（含艾宾浩斯权重） |
| `moments` | 朋友圈动态 |
| `group_chat_sessions` | 群聊会话 |
| `ai_wallets` | AI 钱包 |
| `shop_orders` | 商店订单 |
| `sticker_packs` | 贴纸包 |
| `ai_letters` | 信件系统 |

---

## 贡献指南

欢迎贡献代码、报告问题或提出建议。

### 提交规范

- 使用简体中文编写提交信息
- 格式：`类型: 简短描述`
- 类型：`feat` / `fix` / `refactor` / `docs` / `style` / `test` / `chore`

### 代码规范

- 单引号 (`prefer_single_quotes`)
- 尽量使用 `const` 构造函数
- 不可变集合使用 `const`
- UI 文本、注释均为简体中文

### 开发流程

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -m 'feat: 添加某功能'`
4. 推送分支：`git push origin feature/your-feature`
5. 创建 Pull Request

---

## 作者心里话

我是一个 17 岁的高中生。

一个月时间，从零开始，写出了 Solace。

做这个项目的初衷很简单：市面上的 AI 陪伴软件，要么收费离谱，要么功能阉割，要么数据不安全。我不想再看到有人为了一个聊天功能被割韭菜。

Solace 从第一天起就是免费的，以后也是。

所有数据存在你自己的手机里，不上传任何服务器。你的聊天记录、你的角色、你的回忆，只属于你自己。

我知道这个项目还有很多不完美的地方。代码可能不够优雅，架构可能不够完美，Bug 也可能不少。但它是一个 17 岁少年能拿出的全部诚意。

如果你觉得 Solace 还不错，给个 Star 就够了。

如果你觉得哪里不好，提 Issue，我改。

---

## 许可证

本项目采用 [MIT License](LICENSE) 开源。

---

<p align="center">
  <sub>Made with ❤️ by a 17-year-old developer</sub>
</p>
