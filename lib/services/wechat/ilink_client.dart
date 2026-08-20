import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';

/// iLink 协议异常。
///
/// 与 OpenClaw 官方插件行为对齐：HTTP 4xx/5xx、ret != 0、errcode != 0 均抛异常。
/// [isStaleToken] 对应 errcode -14（token 失效，官方语义：暂停调用 1 小时）。
class IlinkException implements Exception {
  final String message;
  final int? statusCode;
  final int? errcode;
  const IlinkException(this.message, {this.statusCode, this.errcode});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  /// token 过期/失效（iLink errcode -14）
  bool get isStaleToken => errcode == IlinkClient.errcodeStaleToken;

  @override
  String toString() =>
      'IlinkException(http=$statusCode, errcode=$errcode): $message';
}

/// 扫码登录状态（完整枚举，对齐官方插件 StatusResponse）。
enum IlinkQrStatus {
  wait, // 等待扫码
  scanned, // 已扫码待确认（官方拼写 scaned）
  confirmed, // 已确认，拿到 bot_token
  expired, // 二维码过期
  scannedButRedirect, // IDC 重定向：切换 redirectHost 继续轮询
  needVerifyCode, // 需要输入验证码
  verifyCodeBlocked, // 验证码被风控
  bindedRedirect, // 已绑定过本实例，本地凭证仍有效
  unknown,
}

/// get_qrcode_status 完整结果。
class IlinkQrStatusResult {
  final IlinkQrStatus status;

  /// confirmed 时返回的 bot_token（后续 API 的 Bearer 凭证）
  final String? botToken;

  /// bot 自身 iLink 用户 ID
  final String? ilinkBotId;

  /// 账号专属 base URL（confirmed 时返回，覆盖默认域名）
  final String? baseUrl;

  /// 扫码者的 iLink 用户 ID（应加入白名单）
  final String? ilinkUserId;

  /// scannedButRedirect 时的新轮询主机
  final String? redirectHost;

  const IlinkQrStatusResult({
    required this.status,
    this.botToken,
    this.ilinkBotId,
    this.baseUrl,
    this.ilinkUserId,
    this.redirectHost,
  });
}

/// 登录二维码。
class IlinkQrcode {
  /// 二维码会话 ID（轮询 get_qrcode_status 用）
  final String qrcode;

  /// 要编码进二维码图片的 URL 字符串（官方语义：qrcode_img_content）
  final String content;

  const IlinkQrcode({required this.qrcode, required this.content});
}

/// 一条入站消息（getupdates.msgs[] 的解析视图）。
class IlinkMessage {
  final int? seq;
  final int? messageId;
  final String fromUserId;
  final String? toUserId;
  final DateTime createdAt;
  final String? sessionId;

  /// 1=USER（联系人发来）2=BOT（自己发出的回显）
  final int messageType;

  /// 0=NEW 1=GENERATING 2=FINISH
  final int messageState;

  /// 拼接后的全部文本（item_list 中所有 text_item）
  final String text;

  /// 会话上下文令牌——回复必须回传，按 fromUserId 缓存
  final String? contextToken;

  const IlinkMessage({
    this.seq,
    this.messageId,
    required this.fromUserId,
    this.toUserId,
    required this.createdAt,
    this.sessionId,
    required this.messageType,
    required this.messageState,
    required this.text,
    this.contextToken,
  });

  bool get isFromUser => messageType == 1;
  bool get isFinished => messageState == 2;
}

/// getUpdates 响应。
class IlinkUpdatesResult {
  final int ret;
  final int? errcode;
  final String? errmsg;
  final List<IlinkMessage> messages;

  /// 下一次请求要回传的游标（首次为空串）
  final String updatesBuf;
  final int? longpollingTimeoutMs;

  const IlinkUpdatesResult({
    required this.ret,
    this.errcode,
    this.errmsg,
    required this.messages,
    required this.updatesBuf,
    this.longpollingTimeoutMs,
  });

  bool get ok => ret == 0 && (errcode == null || errcode == 0);
}

/// 微信 iLink Bot 协议客户端。
///
/// 协议取证自腾讯官方 OpenClaw 插件 @tencent-weixin/openclaw-weixin@2.4.6
/// （完整笔记见 .research/wechat-ilink-protocol.md）。
/// 所有路径/字段名均按官方源码逐字对齐，勿凭感觉改。
class IlinkClient {
  /// token 失效错误码（官方 session-guard: STALE_TOKEN_ERRCODE）
  static const int errcodeStaleToken = -14;

  /// 插件消息能力声明（官方默认 bot_type）
  static const String botType = '3';

  /// 协议客户端版本（用于 iLink-App-ClientVersion 与 base_info）
  static const String channelVersion = '2.4.6';

  static final Random _rng = Random.secure();

  final String baseUrl;
  final String? botToken;
  final String botAgent;

  IlinkClient({
    required this.baseUrl,
    this.botToken,
    this.botAgent = 'Solace',
  });

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

  /// uint32 打包成 0x00MMNNPP
  static int _encodeClientVersion(String version) {
    final parts = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;
    return ((major & 0xff) << 16) | ((minor & 0xff) << 8) | (patch & 0xff);
  }

  /// X-WECHAT-UIN：随机 uint32 → 十进制串 → base64
  static String _randomWechatUin() {
    final uint32 = _rng.nextInt(0x7fffffff);
    return base64.encode(utf8.encode('$uint32'));
  }

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        'AuthorizationType': 'ilink_bot_token',
        'X-WECHAT-UIN': _randomWechatUin(),
        'iLink-App-Id': 'bot',
        'iLink-App-ClientVersion': '${_encodeClientVersion(channelVersion)}',
        if (auth && botToken != null && botToken!.isNotEmpty)
          'Authorization': 'Bearer ${botToken!.trim()}',
      };

  Map<String, dynamic> _baseInfo() => {
        'channel_version': channelVersion,
        'bot_agent': '$botAgent/1.0',
      };

  // ────────────── 登录 ──────────────

  /// 获取登录二维码。[localTokenList] 传本地已登录账号 token（防重复登录）。
  Future<IlinkQrcode> getBotQrcode({List<String> localTokenList = const []}) async {
    final resp = await http
        .post(
          Uri.parse('$_base${'ilink/bot/get_bot_qrcode?bot_type=$botType'}'),
          headers: _headers(auth: false),
          body: jsonEncode({'local_token_list': localTokenList}),
        )
        .timeout(AppDurations.wxQrcode);
    final data = _decode(resp);
    final qrcode = data['qrcode'] as String? ?? '';
    final content = data['qrcode_img_content'] as String? ?? '';
    if (qrcode.isEmpty || content.isEmpty) {
      throw IlinkException('二维码响应缺少 qrcode/qrcode_img_content',
          statusCode: resp.statusCode);
    }
    return IlinkQrcode(qrcode: qrcode, content: content);
  }

  /// 长轮询扫码状态。官方语义：客户端超时 35s，超时/网络错按 wait 继续。
  Future<IlinkQrStatusResult> getQrcodeStatus(
    String qrcode, {
    String? verifyCode,
    String? pollBaseUrl,
  }) async {
    final base = pollBaseUrl != null && pollBaseUrl.isNotEmpty
        ? (pollBaseUrl.endsWith('/') ? pollBaseUrl : '$pollBaseUrl/')
        : _base;
    var endpoint =
        'ilink/bot/get_qrcode_status?qrcode=${Uri.encodeQueryComponent(qrcode)}';
    if (verifyCode != null && verifyCode.isNotEmpty) {
      endpoint += '&verify_code=${Uri.encodeQueryComponent(verifyCode)}';
    }
    try {
      final resp = await http
          .get(Uri.parse('$base$endpoint'), headers: _headers(auth: false))
          .timeout(AppDurations.wxQrcodeLongPoll);
      final data = _decode(resp);
      final status = switch (data['status'] as String? ?? '') {
        'wait' => IlinkQrStatus.wait,
        'scaned' => IlinkQrStatus.scanned,
        'confirmed' => IlinkQrStatus.confirmed,
        'expired' => IlinkQrStatus.expired,
        'scaned_but_redirect' => IlinkQrStatus.scannedButRedirect,
        'need_verifycode' => IlinkQrStatus.needVerifyCode,
        'verify_code_blocked' => IlinkQrStatus.verifyCodeBlocked,
        'binded_redirect' => IlinkQrStatus.bindedRedirect,
        _ => IlinkQrStatus.unknown,
      };
      return IlinkQrStatusResult(
        status: status,
        botToken: data['bot_token'] as String?,
        ilinkBotId: data['ilink_bot_id'] as String?,
        baseUrl: data['baseurl'] as String?,
        ilinkUserId: data['ilink_user_id'] as String?,
        redirectHost: data['redirect_host'] as String?,
      );
    } catch (e) {
      if (e is IlinkException) rethrow;
      // 长轮询超时/网络抖动：官方插件按 wait 继续轮询
      debugPrint('[iLink] getQrcodeStatus 超时/网络错，按 wait 继续: $e');
      return const IlinkQrStatusResult(status: IlinkQrStatus.wait);
    }
  }

  // ────────────── 收发消息 ──────────────

  /// 长轮询拉取入站消息。[updatesBuf] 为上次响应返回的游标，首次传空串。
  Future<IlinkUpdatesResult> getUpdates({
    required String updatesBuf,
    Duration? timeout,
  }) async {
    final limit = timeout ?? (AppDurations.wxLongPoll);
    try {
      final resp = await http
          .post(
            Uri.parse('${_base}ilink/bot/getupdates'),
            headers: _headers(),
            body: jsonEncode({
              'get_updates_buf': updatesBuf,
              'base_info': _baseInfo(),
            }),
          )
          .timeout(limit);
      final data = _decode(resp);
      final ret = (data['ret'] as num?)?.toInt() ?? 0;
      final errcode = (data['errcode'] as num?)?.toInt();
      final errmsg = data['errmsg'] as String?;
      if (ret != 0 || (errcode != null && errcode != 0)) {
        throw IlinkException(errmsg ?? 'getUpdates ret=$ret',
            statusCode: resp.statusCode, errcode: errcode ?? ret);
      }
      final msgs = (data['msgs'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => _parseMessage(Map<String, dynamic>.from(m)))
          .whereType<IlinkMessage>()
          .toList();
      return IlinkUpdatesResult(
        ret: ret,
        errcode: errcode,
        errmsg: errmsg,
        messages: msgs,
        updatesBuf: data['get_updates_buf'] as String? ?? updatesBuf,
        longpollingTimeoutMs:
            (data['longpolling_timeout_ms'] as num?)?.toInt(),
      );
    } on TimeoutException {
      // 客户端超时是长轮询的正常控制流：当作空结果
      return IlinkUpdatesResult(
        ret: 0,
        messages: const [],
        updatesBuf: updatesBuf,
      );
    }
  }

  IlinkMessage? _parseMessage(Map<String, dynamic> item) {
    final from = item['from_user_id'] as String? ?? '';
    if (from.isEmpty) return null;
    final texts = <String>[];
    final items = item['item_list'] as List? ?? const [];
    for (final raw in items) {
      if (raw is! Map) continue;
      final type = (raw['type'] as num?)?.toInt();
      final textItem = raw['text_item'] as Map?;
      if (type == 1 && textItem != null) {
        final t = textItem['text'] as String? ?? '';
        if (t.isNotEmpty) texts.add(t);
      }
    }
    final text = texts.join('\n');
    if (text.isEmpty) return null;
    final createMs = (item['create_time_ms'] as num?)?.toInt();
    return IlinkMessage(
      seq: (item['seq'] as num?)?.toInt(),
      messageId: (item['message_id'] as num?)?.toInt(),
      fromUserId: from,
      toUserId: item['to_user_id'] as String?,
      createdAt: createMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createMs)
          : DateTime.now(),
      sessionId: item['session_id'] as String?,
      messageType: (item['message_type'] as num?)?.toInt() ?? 1,
      messageState: (item['message_state'] as num?)?.toInt() ?? 2,
      text: text,
      contextToken: item['context_token'] as String?,
    );
  }

  /// 发送文本消息。[contextToken] 必须回传入站消息带来的会话令牌。
  Future<void> sendMessage({
    required String to,
    required String text,
    String? contextToken,
  }) async {
    final clientId =
        'solace-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final resp = await http
        .post(
          Uri.parse('${_base}ilink/bot/sendmessage'),
          headers: _headers(),
          body: jsonEncode({
            'msg': {
              'from_user_id': '',
              'to_user_id': to,
              'client_id': clientId,
              'message_type': 2,
              'message_state': 2,
              'item_list': [
                {
                  'type': 1,
                  'text_item': {'text': text},
                },
              ],
              if (contextToken != null && contextToken.isNotEmpty)
                'context_token': contextToken,
            },
            'base_info': _baseInfo(),
          }),
        )
        .timeout(AppDurations.wxSend);
    final data = _decode(resp);
    final ret = (data['ret'] as num?)?.toInt() ?? 0;
    if (ret != 0) {
      throw IlinkException('sendMessage ret=$ret ${data['errmsg'] ?? ''}',
          statusCode: resp.statusCode, errcode: ret);
    }
  }

  /// 获取账号配置（typing_ticket 等）。
  Future<String?> getConfig(String ilinkUserId, {String? contextToken}) async {
    final resp = await http
        .post(
          Uri.parse('${_base}ilink/bot/getconfig'),
          headers: _headers(),
          body: jsonEncode({
            'ilink_user_id': ilinkUserId,
            if (contextToken != null) 'context_token': contextToken,
            'base_info': _baseInfo(),
          }),
        )
        .timeout(AppDurations.wxConfig);
    final data = _decode(resp);
    return data['typing_ticket'] as String?;
  }

  /// 发送输入状态。[typingTicket] 先从 getConfig 获取；[typing] true=输入中。
  Future<void> sendTyping({
    required String ilinkUserId,
    required String typingTicket,
    required bool typing,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${_base}ilink/bot/sendtyping'),
            headers: _headers(),
            body: jsonEncode({
              'ilink_user_id': ilinkUserId,
              'typing_ticket': typingTicket,
              'status': typing ? 1 : 2,
              'base_info': _baseInfo(),
            }),
          )
          .timeout(AppDurations.wxConfig);
      _decode(resp);
    } catch (e) {
      debugPrint('[iLink] sendTyping failed: $e');
    }
  }

  // ────────────── 生命周期 ──────────────

  Future<void> notifyStart() => _notify('ilink/bot/msg/notifystart');

  Future<void> notifyStop() => _notify('ilink/bot/msg/notifystop');

  Future<void> _notify(String endpoint) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base$endpoint'),
            headers: _headers(),
            body: jsonEncode({'base_info': _baseInfo()}),
          )
          .timeout(AppDurations.wxConfig);
      _decode(resp);
    } catch (e) {
      debugPrint('[iLink] $endpoint failed: $e');
    }
  }

  // ────────────── 工具 ──────────────

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw IlinkException('bot_token 无效或已过期，请重新扫码登录',
          statusCode: resp.statusCode);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw IlinkException('HTTP ${resp.statusCode}: ${_safeBody(resp)}',
          statusCode: resp.statusCode);
    }
    if (resp.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (e) {
      throw IlinkException('响应不是合法 JSON: ${_safeBody(resp)}',
          statusCode: resp.statusCode);
    }
  }

  static String _safeBody(http.Response resp) =>
      resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
}
