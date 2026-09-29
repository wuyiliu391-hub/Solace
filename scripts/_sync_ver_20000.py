#!/usr/bin/env python3
"""Sync Solace version across the 5 required locations + HTML footers."""
from pathlib import Path

ROOT = Path(r"C:\Users\Administrator\Desktop\Solace")
VERSION = "20.0.0"
BUILD = "20000"
COMBO = f"{VERSION}+{BUILD}"

def write(path: Path, text: str):
    path.write_text(text, encoding="utf-8")
    print(f"OK {path.relative_to(ROOT)}")

# 1. pubspec.yaml
p = ROOT / "pubspec.yaml"
t = p.read_text(encoding="utf-8")
import re
t = re.sub(r"^version: .+$", f"version: {COMBO}", t, count=1, flags=re.M)
write(p, t)

# 2. constants.dart
p = ROOT / "lib/config/constants.dart"
t = p.read_text(encoding="utf-8")
t = t.replace("static const String version = '19.0.2';", f"static const String version = '{VERSION}';")
t = t.replace("static const int build = 10305;", f"static const int build = {BUILD};")
if "versionFeatureAck20000" not in t:
    t = t.replace(
        "static const String versionFeatureAck8304 = 'version_feature_ack_v8304';",
        "static const String versionFeatureAck8304 = 'version_feature_ack_v8304';\n"
        f"  static const String versionFeatureAck20000 = 'version_feature_ack_v{BUILD}';",
    )
write(p, t)

# 3. version.json
version_json = f'''{{
  "version": "{VERSION}",
  "build": {BUILD},
  "minSdk": 23,
  "forceUpdate": false,
  "releaseDate": "2026-09-15",
  "downloadUrl": "https://solace-auth-v2.pages.dev/api/v1/download?v={VERSION}",
  "changelog": [
    "大版本 20.0.0：统一单聊/群聊主题为暮玫深色与软纸浅色，告别角色混色背景",
    "新增存储管理：完整扫描本地占用，可清理语音模型、备份残留、聊天图片等",
    "新增全局 AI 消耗控制，可一键关闭后台/附带 LLM 调用",
    "聊天页内置模型快速切换；小手机主题与角色手机壁纸统一",
    "修复群聊长按菜单小屏无法滚动、记忆库不更新、收藏定位失败",
    "折叠重复角色；角色日记恢复入口并提高生成成功率",
    "法功能注入补全与海外模型适配；数据库 v74 自愈分支/世界书",
    "加固：Flutter 引擎运行时资源禁止清理，避免误删导致启动黑屏",
    "降压：精简娱乐与发现页高内存功能，拆分巨型服务文件"
  ],
  "announcement": "Solace 20.0.0 — 统一主题、存储管理、消耗控制与稳定性加固"
}}
'''
write(ROOT / "solace/version.json", version_json)

# 4. _worker.js
p = ROOT / "solace/_worker.js"
t = p.read_text(encoding="utf-8")
t = t.replace("latestVersion: '19.0.2',", f"latestVersion: '{VERSION}',")
t = t.replace("buildNumber: 10305,", f"buildNumber: {BUILD},")
t = t.replace("releaseDate: '2026-08-21',", "releaseDate: '2026-09-15',")
t = t.replace(
    "downloadUrl: 'https://solace-auth-v2.pages.dev/api/v1/download?v=19.0.1',",
    f"downloadUrl: 'https://solace-auth-v2.pages.dev/api/v1/download?v={VERSION}',",
)
old_changelog = """  changelog: [
    '修复内置 TTS 音色切换无效、切换后仍播放旧音色的问题',
    '修复角色消息重新生成失败、生成中断后无法恢复的问题',
    '修复主页联系人列表打开后不显示角色和聊天记录的问题',
    '新增微信「同步到聊天列表」开关，聊天记录默认与主列表隔离',
    '新增微信「连接记忆库」开关，用户可自主选择是否让 AI 读取记忆',
    '修复微信回复极慢（10分钟+）的问题，增加 90 秒超时保护',
    '修复多行输入框第二行文字被遮挡的问题',
  ],"""
new_changelog = f"""  changelog: [
    '大版本 {VERSION}：统一单聊/群聊主题为暮玫深色与软纸浅色',
    '新增存储管理：完整扫描本地占用并支持精细清理',
    '新增全局 AI 消耗控制',
    '聊天页内置模型快速切换；壁纸主题统一',
    '修复群聊菜单滚动、记忆库更新、收藏定位等问题',
    '加固引擎运行时资源保护，避免误删黑屏',
    '法功能海外模型适配；数据库 v74 自愈',
  ],"""
if old_changelog in t:
    t = t.replace(old_changelog, new_changelog)
else:
    # fallback regex
    t = re.sub(r"changelog: \[[\s\S]*?\],", new_changelog.strip() + ",", t, count=1)
write(p, t)

# 5. HTML footers and labels
html_files = list((ROOT / "solace").glob("*.html"))
for hf in html_files:
    t = hf.read_text(encoding="utf-8")
    orig = t
    t = t.replace("v19.0.2+8305", f"v{COMBO}")
    t = t.replace("v19.0.2+10305", f"v{COMBO}")
    t = t.replace("19.0.2+8305", COMBO)
    t = t.replace("19.0.2+10305", COMBO)
    t = t.replace("v19.0.2</b>", f"v{VERSION}</b>")
    t = t.replace("Solace 19.0.2", f"Solace {VERSION}")
    t = t.replace("下载 Solace 19.0.2", f"下载 Solace {VERSION}")
    t = t.replace("19.0.2 · 更新日志", f"{VERSION} · 更新日志")
    t = t.replace(">19.0.2<", f">{VERSION}<")
    if t != orig:
        write(hf, t)

# download.html changelog section rewrite
p = ROOT / "solace/download.html"
t = p.read_text(encoding="utf-8")
# replace the old 19.0.2 changelog block content items if still old
if "专注稳定" in t or "19.0.1 集中修复" in t:
    start = t.find("<!-- 更新日志 -->")
    end = t.find("<!-- CTA -->")
    if start != -1 and end != -1:
        new_block = f'''<!-- 更新日志 -->
    <section class="block" id="changelog" data-reveal>
      <div class="block-head">
        <span class="eyebrow">{VERSION} · 更新日志</span>
        <h2>统一主题，看清每一寸本地空间。</h2>
        <p class="lead">大版本：聊天视觉统一、存储可管可控、引擎误删加固。</p>
      </div>
      <div class="changelog">
        <div class="cl-item">
          <span class="cl-tag">主题</span>
          <p>单聊与群聊统一为「暮玫」深色与「软纸」浅色，不再按角色混色铺底；自定义背景图与微信皮肤不受影响。</p>
        </div>
        <div class="cl-item">
          <span class="cl-tag">存储</span>
          <p>新增完整本地存储扫描：语音模型、备份还原残留、聊天图片、数据库等按占用排序，可精细勾选清理。</p>
        </div>
        <div class="cl-item">
          <span class="cl-tag">消耗</span>
          <p>新增全局 AI 消耗控制，可一键关闭后台与附带 LLM 调用，省电省 token。</p>
        </div>
        <div class="cl-item">
          <span class="cl-tag">聊天</span>
          <p>聊天页内置模型快速切换；小手机主题与角色手机壁纸统一；折叠重复角色。</p>
        </div>
        <div class="cl-item">
          <span class="cl-tag">修复</span>
          <p>修复群聊长按菜单小屏无法滚动、记忆库不更新、收藏定位失败；日记入口恢复并提高生成成功率。</p>
        </div>
        <div class="cl-item">
          <span class="cl-tag">加固</span>
          <p>Flutter 引擎运行时资源禁止清理，避免误删导致启动黑屏；数据库 v74 自愈分支与世界书。</p>
        </div>
      </div>
    </section>

    '''
        t = t[:start] + new_block + t[end:]
        write(p, t)

# AGENTS.md version line
p = ROOT / "AGENTS.md"
t = p.read_text(encoding="utf-8")
t = t.replace(
    "- 当前版本：`19.0.1+8304`（Roadmap 目标 20.0.0「共生」）",
    f"- 当前版本：`{COMBO}`（20.0.0 维护向大版本；Roadmap「共生」主线另计）",
)
write(p, t)

print("DONE", COMBO)
