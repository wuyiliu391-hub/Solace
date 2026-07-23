# Live2D 崽崽素材说明

## 目录结构

所有素材均内置，用户不直接上传文件。按部位分类，每个变体一张 PNG。

```
assets/live2d/variants/
  bodies/
    default.png      # 默认体型
    slim.png         # 纤细体型
    chibi.png        # Q 版体型
  heads/
    default.png
    round.png
    sharp.png
  faces/
    default.png      # 默认肤色
    pale.png         # 白皙
    tan.png          # 小麦色
    cool.png         # 偏冷色调
  hair_front/
    bob.png
    long.png
    short.png
    bangs.png
    twin_tails.png
  hair_back/
    bob.png
    long.png
    short.png
    twin_tails.png
  eyebrows/
    default.png
    thick.png
    thin.png
    curved.png
    flat.png
  eyes/
    default.png
    round.png
    slim.png
    doe.png
    sleepy.png
  mouths/
    default.png
    smile.png
    frown.png
    open.png
    pout.png
    surprise.png
  shirts/
    default.png
    sailor.png
    hoodie.png
    uniform.png
    dress.png
  pants/
    default.png
    skirt.png
    jeans.png
    shorts.png
  accessories/
    cat_ears.png
    glasses.png
    ribbon.png
    hat.png
```

## 素材规范

1. **尺寸统一**：所有 PNG 建议 512x512 或 1024x1024，透明背景
2. **锚点居中**：素材中心点对齐人物中心，避免换装错位
3. **分层顺序**：从后到前：body → pants → shirt → head → hair_back → face → eyebrows → eyes → mouths → eye_shadow → blush → hair_front → accessory
4. **命名规范**：部位目录名 + 变体文件名（不含扩展名）= 代码中的变体 ID

## 化妆与捏脸

- 肤色/发色/瞳色/唇色/腮红/眼影 通过代码 ColorFilter 覆盖，不依赖素材
- 脸部参数（眼距、眼大小、嘴大小等）通过渲染时矩阵变换实现

## 如何添加新变体

1. 在对应目录放入 PNG
2. 在 `lib/models/avatar/avatar_renderer.dart` 的 `AvatarAssets.variants` 中追加变体 ID
3. 管理页面会自动显示新选项
