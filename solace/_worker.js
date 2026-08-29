// Solace Pages Worker — 处理 API 路由 + 静态文件服务
function versionCompare(v1, v2) {
  const p1 = (v1 || '0').split('.').map(Number);
  const p2 = (v2 || '0').split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const a = p1[i] || 0, b = p2[i] || 0;
    if (a > b) return 1;
    if (a < b) return -1;
  }
  return 0;
}

const VERSION_DATA = {
  latestVersion: '19.0.1',
  buildNumber: 8304,
  minSdk: 23,
  releaseDate: '2026-08-21',
  downloadUrl: 'https://solace-auth-v2.pages.dev/api/v1/download?v=19.0.1',
  changelog: [
    '修复内置 TTS 音色切换无效、切换后仍播放旧音色的问题',
    '修复角色消息重新生成失败、生成中断后无法恢复的问题',
    '修复主页联系人列表打开后不显示角色和聊天记录的问题',
    '新增微信「同步到聊天列表」开关，聊天记录默认与主列表隔离',
    '新增微信「连接记忆库」开关，用户可自主选择是否让 AI 读取记忆',
    '修复微信回复极慢（10分钟+）的问题，增加 90 秒超时保护',
    '修复多行输入框第二行文字被遮挡的问题',
  ],
  forceUpdate: false,
};

const ANNOUNCEMENTS = [
  {
    id: 'ann_1901',
    title: 'Solace 19.0.1 稳定性修复公告',
    content: `Solace 19.0.1+8304 稳定性修复公告

━━━━━━━━━ 本次修复 ━━━━━━━━━

🔊 语音与音色修复
修复内置 TTS 音色切换无效、切换后仍播放旧音色的问题；切换预置音色时自动清理内存缓存，确保新音色立即生效。

💬 聊天功能修复
修复角色消息重新生成失败、生成中断后无法恢复的问题；重新生成增加超时保护和异常恢复，避免卡死或消息丢失。
修复主页联系人列表打开后不显示角色和聊天记录的问题。

🤖 微信机器人优化
新增「同步到聊天列表」开关，微信聊天记录默认与主列表隔离，不再混在一起。
新增「连接记忆库」开关，用户可自主选择是否让微信 AI 读取 Solace 记忆库。
修复微信回复极慢（10分钟+）的问题，AI 生成增加 90 秒超时保护，typing 状态请求增加 5 秒超时。

✍️ 界面与体验
修复多行输入框第二行文字被遮挡的问题。
微信机器人设置页新增功能开关，支持明暗主题自适应。

感谢反馈，这个版本集中修了一批影响日常使用的稳定性问题。`,
    date: '2026-08-21',
    type: 'update',
  },
  {
    id: 'ann_1900',
    title: 'Solace 19.0.0 大版本更新公告',
    content: `Solace 19.0.0+6303 大版本更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🤖 微信 Bot 重磅上线
接入微信 iLink 协议，AI 角色可直接进驻真实微信对话：扫码登录后以前台服务长轮询收发消息，完整走记忆、人格与情感管线回复；支持「正在输入」状态、消息去重、单联系人冷却与每小时回复上限，token 失效自动暂停并提醒重新扫码；搭配全新 1:1 微信风格界面（会话、通讯录、发现、朋友圈与转账卡片），并以前台保活服务防止系统断网杀进程。

🧱 工程架构重构
拆分 main.dart、AI 服务、记忆引擎和本地存储仓库等大型文件，采用更清晰的模块与 part 组织方式，在保持对外接口兼容的同时降低维护复杂度。

🧪 测试体系补齐
新增 125+ 个测试用例，覆盖语音链路、朋友圈、小说和商店 BLoC。最近提交记录显示全量 555 个测试通过，工程回归更有底气。

🔎 联网搜索与占位实现治理
移除三处联网搜索占位 URL，统一接入 BingCnMcpService 真实抓取；补全 chat_screen_v2 的待办，并清理死代码和桩方法。

📞 语音通话持续强化
完善 VAD 自动断句、本地 STT、MiMo TTS、音色克隆、手动打字输入、通话记录和记忆沉淀；同时改善参考音频处理、超时、音频转换、内存上限与异常恢复。

📦 Android 单平台收敛
移除 Flutter Web 与 Windows runner，项目从本版本起聚焦 Android，减少无效平台维护面。

🧹 仓库与包体积治理
移除约 3.8MB 的冗余 sky.mp3，部署产物加入忽略规则，持续清理遗留入口和无效代码。

感谢你陪 Solace 走到 19.0.0。这个版本不只是在增加功能，也是在把基础打磨得更可靠。`,
    date: '2026-08-20',
    type: 'feature',
  },
  {
    id: 'ann_1810',
    title: 'Solace 18.1.0 更新公告',
    content: `Solace 18.1.0+2300 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

📞 实时语音通话
点击角色卡片上的通话按钮，开口即聊：本地 VAD 自动断句、本地转写、AI 用你的专属克隆音色逐句回答。

🎤 音色克隆与打字输入
支持录制/导入参考音频克隆角色音色；不方便说话时（或想悄悄说点别的）可随时切换到打字输入，AI 照样开口回答。

💭 通话记忆自动沉淀
通话内容静默整理进记忆库，AI 会记住你们聊过的事；聊天页只保留通话记录，不刷屏。`,
    date: '2026-08-18',
    type: 'update',
  },
  {
    id: 'ann_1801',
    title: 'Solace 18.0.1 更新公告',
    content: `Solace 18.0.1+294 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🐛 单聊消息丢失修复
修复长会话（超过 50 条）退出重进后最新回复消失的问题；同时修复删除/隐藏/收藏消息后更早历史塌缩、需要重新上滑才会出现的问题。

💬 群聊加载更多历史
群聊新增「上滑加载更多」，长群聊可完整回看更早消息，删除/编辑/撤回后不再塌缩列表。

✨ 状态栏纯文本
单聊状态栏移除固定表情，改为纯文本展示。`,
    date: '2026-08-14',
    type: 'update',
  },
  {
    id: 'ann_1800',
    title: 'Solace 18.0.0 更新公告',
    content: `Solace 18.0.0+293 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🎭 番外小剧场（平行会话层）
新增独立番外会话：主线与记忆完全隔离、互不污染，退出即 100% 原样切回主线。支持顶部横幅标识、一键退出、番外回看列表，粘贴 mufy 风格指令也能自动开番外。

🎨 发现页新角色
新增傲娇系、高冷系、奇幻系、猫娘等多个高趣味角色，支持分类标签分组与「新上架」角标。

💬 朋友圈闭环
角色现在记得自己发过、评论过、看到过的动态，并在聊天中自然承接；动态支持「不让谁看」名单，AI↔AI 互评设轮次上限防刷屏。

🤖 角色主动技能
新增关怀、亲密互动、故事推进、话题发起四类主动技能，统一走 Agent 网关并留审计记录。

🛡️ AI 拒绝/上下文污染根治
统一识别「我是AI助手」「有什么可以帮你的吗」等无拒绝动词的脱角色回复，历史、记忆、会话锚点、群聊总结全线过滤——换模型后不再被旧拒绝锁死。备用模型沿用角色人设，流式首字超时 30s→60s。

🐛 单聊稳定性
修复加载更多崩溃、重新生成取错上下文、hasMore 边界等一批逻辑 bug。

🗄️ 数据库孤儿数据治理
删除会话/角色改为自包含级联，首次启动自动清理历史残留的孤儿聊天记录与记忆。`,
    date: '2026-08-14',
    type: 'update',
  },
  {
    id: 'ann_1790',
    title: 'Solace 17.9.0 更新公告',
    content: `Solace 17.9.0+292 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🤖 Operit 设备 Agent 全链路强化
统一意图识别、工具规划、确定性路由、权限控制和真实执行反馈；新增电量、通知、进程、应用与工作区能力，失败时返回真实原因。

🎭 角色化设备反馈
设备操作完成后继续使用角色口吻反馈，同时保留剧情、关系和人设上下文。

🧠 单聊状态与关系体验
状态栏显示每轮实时情绪 emoji，点击放大图标可查看完整情绪、强度和当下内心想法；角色承诺、共同经历、关系边界和主动互动策略继续沉淀。

👁️ 隐藏状态区分
隐藏聊天与隐藏联系人完全分离，分别提供独立恢复入口；隐藏聊天不会隐藏联系人，也不会删除聊天记录。

🧹 功能收敛
清理废弃虚拟电话、旧 TTS、音色克隆、录音转写、Live2D、音乐陪伴、宠物和故事模块旧入口。`,
    date: '2026-08-09',
    type: 'update',
  },
  {
    id: 'ann_1780',
    title: 'Solace 17.8.0 更新公告',
    content: `Solace 17.8.0+291 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🧠 角色生命循环
角色的情绪不再只是一行展示。用户的话会改变持续情绪；角色回复后的内心状态也会被受限地归并，影响之后的语气、记忆和关系。

🤝 承诺成为共同经历
当你提到明天的考试、面试、答辩或其他近期事项，角色会保存这件事。在合适时间自然关心结果；你反馈“考完了”“没考好”后，它会沉淀成重要共同经历，而不是下一轮就忘记。

🧭 关系开始有边界
新增信任感、用户边界、未修复矛盾和最近重要经历。说“我不想谈了”会停止追问和主动打扰；道歉、冲突和分享脆弱时刻会在关系里留下不同后果。

🌙 主动联系有理由
主动消息现在先经过本地策略：用户开关、静默时段、冷却、每日上限、近期互动和用户要求的空间都会被尊重。模型不会绕过这些限制。

👤 内置作者角色升级
内置作者角色完成公开化人格升级，保留真实的价值与表达方式，同时不暴露现实姓名、地点或私密经历。作者资料与互动设置现已锁定。

🗄️ 本地数据升级
数据库升级至 v70，新增角色承诺和关系上下文持久化；备份、导入、清除和角色删除流程均已同步支持。`,
    date: '2026-08-06',
    type: 'update',
  },
  {
    id: 'ann_1770',
    title: 'Solace 17.7.0 更新公告',
    content: `Solace 17.7.0+290 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🛡️ 旧版本数据库自动修复
旧版本用户升级后，应用启动会自动检测并补齐缺失的数据库表和字段。即使历史迁移曾经中断，也会重新校验群聊相关结构，避免打开时报错。

💬 修复创建群聊失败
兼容旧版群聊表中的 participantIds、participantNames 以及无默认值 NOT NULL 字段，自动安全重建并保留旧数据。新建群聊和成员入场消息不再因旧表结构失败。

📚 群聊数据结构完整自愈
启动时自动确保群聊会话、消息、分支、摘要、公共事件记忆表存在，并补齐聊天分支、自动回复、按角色间隔、隐藏状态等字段。

🔁 群聊体验修复
修复成员不回复、AI 复读、群聊记忆回流、公共事件记忆、自动回复开关、铃铛静音和按角色接话间隔。

💬 单聊与角色手机修复
修复小说模式段落标点、自定义状态、永久记忆、书签跳转和角色手机自动更新；角色手机现在继承用户当前壁纸主题。

🌐 官网与启动体验
Android 启动页支持深浅色主题，官网 Bauhaus 主题和版本更新服务同步升级。`,
    date: '2026-08-04',
    type: 'update',
  },
  {
    id: 'ann_1744',
    title: 'Solace 17.4.4 紧急修复',
    content: `Solace 17.4.4+287 紧急修复

━━━━━━━━━ 本次更新 ━━━━━━━━━

🐛 商店数据库彻底修复
彻底解决 shop_items 表缺少 isCustom / createdAt 列时，自定义商品保存、商店初始化报 DatabaseException（no such column）崩溃的问题。

本次加固：
• 启动与进入商店时强制校验表结构（不依赖版本号是否已升过）
• 写入只按 PRAGMA 真实存在的列落库，杜绝整表 toMap 误写缺列
• ALTER 失败时自动重建表并迁移旧商品数据；极端情况硬重建后可重新灌种子
• 数据库版本升至 v64

建议尽快升级。老用户与新用户均兼容。`,
    date: '2026-07-26',
    type: 'fix',
  },
  {
    id: 'ann_1743',
    title: 'Solace 17.4.3 紧急修复',
    content: `Solace 17.4.3+286 紧急修复

━━━━━━━━━ 本次更新 ━━━━━━━━━

🐛 数据库兼容性修复
修复 shop_items 表在老版本升级时缺少 isCustom / createdAt 列，导致自定义商品保存、商店初始化写入时报 DatabaseException 崩溃的问题。

影响范围：
• 从 17.4.2 及以下版本升级的用户
• 曾经删除本地数据后重新安装的用户
• 旧版首次安装但未执行 v61 迁移的用户

本次为纯修复版本，无新增功能，建议尽快升级。`,
    date: '2026-07-25',
    type: 'fix',
  },
  {
    id: 'ann_1741',
    title: 'Solace 17.4.1 更新公告',
    content: `Solace 17.4.1+284 更新

━━━━━━━━━ 本次更新 ━━━━━━━━━

📚 记忆库
页面布局从力导向图谱样式回退至旧版卡片设计，同时升级整体 UI 视觉效果。

📖 小说模式
修复小说模式无法关闭的 Bug。

🛒 商店 & 朋友圈
商店模块正式投入运行，朋友圈互动功能完成对接连通。

🧠 记忆机制
实现不同角色之间聊天记忆互通。

👤 创建角色
修复创建角色失败问题。

💬 聊天体验
优化对话上下文记忆策略；修复单聊页面无法更换聊天背景的问题；修复发送消息界面卡死故障。

🤖 人设代词
解决角色代词性别混乱、多轮上下文记忆指代错乱问题。

🌐 网站资源
整体重新构建官网资源，采用蓝白主题，手机优先适配。`,
    date: '2026-07-24',
    type: 'update',
  },
  {
    id: 'ann_1740',
    title: 'Solace 17.4.0 更新公告',
    content: `Solace 17.4.0+283 大版本更新

━━━━━━━━━ 本次更新 ━━━━━━━━━

👥 聊天群
支持创建聊天群，多角色同时对话。

📊 状态栏
单聊页面顶部新增状态栏，实时显示 AI 在线/离线状态与自定义状态文案。

(( )) 动作描写
输入框新增 (( )) 快捷按钮，快速插入动作、神态描写括号，消息中自动渲染为斜体灰色。

💰 虚拟转账
新增 AI 虚拟转账功能，支持与 AI 角色互相转账金币。

📖 小说模式独立开关
每个聊天会话拥有独立的小说模式开关，三态循环（跟随全局→开启→关闭），不再全局统一。

🎉 朋友圈
新增朋友圈动态功能，AI 角色自动生成动态、互相互动。

🐛 Bug 修复
• 修复句号分句渲染 BUG：文本换行时双引号单独跑到另一行`,
    date: '2026-07-23',
    type: 'feature',
  },
  {
    id: 'ann_1731',
    title: 'Solace 17.3.1 更新公告',
    content: `Solace 17.3.1+282 小更新

━━━━━━━━━ 本次修复 ━━━━━━━━━

📚 记忆库
修复角色很多时「切换角色」列表无法下滑。

💬 单聊体验
• AI 已回复后用户消息正确显示「已读」
• 文本聊天亲密度恢复正常增长
• 缩短拟人等待，去掉犹豫假卡顿
• 修复首条消息卡在「等待中」需重发才回复

⚙️ 互动设置
修复保存后不生效：异步覆盖、部分项未落库、返回聊天未回写配置。`,
    date: '2026-07-20',
    type: 'fix',
  },
  {
    id: 'ann_1730',
    title: 'Solace 17.3.0 更新公告',
    content: `Solace 17.3.0+281 更新公告

━━━━━━━━━ 本次更新 ━━━━━━━━━

🎵 沉浸式一起听
新增沉浸式一起听模式，复刻网易云音乐样式，实现和AI角色同步听歌、聊天互动；角色可以根据播放的歌曲感知你的情绪状态。

🎨 主题改版
改版原先蓝白抖音‑风格主题，额外新增白‑灰色系主题，用户可在设置页面自由切换主题样式。

🧠 记忆库重构
对记忆库整体重构：抛弃旧版卡片布局，更换为现代化线条网状树杈结构；支持拖拽移动、缩放节点，点击卡片展开查看完整记忆详情。

🤖 Operit‑AI Agent
接入Operit‑AI Agent，获取设备自动化操控能力；页面底部导航栏增加自动化功能入口，前提是设备安装并且激活Shizuku。`,
    date: '2026-07-15',
    type: 'feature',
  },
  {
    id: 'ann_1710',
    title: 'Solace 17.1.0 更新公告',
    content: `Solace 17.1.0+279 更新公告\n\n━━━━━━━━━ 本次更新 ━━━━━━━━━\n\n🎨 自定义字体颜色\n用户现在可以自由选择对白字体颜色，入口在单聊页面右上角调色板按钮，点击即可打开模式与颜色面板。\n\n🔄 小说模式开关修复\n修复全新安装后小说模式默认为关闭导致对白全部显示为白色的问题，切换模式后立即生效。\n\n💬 气泡三点动态状态\n气泡下方的三点等待指示器改为动态状态文字显示：等待中…（请求发送中）→ 思考中…（AI正在思考）→ 流式输出。\n\n📝 字体颜色与旁白修复\n理论修复对白/旁白字体颜色异常问题，对白着蓝色、旁白保持白色，自定义颜色同步生效。\n\n🌐 联网搜索增强\n恢复并增强联网搜索能力，实际完全可用。修复搜索结果显示0结果、搜索意图识别不准确、部分角色不触发搜索等多个问题。`,
    date: '2026-07-09',
    type: 'feature',
  },
  {
    id: 'ann_1701',
    title: 'Solace 17.0.1 更新公告',
    content: `Solace 17.0.1+278 更新公告\n\n━━━━━━━━━ 本次更新 ━━━━━━━━━\n\n🔧 修复导入备份失败问题\n修复用户导入备份文件时崩溃的问题，数据恢复功能恢复正常。\n\n📚 底部导航栏新增小说功能\n底部导航栏新增小说入口，随时进入小说创作与阅读。`,
    date: '2026-07-08',
    type: 'fix',
  },
  {
    id: 'ann_1630_bugfix',
    title: 'Solace 16.3.0 更新公告',
    content: `Solace 16.3.0+276 更新公告\n\n━━━━━━━━━ 本次更新 ━━━━━━━━━\n\nBug 修复\n• 修复备份文件导入失败问题，数据恢复功能恢复正常\n• 理论修复动态输出思考内容问题，AI 回复时不再泄露思考过程\n\n代码优化\n• 移除所有图片生成与多模态相关代码（HF Space 到期暂时下线）\n• 清理冗余的模型管理、TFLite、图片分析等遗留代码\n• 整体代码结构优化，提升稳定性`,
    date: '2026-07-07',
    type: 'fix',
  },
  {
    id: 'ann_1603',
    title: '🧹 Solace 16.0.3 — 七项 Bug 修复',
    content: `Solace 16.0.3+264 版本更新公告\n\n━━━━━━━━━ 修复内容 ─────────────────────\n\n🧹 朋友圈动态 AI 思考过程泄露修复\n💬 消息发送反馈修复\n🔄 流式输出中断保护\n🤖 角色身份防泄露\n📭 空白回复兜底\n🌙 深色模式适配\n🌐 世界功能入口禁用`,
    date: '2026-06-25',
    type: 'fix',
  },
  {
    id: 'ann_1602',
    title: '💔 Solace 16.0.2 — 最后的版本',
    content: `这可能是维护的最后一个版本。`,
    date: '2026-06-17',
    type: 'fix',
  },
  {
    id: 'ann_1600',
    title: '🎉 Solace 16.0.0 — 大版本更新',
    content: `Solace 16.0.0+261 大版本更新公告\n\n━━━━━━━━━ 更新内容 ━━━━━━━━━\n\n⚠️ 历史公告说明\n本历史公告中涉及的视觉相关能力已在 16.2.0 暂时下线，请以最新公告为准。\n\n✨ 人生系统\n🏛️ 全新人生系统，数字生命拥有完整生命周期。\n📜 人生线时间线，记录角色每一个关键时刻。\n🧠 人格五因子动态演化，实时对比基线变化。\n📊 马斯洛需求层次可视化，洞察角色内心世界。\n🔮 身份认同、三观标签、情绪八维全面展示。\n⏳ 生命阶段自动推进，从婴儿到暮年全程陪伴。\n🌟 数字永生机制，角色可超越肉体永存于世。\n\n⚔️ 宫斗战 & AI 自主\n👑 宫斗战系统震撼登场，角色间明争暗斗。\n🤖 AI 自主系统全面升级，角色拥有独立社交能力。\n💬 角色间可互读聊天记录和记忆库。\n🤝 社交网络支持好友申请与关系建立。\n❤️ 朋友圈打通，角色间可互相点赞评论。\n💓 自主控制面板支持心跳监控与手动触发。\n\n🔧 系统优化\n👁 观察功能支持多角色自由切换。\n🌐 关系图谱修复空白，数据全面打通。\n🎂 角色年龄支持手动编辑。\n🐛 聊天页面修复 30 余处中文乱码。\n⚡ 清理冗余数据库代码，性能更优。\n\n⚠️ GPT 功能每日 9 点至次日凌晨可用。\n⚠️ 人生系统和宫斗战会消耗额外 Token。\n⚠️ 谨慎开启宫斗战，剧情不可预测。`,
    date: '2026-06-17',
    type: 'feature',
  },
  {
    id: 'ann_1501',
    title: '🔧 Solace 15.0.1 — 通讯录报错修复',
    content: `Solace 15.0.1+260 紧急修复\n\n⚠️ 本次为半成品版本补丁。\n\n━━━━━━━━━ 修复内容 ━━━━━━━━━\n\n🐛 通讯录角色打开报错\n修复 DatabaseException(no such column: sessionType) 错误。数据库迁移 v38：chat_sessions 新增 sessionType 列，创建 social_memories 表。\n\n⚠️ 半成品声明\n自主系统核心框架已搭建，部分社交功能仍在开发中。`,
    date: '2026-06-13',
    type: 'fix',
  },
  {
    id: 'ann_1500',
    title: '⚠️ Solace 15.0.0 — 自主系统（半成品）',
    content: `Solace 15.0.0+259 版本更新公告\n\n⚠️ 本次为半成品版本，自主系统核心框架已搭建，部分功能仍在开发中。\n\n━━━━━━━━━ 更新内容 ━━━━━━━━━\n\n🤖 自主系统（新功能）\n新增「自主」页面，作为底部导航栏第五个标签。自主控制面板：主开关、心跳状态、角色列表、手动触发、API统计、日志。\n\n🌐 社交网络\n角色间可互相读取聊天记录和记忆库。社交关系二级页面：关系网络、好友申请、社交动态。角色基于真实数据回答。\n\n💬 朋友圈打通\n评论和点赞正确写入 Moments 数据库，支持 AI 间互相评论点赞。手动立即触发测试功能。\n\n🔧 系统改进\nPersonaRule 自动生成，任务不再因缺少规则被静默驳回。DNS-over-HTTPS 支持，绕过 ISP 域名封锁。智谱 v4 API 端点兼容性修复。SSE 响应解析修复。\n\n❌ 移除内容\n移除 BT 病娇模式底部导航栏入口。`,
    date: '2026-06-13',
    type: 'feature',
  },
  {
    id: 'ann_1420',
    title: '🧠 Solace 14.2.0 — GLM-Z1-9B 内置模型 & 多模式调参',
    content: `Solace 14.2.0+258 版本更新公告\n\n━━━━━━━━━ 更新内容 ━━━━━━━━━\n\n🤖 新增第二内置模型\nGLM-Z1-9B（硅基流动 THUDM/GLM-Z1-9B-0414）加入内置模型列表，设置页一键切换。9B 推理模型，支持 thinking_budget 控制推理深度。\n\n⚙️ 多模式专属参数\n为 GLM-Z1-9B 针对 10+ 场景独立调参：普通聊天 temp=0.85、小说模式 thinking_budget=12288、朋友圈 temp=0.92、写信模式、反思、主动消息、语音通话、纯AI、群聊、论坛等，每个场景的温度/采样/惩罚/推理深度都经过优化。\n\n🎯 对话模板化修复\n角色身份声明移至 system prompt 最前面，删除"怎么了？""辛苦啦～""愿意跟我说说吗？"等硬编码模板，防止模型照抄客服话术。删除"你是一个AI陪伴助手"等覆盖性声明。\n\n🛡️ 内容泄露防护\n新增 internal_context XML 标签过滤，流式和非流式双路径防护。信件/朋友圈后端过滤增强，新增 sanitizeForContent 方法。\n\n📝 朋友圈/信件 max_tokens 放开\n不再硬编码限制，由供应商配置决定最大输出长度，解决话只说一半的问题。`,
    date: '2026-06-13',
    type: 'feature',
  },
  {
    id: 'ann_1410',
    title: '🔥 Solace 14.1.0 — 病娇操控 & 渲染性能重构',
    content: `Solace 14.1.0+257 版本更新公告\n\n━━━━━━━━━ 更新内容 ━━━━━━━━━\n\n🧠 病娇操控系统\nAI 现在能直接操控 APP！系统 prompt 注入权限指令，AI 在回复末尾输出 <BT_ACTION> 标签即可自动执行操作（切换主题、改备注、删消息等）。不依赖 function calling，所有模型通用。\n\n⚡ 渲染性能大重构\n彻底修复全屏波浪刷新问题。增加 buildWhen 增量刷新、AnimatedListItem Key 修复避免入场动画重复播放、删除冗余 setState、流式滚动 400ms 节流。现在收发消息如丝般顺滑。\n\n👤 新增病娇角色\n沈烬（病娇男）和温妤（病娇女）两位高阶角色上线，支持普通/暴戾双版本一键切换，四维欲望度进度条直观展示。\n\n🔄 角色创建入口重构\n消息页右上角 + 菜单改为「创建角色」和「发现角色」双入口，发现角色支持完整编辑后添加。10 个日常陪伴模板保留，入口统一迁至发现角色页。\n\n🔒 BT 模式暂时禁用\n底部导航栏灰显锁定，代码层完整保留。\n\n🤖 内置供应商切换\n从 Kimi-K2.6 替换为 NVIDIA Step-3.7-Flash（stepfun-ai/step-3.7-flash），双 API Key 轮询防 429 限流。`,
    date: '2026-06-12',
    type: 'feature',
  },
];

function cacheHeaders(ttl) {
  return { 'Cache-Control': `public, max-age=${ttl}, immutable` };
}

const COMMON_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...COMMON_HEADERS, 'Content-Type': 'application/json' },
  });
}

function html(content, status = 200) {
  return new Response(content, {
    status,
    headers: { ...COMMON_HEADERS, 'Content-Type': 'text/html; charset=utf-8' },
  });
}

function isCacheableAsset(path) {
  return /\.(css|js|svg|png|jpg|jpeg|gif|ico|woff2?|ttf|eot)$/i.test(path);
}

// ==================== 主入口 ====================

export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      const path = url.pathname;

      if (request.method === 'OPTIONS') {
        return new Response(null, { headers: COMMON_HEADERS });
      }

      // ==================== API 路由 ====================

      // 1. 版本检查
      if (path === '/api/v1/version') {
        const currentVer = url.searchParams.get('current') || '0';
        const currentBuild = parseInt(url.searchParams.get('build') || '0', 10);
        const verUpdate = versionCompare(currentVer, VERSION_DATA.latestVersion) < 0;
        const buildUpdate = currentBuild < VERSION_DATA.buildNumber;
        const hasUpdate = verUpdate || buildUpdate;
        const dynamicDownloadUrl = `${url.origin}/api/v1/download?v=${VERSION_DATA.latestVersion}`;
        const resp = json({ hasUpdate, ...VERSION_DATA, downloadUrl: dynamicDownloadUrl });
        // 缓存 10 分钟
        resp.headers.set('Cache-Control', 'public, max-age=600');
        return resp;
      }

      // 2. 公告列表
      if (path === '/api/v1/announcements') {
        const lastId = url.searchParams.get('after') || '';
        let result = ANNOUNCEMENTS;
        if (lastId) {
          const idx = ANNOUNCEMENTS.findIndex(a => a.id === lastId);
          result = idx >= 0 ? ANNOUNCEMENTS.slice(0, idx) : [];
        }
        return json({ announcements: result, total: ANNOUNCEMENTS.length });
      }

      // 3. 管理员统计
      if (path === '/api/v1/admin/stats') {
        return html(statsPage(VERSION_DATA));
      }

      // 4. APK 下载
      // deploy.sh 只上传 app-release.apk.gz 的分片（Pages 单文件 <25MiB，
      // 分片名为 app-release.apk.gz.aa / .ab / ...）。
      // 这里按片拼接 → 解压后返回原始 APK 字节流，避免客户端把 gzip 当 APK 安装。
      if (path === '/api/v1/download') {
        const serverETag = `"apk-${VERSION_DATA.latestVersion}-${VERSION_DATA.buildNumber}"`;
        const ifNoneMatch = request.headers.get('If-None-Match');
        if (ifNoneMatch === serverETag) {
          return new Response(null, { status: 304 });
        }

        // 按清单取分片（deploy.sh 生成 app-release.apk.gz.manifest，列出
        // .aa/.ab/... 分片名；不探测——Pages SPA 回退会让不存在路径返回
        // 200，探测会撞 Workers 单次调用 50 次子请求上限）
        const manifestRes = await env.ASSETS.fetch(
          `${url.origin}/app-release.apk.gz.manifest?v=${VERSION_DATA.buildNumber}`,
        );
        if (!manifestRes.ok) {
          return json({ error: 'APK manifest missing' }, 502);
        }
        let partNames = [];
        try {
          partNames = await manifestRes.json();
        } catch (e) {
          return json({ error: 'APK manifest invalid' }, 502);
        }
        // 读入内存拼接（不走 ReadableStream 构造器——Pages 项目未开
        // streams_enable_constructors 兼容旗标；约 50MB 数据在 128MB 限制内）
        const partResList = [];
        for (const name of partNames) {
          const partRes = await env.ASSETS.fetch(
            `${url.origin}/${name}?v=${VERSION_DATA.buildNumber}`,
          );
          if (!partRes.ok || !partRes.body) {
            return json({ error: `APK part missing: ${name}` }, 502);
          }
          partResList.push(partRes);
        }
        if (partResList.length === 0) {
          return json({ error: 'APK asset missing' }, 502);
        }
        // 以实际字节数为准（Content-Length 可能与实发长度不一致）
        const bufs = [];
        for (const partRes of partResList) {
          bufs.push(new Uint8Array(await partRes.arrayBuffer()));
        }
        const merged = new Uint8Array(
          bufs.reduce((n, b) => n + b.byteLength, 0),
        );
        let offset = 0;
        for (const buf of bufs) {
          merged.set(buf, offset);
          offset += buf.byteLength;
        }
        const gzBytes = merged;

        let body = new Response(gzBytes).body;
        try {
          // CF Workers 支持 DecompressionStream
          body = body.pipeThrough(new DecompressionStream('gzip'));
        } catch (e) {
          // 解压不可用时回退：返回 gzip 并标记 Content-Encoding，
          // 客户端 UpdateService 会再做 gzip 魔数检测解压。
          const headers = new Headers(COMMON_HEADERS);
          headers.set('Content-Type', 'application/vnd.android.package-archive');
          headers.set(
            'Content-Disposition',
            `attachment; filename="Solace-${VERSION_DATA.latestVersion}.apk"`,
          );
          headers.set('Content-Encoding', 'gzip');
          headers.set('Cache-Control', 'public, max-age=3600');
          headers.set('ETag', serverETag);
          return new Response(gzBytes, { status: 200, headers });
        }

        const headers = new Headers(COMMON_HEADERS);
        headers.set('Content-Type', 'application/vnd.android.package-archive');
        headers.set(
          'Content-Disposition',
          `attachment; filename="Solace-${VERSION_DATA.latestVersion}.apk"`,
        );
        headers.set('Cache-Control', 'public, max-age=3600');
        headers.set('ETag', serverETag);
        // 不设 Content-Encoding，body 已是原始 APK
        return new Response(body, { status: 200, headers });
      }

      // ==================== 静态资源处理 ====================

      const assetReq = new Request(request.url, request);
      const assetRes = await env.ASSETS.fetch(assetReq);

      if (assetRes.status === 404) {
        return new Response('404 — Not Found', { status: 404 });
      }

      if (isCacheableAsset(path)) {
        const resp = new Response(assetRes.body, assetRes);
        // HTML references versioned CSS, but keep direct CSS requests refreshable
        // so a deploy can never leave the browser on an old stylesheet.
        resp.headers.set(
          'Cache-Control',
          path.endsWith('.css')
              ? 'public, max-age=300, must-revalidate'
              : 'public, max-age=86400, immutable',
        );
        return resp;
      }

      return assetRes;
    } catch (err) {
      return json({ error: err.message }, 500);
    }
  },
};

// ==================== 管理后台页面 ====================

function statsPage(ver) {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solace 管理后台</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f5f5; color: #333; padding: 40px 20px; }
    .container { max-width: 600px; margin: 0 auto; }
    h1 { font-size: 24px; margin-bottom: 8px; }
    .subtitle { color: #666; margin-bottom: 24px; }
    .card { background: white; border-radius: 12px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 16px; }
    .card h2 { font-size: 14px; color: #999; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 12px; }
    .stat { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; font-size: 14px; }
    .stat:last-child { border-bottom: none; }
    .label { color: #666; }
    .value { font-weight: 600; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 12px; }
    .badge-update { background: #e3f2fd; color: #1565c0; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Solace Admin</h1>
    <p class="subtitle">当前版本信息</p>
    <div class="card">
      <h2>版本数据</h2>
      <div class="stat"><span class="label">版本</span><span class="value"> <strong>${ver.latestVersion}</strong> (build ${ver.buildNumber})<br></span></div>
      <div class="stat"><span class="label">发布日期</span><span class="value">${ver.releaseDate}</span></div>
      <div class="stat"><span class="label">最低 SDK</span><span class="value">${ver.minSdk}</span></div>
      <div class="stat"><span class="label">强制更新</span><span class="value">${ver.forceUpdate ? '是' : '否'}</span></div>
    </div>
    <div class="card">
      <h2>更新内容</h2>
      ${ver.changelog.map(item => `<div class="stat"><span class="label">•</span><span class="value">${item}</span></div>`).join('')}
    </div>
    <div class="card">
      <h2>公告 (${ANNOUNCEMENTS.length})</h2>
      ${ANNOUNCEMENTS.map(a => `<div class="stat"><span class="value"><span class="badge badge-update">${a.type}</span> ${a.title}</span></div>`).join('')}
    </div>
  </div>
</body>
</html>`;
}
