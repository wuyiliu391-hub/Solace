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
  latestVersion: '17.0.1',
  buildNumber: 278,
  minSdk: 23,
  releaseDate: '2026-07-08',
  downloadUrl: 'https://solace-auth.pages.dev/api/v1/download?v=17.0.1',
  changelog: [
    '修复导入备份失败问题',
    '底部导航栏新增小说功能',
  ],
  forceUpdate: false,
};

const ANNOUNCEMENTS = [
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
      if (path === '/api/v1/download') {
        const serverETag = `"apk-${VERSION_DATA.latestVersion}-${VERSION_DATA.buildNumber}"`;

        // ETag 缓存检查
        const ifNoneMatch = request.headers.get('If-None-Match');
        if (ifNoneMatch === serverETag) {
          return new Response(null, { status: 304 });
        }

        const gzReq = new Request(`${url.origin}/app-release.apk.gz?v=${VERSION_DATA.buildNumber}`, request);
        const gzRes = await env.ASSETS.fetch(gzReq);
        if (!gzRes.ok) return gzRes;

        const ds = new DecompressionStream('gzip');
        const streamed = gzRes.body.pipeThrough(ds);

        const headers = new Headers(COMMON_HEADERS);
        headers.set('Content-Type', 'application/vnd.android.package-archive');
        headers.set('Content-Disposition', `attachment; filename="Solace-${VERSION_DATA.latestVersion}.apk"`);
        headers.set('Cache-Control', 'public, max-age=3600');
        headers.set('ETag', serverETag);
        return new Response(streamed, { status: 200, headers });
      }

      // ==================== 静态资源处理 ====================

      const assetReq = new Request(request.url, request);
      const assetRes = await env.ASSETS.fetch(assetReq);

      if (assetRes.status === 404) {
        return new Response('404 — Not Found', { status: 404 });
      }

      if (isCacheableAsset(path)) {
        const resp = new Response(assetRes.body, assetRes);
        resp.headers.set('Cache-Control', 'public, max-age=86400, immutable');
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
