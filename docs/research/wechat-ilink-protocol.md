# 微信 iLink Bot 协议（真实，逆向自腾讯官方插件）

> 来源：npm `@tencent-weixin/openclaw-weixin@2.4.6`（腾讯微信团队官方维护的 OpenClaw 渠道插件，2026-03 首发，2026-06-22 更新）。
> 取证方式：解包 tarball 读完整 TS 源码（src/api/api.ts、src/auth/login-qr.ts、src/auth/accounts.ts、src/messaging/send.ts、src/api/types.ts、src/api/session-guard.ts）。
> 宿主：OpenClaw（github.com/openclaw/openclaw，386k star 的个人 AI 助理网关）。插件文档：docs.openclaw.ai/channels/wechat。

## 概览

- 微信个人号接入，扫码登录 + 长轮询收消息 + HTTP 发消息。
- 支持私聊 + 媒体（图片/语音 SILK/文件/视频）；**不支持群聊**（插件 capability 只声明 direct chats）。
- 媒体走 CDN（`https://novac2c.cdn.weixin.qq.com/c2c`），AES-128-ECB 加密，上传需 getuploadurl 预签名。
- 账号 = 手机微信扫码并确认授权；凭证（bot_token）本地保存；支持多账号。

## 基础

- **Base URL**: `https://ilinkai.weixin.qq.com`（accounts.ts DEFAULT_BASE_URL；登录响应的 `baseurl` 字段可覆盖为账号专属域名）
- **CDN**: `https://novac2c.cdn.weixin.qq.com/c2c`
- 除 get_qrcode_status 为 GET 外，其余全部 POST + JSON。

### 请求头（所有接口）

| Header | 值 |
|---|---|
| Content-Type | application/json |
| AuthorizationType | 固定 `ilink_bot_token` |
| Authorization | `Bearer <bot_token>`（登录后才有） |
| X-WECHAT-UIN | base64( decimalString( random uint32 ) )，每请求随机 |
| iLink-App-Id | `"bot"`（来自 package.json 的 ilink_appid 字段） |
| iLink-App-ClientVersion | uint32 = major<<16 \| minor<<8 \| patch（如 2.4.6 → 0x020406） |

### 所有 POST body 附带

```json
"base_info": { "channel_version": "<客户端版本>", "bot_agent": "Name/Version" }
```
bot_agent 仅用于观测（类似 User-Agent），不参与鉴权；默认 `OpenClaw`。

## 登录

### 1. 获取二维码
`POST /ilink/bot/get_bot_qrcode?bot_type=3`
- body: `{ "local_token_list": ["<已有 token>", ...] }`（本地已登录账号 token，最多 10 个）
- resp: `{ "qrcode": "<会话ID>", "qrcode_img_content": "<URL>" }`
- `qrcode_img_content` 是要编码进二维码的 **URL 字符串**（插件用 qrcode-terminal 渲染它）。

### 2. 轮询扫码状态
`GET /ilink/bot/get_qrcode_status?qrcode=<qrcode>`（长轮询，客户端超时 35s，超时视作 wait 继续）
- resp: `{ "status": ..., "bot_token"?, "ilink_bot_id"?, "baseurl"?, "ilink_user_id"?, "redirect_host"? }`
- status 枚举：`wait | scaned | confirmed | expired | scaned_but_redirect | need_verifycode | verify_code_blocked | binded_redirect`
  - confirmed：带 bot_token + ilink_bot_id + ilink_user_id（扫码者 ID，应进白名单）+ baseurl
  - scaned_but_redirect：后续轮询切换到 redirect_host
  - binded_redirect：该 bot 已绑定过，本地旧凭证仍有效（视为成功）
  - need_verifycode：下次轮询附加 `&verify_code=<code>`
- 登录会话 TTL 5 分钟；二维码过期自动重新 get_bot_qrcode（最多 3 次）。

## 收消息（长轮询）

`POST /ilink/bot/getupdates`
- body: `{ "get_updates_buf": "<游标, 首次空串>", "base_info": {...} }`
- resp: `{ "ret": 0, "errcode"?, "errmsg"?, "msgs": [...], "get_updates_buf": "<新游标>", "longpolling_timeout_ms": 35000 }`
- 服务端 hold 到有新消息或超时；客户端超时建议 = longpolling_timeout_ms + 余量。
- **errcode -14 = token 过期**（session-guard：暂停一切调用 1 小时）。

### WeixinMessage（收发消息共用结构）

```
seq, message_id, from_user_id, to_user_id, client_id, create_time_ms,
session_id, group_id, message_type (1=USER, 2=BOT),
message_state (0=NEW, 1=GENERATING, 2=FINISH), item_list, context_token
```

### MessageItem

```
type: 1=TEXT 2=IMAGE 3=VOICE 4=FILE 5=VIDEO 11/12=tool_call
text_item: {text}
image_item: {media: CDNMedia, thumb_media, aeskey(hex16), ...}
voice_item: {media, encode_type(6=silk), text(语音转文字), ...}
file_item / video_item
ref_msg: 引用消息
```

### CDNMedia

`{ encrypt_query_param, aes_key(base64 AES-128), encrypt_type, full_url? }`

## 发消息

`POST /ilink/bot/sendmessage`（每个请求只带一个 item）
```json
{
  "msg": {
    "from_user_id": "",
    "to_user_id": "<目标>",
    "client_id": "<生成的消息ID>",
    "message_type": 2,
    "message_state": 2,
    "item_list": [{ "type": 1, "text_item": { "text": "内容" } }],
    "context_token": "<必回传, 从入站消息缓存>",
    "run_id": "<可选>"
  },
  "base_info": {...}
}
```
- resp: `{ "ret": 0, ... }`，ret != 0 视为失败。
- **context_token 关键**：入站消息带的会话令牌，回复必须回传；按 (账号, from_user_id) 缓存。

## 输入状态（拟人化）

1. `POST /ilink/bot/getconfig` body `{ ilink_user_id, context_token?, base_info }` → `{ ret, typing_ticket(base64) }`
2. `POST /ilink/bot/sendtyping` body `{ ilink_user_id, typing_ticket, status: 1|2, base_info }`（1=输入中, 2=取消）

## 生命周期

- `POST /ilink/bot/msg/notifystart` / `POST /ilink/bot/msg/notifystop`（body 仅 base_info）

## 媒体上传（getuploadurl）

`POST /ilink/bot/getuploadurl`
- body: `{ filekey, media_type(1图/2视频/3文件/4语音), to_user_id, rawsize, rawfilemd5, filesize(密文大小), thumb_*, no_need_thumb, aeskey, base_info }`
- resp: `{ upload_param, thumb_upload_param, upload_full_url? }`
- 流程：算明文 size/MD5 → AES-128-ECB 加密 → getuploadurl → PUT CDN → 用 encrypt_query_param 组 CDNMedia 放入 item_list。

## 对旧实现（Solace）的修正清单

| 项 | 旧（猜的） | 新（真实） |
|---|---|---|
| base url | ilink.weixin.qq.com / 本地 http | https://ilinkai.weixin.qq.com |
| 接口路径 | /api/v1/getUpdates 等驼峰 | /ilink/bot/getupdates 全小写 |
| 认证 | 仅 Bearer | + AuthorizationType + X-WECHAT-UIN + iLink-App-* 头 |
| 收消息 | GET + offset 数字游标 | POST + get_updates_buf 字符串游标，长轮询 35s |
| 二维码 | content 直接渲染 | qrcode_img_content 是 URL，要编码成 QR 图 |
| 扫码状态 | waiting/scanned/confirmed/expired | + scaned_but_redirect/need_verifycode/verify_code_blocked/binded_redirect |
| 发送 | {to, text} | msg{to_user_id, client_id, message_type:2, message_state:2, item_list, context_token} |
| typing | 直接 {to} | 先 getconfig 取 typing_ticket，再 sendtyping |
| 错误 | 401/403 | ret/errcode 字段；-14=token 失效（暂停 1h） |
| bot_type | 无 | get_bot_qrcode?bot_type=3 |
