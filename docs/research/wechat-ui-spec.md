# 微信聊天界面逆向规格（刷圈兔仿微信 App 逆向）

> 来源：`C:\Users\Administrator\Desktop\逆向工具\shuaquantu_dec`（apktool 解包）+ `shuaquantu_jadx`（jadx 反编译）
> 刷圈兔（com.jiangsu.shuaquanwang）内置仿微信聊天模块（cn.wsjtsq.wchat_simulator），
> 颜色/几何大量取自真实微信资源。本文档提炼其"真实微信聊天界面规格"供 Solace 微信皮肤对照。

## 一、聊天页面

```
背景色            #EDEDED（App 内为 #EAEAEA，微信实为 #EDEDED）
导航栏            高 ~44dp + 状态栏；底色 #EDEDED；底部 0.5dp 分隔线 #D6D6D6
标题              17sp #111111 居中；返回箭头 24×24dp 左侧
输入栏            总高 ~53dp（含上下 padding 6dp），背景 #F7F7F7，顶部 0.5dp 分隔线 #D6D6D6
扩展面板          高 ~260dp，背景 #F7F7F7，tab 行 44dp
```

## 二、消息气泡

| 项目 | 值 |
|---|---|
| 头像 | **40×40dp 正圆**（circle clip，不是圆角矩形），无描边 |
| 头像边距 | 左右 10dp；气泡与头像间距 8dp |
| 气泡圆角 | 4-6dp，角部小尖 2-3dp（**尖在气泡上端**指向头像） |
| 气泡内边距 | H: 12dp，V: 8dp（17sp 字时） |
| 气泡最大宽度 | 屏宽 × 0.62 左右 |
| 文字字号 | 17sp（标准），行高 1.35，行距 2-3px |
| 文字颜色 | 发送 **#0E2206** / 接收 **#333333** |
| 气泡颜色 | 发送 **#95EC69** / 接收 **#FFFFFF** |
| 时间戳 | 居中，8-9sp #B2B2B2，背景胶囊 #E6E6E6 圆角 4dp，上下 14dp 间距 |
| 系统消息 | 居中 12sp #AFAFAF（"拍了拍" 12sp 加粗 #6A6A6A） |

## 三、语音消息

- 语音条宽：60dp(1s) ~ 250dp(60s)，高 38dp，圆角同气泡
- 时长文字 14sp，条外侧；未读红点 8×8dp #FA5151

## 四、会话列表

| 项目 | 值 |
|---|---|
| 行高 | ~64dp，背景 #FFFFFF |
| 头像 | 40×40dp 正圆，左边距 12dp |
| 昵称 | 17sp #111111；最后消息 14sp #999999，marginTop 3dp |
| 时间 | 12sp #B2B2B2 右对齐，右边距 12dp |
| 未读红点 | 16×16dp 起 #FA5151，白字 10sp，右上角叠加 1.5dp 白描边 |
| 分隔线 | 0.5dp #E5E5E5，缩进 62dp（12+40+10） |

## 五、颜色体系（wx_* 全部）

| 用途 | 值 |
|---|---|
| 聊天页/全局背景 | #EAEAEA（微信实为 #EDEDED） |
| 输入栏背景 | #F5F5F5 |
| 输入框背景 | #FFFFFF，圆角 3dp（微信 5-6dp） |
| 气泡绿 | #95EC69 |
| 发送文字 | #0E2206 |
| 接收文字 | #333333 |
| 会话摘要/时间 | #ACACAC |
| 标题栏细线 | #E1E1E1 |
| 输入框分割线 | #CCCCCC |
| 标题文字 | #101010 |
| 副标题 | #909090 |
| 灰字 | #7F7F7F |
| 未读红 | #F95151 |
| 系统消息 | #888888 |
| 微信绿(按钮) | #2AAE67 / #08C261，选中 #0C9253 |
| 底部导航 | #F6F6F6，选中 #4CD489 |
| 列表背景 | #FFFFFF |
| 会话页标题栏 | #EEEEEE |

## 六、输入栏细节

- 图标全部 22×22dp（点击域更大），左右间距 8-10dp
- 输入框高 ~38dp，白底圆角 5dp，左右 padding 10dp，17sp
- 语音按钮图标 `ic_wx_chat_footer_voice`，表情 `ic_wx_chat_footer_sticker`，加号 `ic_wx_chat_footer_add`
- 发送按钮 48×25dp 白字 14dp 绿底

## 七、聊天背景切换（已支持）

- 内置 9 张背景 wx_chatbg_big_01~09 + 相册选图
- 3 列 Grid 选择，168dp 高每项，centerCrop
- 背景存在时系统消息底色 #80FFFFFF 半透明白

## 八、刷圈兔自编/偏差（Solace 应避免）

1. **头像圆角错**：用圆角矩形（微信是正圆）
2. **气泡圆角过大不对称**：白泡 12px+、绿泡 20px（微信 4-6dp，尖在顶端）
3. **时间戳裸文字无胶囊**（微信是 #E6E6E6 胶囊背景）
4. **输入框圆角 3dp**（微信 5-6dp）
5. **会话行高 69.6dp**（微信 64dp）
6. **字号用 dp 不随系统缩放**（微信跟随系统，Flutter 用 sp）
7. **红点无白描边**（微信有 1.5dp 白描边）

## 九、Flutter 实现要点（对照 Solace）

- 头像：正圆裁剪（WeChatAvatar 已实现圆形）
- 气泡：圆角 5dp 统一，右下 3dp 小尖可用 CustomPainter
- 时间戳：居中胶囊（#E6E6E6 底、8-9sp、圆角 4dp）
- 输入栏：53dp 高、图标 22-28dp
- 字号用 sp 语义（Flutter textScaler）
- 会话列表：64dp 行高、40dp 正圆头像、62dp 分割线缩进、红点白描边

## 相关文件索引

- 聊天布局：`shuaquantu_dec\res\layout\activity_chatmsg.xml`、`item_msg.xml`、`item_main_chat.xml`
- 气泡 9-patch：`shuaquantu_dec\res\drawable-xxhdpi\sdbnm_new.9.png`（绿）、`sdbnmm_new.9.png`（白）
- 颜色：`shuaquantu_dec\res\values\colors.xml`（wx_* 前缀）
- 背景切换：`shuaquantu_jadx\sources\cn\wsjtsq\wchat_simulator\activity\chat\BgSelectActivity.java`
- 气泡适配：`...\adapter\ChatMsgAdapter.java`
- 输入栏：`...\activity\chat\ChatMsgActivity.java`
- 时间格式：`...\utils\TimeUtils.java`（getChatNromalTimestampString）