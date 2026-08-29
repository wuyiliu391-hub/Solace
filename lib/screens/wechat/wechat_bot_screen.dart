import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/wechat/ilink_client.dart';
import '../../services/wechat/wechat_bot_service.dart';
import '../../services/wechat/wechat_bot_store.dart';
import '../../widgets/wechat/wx_setting_row.dart';

/// 微信机器人管理页：扫码登录 + 角色绑定 + 白名单管理。
class WeChatBotScreen extends StatefulWidget {
  const WeChatBotScreen({super.key});

  @override
  State<WeChatBotScreen> createState() => _WeChatBotScreenState();
}

class _WeChatBotScreenState extends State<WeChatBotScreen> {
  final WeChatBotService _service = WeChatBotService.instance;

  bool _loading = true;
  bool _connected = false;
  bool _enabled = false;
  bool _syncToChatList = false;
  bool _useMemory = true;
  String _baseUrl = WeChatBotStore.defaultBaseUrl;

  List<AICharacter> _characters = [];
  String? _boundCharacterId;
  List<WxContactEntry> _whitelist = [];
  List<WxPendingEntry> _pending = [];

  // ── 扫码流程状态 ──
  IlinkQrcode? _qrcode;
  IlinkQrStatus _qrStatus = IlinkQrStatus.wait;
  bool _qrLoading = false;
  String? _qrError;
  bool _qrPolling = false;

  /// IDC 重定向后的状态轮询域名
  String? _pollBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _qrPolling = false;
    super.dispose();
  }

  Future<void> _loadAll() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final token = await WeChatBotStore.loadToken();
    final enabled = await WeChatBotStore.loadEnabled();
    final baseUrl = await WeChatBotStore.loadBaseUrl();
    final characters = await storage.getAllAICharacters();
    final boundId = await WeChatBotStore.loadBoundCharacterId();
    final whitelist = await WeChatBotStore.loadWhitelist();
    final pending = await WeChatBotStore.loadPending();
    final syncToChatList = await WeChatBotStore.loadSyncToChatList();
    final useMemory = await WeChatBotStore.loadUseMemory();
    if (!mounted) return;
    setState(() {
      _connected = token != null;
      _enabled = enabled;
      _baseUrl = baseUrl;
      _characters = characters;
      _boundCharacterId = boundId;
      _whitelist = whitelist;
      _pending = pending;
      _syncToChatList = syncToChatList;
      _useMemory = useMemory;
      _loading = false;
    });
  }

  // ────────────── 扫码登录 ──────────────

  Future<void> _startLogin() async {
    setState(() {
      _qrLoading = true;
      _qrError = null;
      _qrcode = null;
      _qrStatus = IlinkQrStatus.wait;
      _pollBaseUrl = null;
    });
    try {
      final qr = await _service.requestQrcode();
      if (!mounted) return;
      setState(() {
        _qrcode = qr;
        _qrLoading = false;
      });
      _pollQrStatus(qr.qrcode);
    } on IlinkException catch (e) {
      if (!mounted) return;
      setState(() {
        _qrLoading = false;
        _qrError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrLoading = false;
        _qrError = '无法连接 iLink 服务：$e\n请检查网络或在下方修改服务地址';
      });
    }
  }

  /// 长轮询扫码状态（官方接口服务端 hold ~35s，超时按 wait 续轮）。
  void _pollQrStatus(String qrcode) {
    _qrPolling = true;
    Future<void> loop() async {
      while (_qrPolling && mounted) {
        IlinkQrStatusResult result;
        try {
          result = await _service.pollQrcodeStatus(
            qrcode,
            pollBaseUrl: _pollBaseUrl,
          );
        } catch (_) {
          // 长轮询内部已把超时归为 wait；这里兜底防异常死循环
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        if (!mounted || !_qrPolling) return;

        switch (result.status) {
          case IlinkQrStatus.confirmed:
            _qrPolling = false;
            await _service.completeLogin(result);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('微信接入成功，机器人已上线')),
            );
            await _loadAll();
            return;
          case IlinkQrStatus.bindedRedirect:
            // 该 bot 已绑定过本实例，本地凭证仍有效
            _qrPolling = false;
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该微信已绑定，沿用现有登录')),
            );
            await _loadAll();
            return;
          case IlinkQrStatus.expired:
            _qrPolling = false;
            setState(() {
              _qrcode = null;
              _qrError = '二维码已过期，请重新获取';
            });
            return;
          case IlinkQrStatus.scannedButRedirect:
            // IDC 重定向：切换轮询域名后继续
            if (result.redirectHost != null &&
                result.redirectHost!.isNotEmpty) {
              _pollBaseUrl = result.redirectHost;
            }
            if (_qrStatus != IlinkQrStatus.scanned) {
              setState(() => _qrStatus = IlinkQrStatus.scanned);
            }
            continue;
          case IlinkQrStatus.needVerifyCode:
            _qrPolling = false;
            setState(() {
              _qrcode = null;
              _qrError = '微信要求输入验证码，请在手机上完成验证后重试';
            });
            return;
          case IlinkQrStatus.verifyCodeBlocked:
            _qrPolling = false;
            setState(() {
              _qrcode = null;
              _qrError = '该账号被微信风控，请换个账号或稍后再试';
            });
            return;
          case IlinkQrStatus.wait:
          case IlinkQrStatus.unknown:
            // 继续长轮询
            break;
          default:
            break;
        }

        if (result.status != _qrStatus) {
          setState(() => _qrStatus = result.status);
        }
      }
    }

    loop();
  }

  Future<void> _logout() async {
    await _service.logout();
    setState(() {
      _connected = false;
      _enabled = false;
      _qrcode = null;
    });
  }

  // ────────────── 白名单 ──────────────

  Future<void> _showAddWhitelistDialog() async {
    final wxIdController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加白名单联系人'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final grayColor = Theme.of(context).brightness == Brightness.dark
                    ? WeChatColors.darkTextSecondary
                    : WeChatColors.textSecondary;
                return Text(
                  '对方给你的微信发消息时，将由 AI 角色代替你回复。填写对方的微信 ID（wxid）或备注标识。',
                  style: TextStyle(
                    fontSize: 12,
                    color: grayColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: wxIdController,
              decoration: const InputDecoration(
                labelText: '微信 ID（wxid）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '备注名（用于展示）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final wxId = wxIdController.text.trim();
    if (wxId.isEmpty) return;
    final entry = WxContactEntry(
      wxId: wxId,
      displayName: nameController.text.trim().isEmpty
          ? wxId
          : nameController.text.trim(),
    );
    final list = [..._whitelist];
    list.removeWhere((e) => e.wxId == wxId);
    list.add(entry);
    await WeChatBotStore.saveWhitelist(list);
    await _loadAll();
  }

  Future<void> _approvePending(WxPendingEntry entry) async {
    final list = [..._whitelist];
    list.removeWhere((e) => e.wxId == entry.wxId);
    list.add(WxContactEntry(
      wxId: entry.wxId,
      displayName: entry.fromName.isNotEmpty ? entry.fromName : entry.wxId,
    ));
    await WeChatBotStore.saveWhitelist(list);
    final pending = [..._pending]..removeWhere((e) => e.wxId == entry.wxId);
    await WeChatBotStore.savePending(pending);
    await _loadAll();
  }

  Future<void> _dismissPending(WxPendingEntry entry) async {
    final pending = [..._pending]..removeWhere((e) => e.wxId == entry.wxId);
    await WeChatBotStore.savePending(pending);
    await _loadAll();
  }

  Future<void> _showEditBaseUrlDialog() async {
    final controller = TextEditingController(text: _baseUrl);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('iLink 服务地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final url = controller.text.trim();
    if (url.isEmpty) return;
    await WeChatBotStore.saveBaseUrl(url);
    setState(() => _baseUrl = url);
  }

  // ────────────── UI ──────────────

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? WeChatColors.darkListItem : WeChatColors.listItem;
    final navColor = isDark ? WeChatColors.darkPageBackground : WeChatColors.pageBackground;
    final titleColor = isDark ? WeChatColors.darkTextPrimary : WeChatColors.textPrimary;
    final brandColor = WeChatColors.brandGreen;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: navColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          '微信机器人',
          style: TextStyle(
            fontSize: 17,
            color: titleColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: titleColor),
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: brandColor),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        _buildConnectionSection(),
        if (_connected) ...[
          _buildCharacterSection(),
          _buildWhitelistSection(),
          if (_pending.isNotEmpty) _buildPendingSection(),
        ],
        _buildAdvancedSection(),
      ],
    );
  }

  // ── 连接/扫码 ──

  Widget _buildConnectionSection() {
    return WxSettingGroup(
      title: '微信接入',
      rows: [
        Builder(
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            const brandColor = WeChatColors.brandGreen;
            final textColor = isDark ? WeChatColors.darkTextPrimary : WeChatColors.textPrimary;
            final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
            return Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: brandColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chat_bubble_rounded,
                      size: 18, color: brandColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'iLink 官方协议',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connected ? '已连接' : '未连接',
                        style: TextStyle(
                          fontSize: 12,
                          color: _connected ? brandColor : grayColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_connected)
                  Switch(
                    value: _enabled,
                    activeColor: brandColor,
                    onChanged: (v) async {
                  await WeChatBotStore.saveEnabled(v);
                  if (v) {
                    await _service.startPolling();
                  } else {
                    _service.stopPolling();
                  }
                  setState(() => _enabled = v);
                },
              ),
            ],
          );
        },
      ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final grayColor = Theme.of(context).brightness == Brightness.dark
                ? WeChatColors.darkTextSecondary
                : WeChatColors.textSecondary;
            return Text(
              '限制说明：机器人只能回复白名单联系人发来的消息，不能主动发起对话，也不能进群。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: grayColor,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (!_connected) ...[
          if (_qrcode != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: _qrcode!.content,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final grayColor = Theme.of(context).brightness == Brightness.dark
                    ? WeChatColors.darkTextSecondary
                    : WeChatColors.textSecondary;
                return Center(
                  child: Text(
                    _qrStatus == IlinkQrStatus.scanned
                        ? '已扫码，请在手机上确认'
                        : '用微信扫描二维码接入',
                    style: TextStyle(
                      fontSize: 12,
                      color: grayColor,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          if (_qrLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(color: WeChatColors.brandGreen),
              ),
            ),
          if (_qrError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Builder(
                builder: (context) {
                  final badgeColor = Theme.of(context).brightness == Brightness.dark
                      ? WeChatColors.badgeRed
                      : WeChatColors.badgeRed;
                  return Text(
                    _qrError!,
                    style: TextStyle(fontSize: 12, color: badgeColor),
                  );
                },
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: WeChatColors.brandGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _qrLoading ? null : _startLogin,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text(_qrcode != null ? '刷新二维码' : '扫码接入微信'),
            ),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WeChatColors.badgeRed,
                side: const BorderSide(color: WeChatColors.badgeRed),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _logout,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: const Text('断开微信连接'),
            ),
          ),
      ],
    );
  }

  // ── 回复角色 ──

  Widget _buildCharacterSection() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
        final brandColor = WeChatColors.brandGreen;
        final navColor = isDark ? WeChatColors.darkPageBackground : WeChatColors.pageBackground;
        return WxSettingGroup(
          title: '回复角色',
          rows: [
            Text(
              '白名单消息将以下方角色的人设、记忆与口吻回复。',
              style: TextStyle(fontSize: 12, color: grayColor),
            ),
            const SizedBox(height: 10),
            if (_characters.isEmpty)
              Text(
                '暂无角色，请先创建一个 AI 角色。',
                style: TextStyle(fontSize: 12, color: grayColor),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _characters.map((c) {
                  final selected = c.id == _boundCharacterId;
                  return ChoiceChip(
                    label: Text(c.name),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: navColor,
                    selectedColor: brandColor.withOpacity(0.15),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected ? brandColor : grayColor,
                    ),
                    onSelected: (_) async {
                      await WeChatBotStore.saveBoundCharacterId(c.id);
                      setState(() => _boundCharacterId = c.id);
                    },
                  );
                }).toList(),
              ),
          ],
        );
      },
    );
  }

  // ── 白名单 ──

  Widget _buildWhitelistSection() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
        final brandColor = WeChatColors.brandGreen;
        return WxSettingGroup(
          title: '白名单联系人',
          trailing: TextButton.icon(
            onPressed: _showAddWhitelistDialog,
            icon: Icon(Icons.add_rounded, size: 16, color: brandColor),
            label: Text('添加', style: TextStyle(color: brandColor)),
          ),
          rows: [
            Text(
              '仅名单内联系人的消息会被 AI 回复，其他人照常由你本人回复。',
              style: TextStyle(fontSize: 12, color: grayColor),
            ),
            const SizedBox(height: 6),
            if (_whitelist.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '白名单为空，机器人不会回复任何人。',
                  style: TextStyle(fontSize: 12, color: grayColor),
                ),
              )
            else
              ..._whitelist.map((e) => _buildWhitelistTile(e)),
          ],
        );
      },
    );
  }

  Widget _buildWhitelistTile(WxContactEntry e) {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
        final brandColor = WeChatColors.brandGreen;
        final navColor = isDark ? WeChatColors.darkPageBackground : WeChatColors.pageBackground;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: navColor,
            child: Text(
              e.displayName.isNotEmpty ? e.displayName[0] : '?',
              style: TextStyle(fontSize: 13, color: brandColor),
            ),
          ),
          title: Text(e.displayName, style: const TextStyle(fontSize: 13)),
          subtitle: Text(e.wxId, style: TextStyle(fontSize: 11, color: grayColor)),
          trailing: IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: grayColor),
            onPressed: () async {
              final list = [..._whitelist]..removeWhere((x) => x.wxId == e.wxId);
              await WeChatBotStore.saveWhitelist(list);
              await _loadAll();
            },
          ),
        );
      },
    );
  }

  // ── 待审批 ──

  Widget _buildPendingSection() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
        final brandColor = WeChatColors.brandGreen;
        return WxSettingGroup(
          title: '待审批来信',
          rows: [
            Text(
              '以下白名单外联系人发来了消息。批准后 TA 的消息将由 AI 代回。',
              style: TextStyle(fontSize: 12, color: grayColor),
            ),
            const SizedBox(height: 6),
            ..._pending.map((e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(e.fromName, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    e.lastText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: grayColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _approvePending(e),
                        child: Text('批准',
                            style: TextStyle(fontSize: 12, color: brandColor)),
                      ),
                      TextButton(
                        onPressed: () => _dismissPending(e),
                        child: Text('忽略',
                            style: TextStyle(fontSize: 12, color: grayColor)),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }

  // ── 高级 ──

  Widget _buildAdvancedSection() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final grayColor = isDark ? WeChatColors.darkTextSecondary : WeChatColors.textSecondary;
        return WxSettingGroup(
          title: '高级',
          rows: [
            WxSettingRow(
              title: 'iLink 服务地址',
              value: _baseUrl,
              onTap: _showEditBaseUrlDialog,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('同步到聊天列表', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '开启后微信聊天记录会出现在 Solace 聊天列表中',
                style: TextStyle(fontSize: 12, color: grayColor),
              ),
              value: _syncToChatList,
              onChanged: (v) async {
                await WeChatBotStore.saveSyncToChatList(v);
                setState(() => _syncToChatList = v);
              },
            ),
            SwitchListTile(
              title: const Text('连接记忆库', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '开启后 AI 会读取 Solace 记忆库来回复微信消息',
                style: TextStyle(fontSize: 12, color: grayColor),
              ),
              value: _useMemory,
              onChanged: (v) async {
                await WeChatBotStore.saveUseMemory(v);
                setState(() => _useMemory = v);
              },
            ),
          ],
        );
      },
    );
  }
}
