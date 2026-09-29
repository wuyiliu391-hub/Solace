# Solace 虚拟手机图标包（AI 出图规范）

从 **应用图标** 开始做桌面主题时，统一按本规范出图，保证整套风格一致、可直接进 Flutter。

## 1. 技术规格（必须遵守）

| 项 | 要求 |
|----|------|
| 画布 | **1024 × 1024** px |
| 背景 | **透明**（不要烘焙壁纸） |
| 安全区 | 内容落在中心约 **88%**，四周留白 |
| 圆角 | **不要**在图里做 iOS 遮罩圆角；由 App 代码裁圆角 |
| 主体 | 3D 软粘土 / 玻璃拟态小物件，略微透视，居中 |
| 光影 | 左上柔光 + 底部轻投影（投影可画进图，透明度低） |
| 文字 | **图标内不要写中文/英文**（标签由代码显示） |
| 导出 | 先存 `assets/phone_icons/_master/{id}.png`，再导出 `generated/{id}.webp` 或 `.png`（建议 256 / 512） |
| 命名 | 必须与 `lib/config/phone_app_icons.dart` 里的 `id` 一致 |

落地路径：

```text
assets/phone_icons/
  _master/          # AI 原图 1024（可 gitignore 大图）
  generated/        # App 实际加载（提交这个）
    chat.webp
    wallet.webp
    ...
  README.md         # 本文件
```

App 读取：`assets/phone_icons/generated/{id}.webp`  
若文件不存在，UI 自动回退到 **玻璃渐变 + 临时图标**（见 `PhoneAppIcon`）。

## 2. 统一风格 Prompt（复制即用）

把 `{SUBJECT}` 换成下表「AI 主体描述」。

### 英文主 Prompt（推荐，出图更稳）

```text
App icon asset, single centered 3D soft clay / glassmorphism object: {SUBJECT}.
Pastel candy colors, glossy plastic and frosted glass materials, cute but premium.
Soft studio lighting from top-left, gentle ambient occlusion, subtle drop shadow under object.
Centered composition, large clear silhouette, no text, no letters, no numbers, no logo watermark.
Transparent background, PNG, 1024x1024, mobile UI icon, high detail, clean edges.
Style reference: iOS 3D soft UI icons, macaron palette, sky-blue friendly mood.
```

### 负面词

```text
text, letters, words, watermark, logo, frame, border, square mask, iOS squircle baked in,
busy background, photo realistic person face, clutter, multiple objects, lowres, blurry, noisy
```

### 中文辅助（给只吃中文的模型）

```text
手机应用图标，单个居中 3D 软粘土玻璃质感物件：{SUBJECT}。
马卡龙配色，果冻高光，磨砂玻璃，左上柔光，底部淡投影。
透明背景，无文字无水印，1024x1024，干净轮廓，适合 iOS 桌面图标。
```

## 3. 批量一致性技巧

1. **固定种子 + 固定风格前缀**：同一套先出 3 个样张定调，再批量。
2. **先出「钱包 / 消息 / 日记」** 做锚点，其余跟色。
3. 若某张过艳/过暗：只改 SUBJECT，不改风格段。
4. 后期统一：同样的描边强度、投影距离；可用 Photoshop/Photopea 批处理。
5. **商标风险**：电话/聊天气泡做成 Solace 原创造型，不要 1:1 复制微信绿标。

## 4. 图标清单（与代码 id 对齐）

| id | 桌面显示名 | AI 主体描述 {SUBJECT} | 优先级 |
|----|------------|------------------------|--------|
| chat | 消息 | pastel green speech bubbles, soft rounded | P0 |
| contacts | 通讯录 | soft blue address book with two people silhouettes | P0 |
| phone | 电话 | glossy green handset, soft 3D | P0 |
| settings | 设置 | silver frosted gear | P0 |
| memory | 纪念回忆 | pink calendar with heart | P0 |
| forum | 论坛 | blue people / community bubble | P1 |
| inspiration | 灵感 | glowing lightbulb warm yellow | P1 |
| guide | Shine指南 | pink book with sparkle (no brand text) | P1 |
| store | 应用商店 | gradient circle with three dots | P1 |
| wallet | 钱包 | green money bag with soft dollar mark shape (no text) | P0 |
| shop | 拾光购物 | pink shopping bag with heart | P0 |
| calendar | 小月历 | peach calendar with flower | P1 |
| oracle | 求签 | cute oracle stick / fortune tube oriental soft 3D | P1 |
| coins | 有钱花 | teal coins stack with upward arrow | P1 |
| destiny | 命运之书 | dark blue magical open book with stardust | P1 |
| diary | 秘密日记本 | pastel illustrated diary with flower garden | P0 |
| reading | 灵犀共读 | pink open book with two hearts | P1 |
| love_sign | 每日恋爱签 | pink cup with fortune sticks and hearts | P1 |
| love_lab | 恋爱人格研 | pink chemistry flask with heart liquid | P1 |
| power | 关闭手机 | soft red power button | P1 |
| moments | 动态 | pink camera / social feed card | P0 |
| notes | 备忘录 | yellow sticky notes stack | P0 |
| tarot | 塔罗 | mystical tarot card soft 3D | P1 |
| music | 音乐陪伴 | pastel headphones or music note jelly | P1 |
| story | 故事 | storybook with starry cover | P1 |
| map | 地图 | soft folded map pin | P2 |
| mailbox | 信箱 | pink envelope with heart seal | P1 |
| live2d | 形象 | cute avatar frame soft 3D | P2 |

## 5. 导出命令示例

有 `cwebp` 时可批量：

```bash
# 将 master 1024 压成 512 webp
for f in assets/phone_icons/_master/*.png; do
  id=$(basename "$f" .png)
  cwebp -q 90 -resize 512 512 "$f" -o "assets/phone_icons/generated/${id}.webp"
done
```

无 cwebp 时直接把 512 PNG 放进 `generated/`，扩展名改为 `.png`，并在 `PhoneAppIconCatalog` 里改 `ext`。

## 6. 验收清单

- [ ] 透明底，无灰底/白底
- [ ] 无文字
- [ ] 主体居中，四周留白
- [ ] 同套图标光影方向一致
- [ ] 在浅蓝壁纸上仍清晰
- [ ] 文件名 = 代码 `id`
- [ ] 在「图标预览页」检查过回退/加载

## 7. 与产品关系

- **主 App 桌面主题**：使用本图标包做启动器网格 + Dock  
- **看 TA 手机**：角色虚拟手机可复用同一套组件，内容仍走 `VirtualPhone` 数据  

先做齐 **P0** 再铺桌面壳；P1/P2 可占位玻璃图标。
