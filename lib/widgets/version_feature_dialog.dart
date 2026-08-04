// ============================================================
// 版本更新公告弹窗 — 强制确认，不可跳过
// ============================================================

import 'package:flutter/material.dart';
import '../config/constants.dart';

/// 版本新功能公告弹窗
///
/// 每次版本更新后所有用户都会看到，必须点击"我已知晓"才能关闭。
/// 使用 [ackKey] 区分不同版本的公告，避免重复弹出。
class VersionFeatureDialog extends StatelessWidget {
  final String ackKey;

  const VersionFeatureDialog({super.key, required this.ackKey});

  /// 检查当前版本是否已确认过，未确认则弹窗
  static Future<void> showIfNeeded(BuildContext context, String ackKey) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VersionFeatureDialog(ackKey: ackKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 标题栏 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  Icon(Icons.rocket_launch, color: cs.primary, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Solace ${AppVersion.version} 版本更新',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── 内容列表 ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('数据库兼容性修复', cs),
                    _item('旧版本用户升级后，启动时自动检测并补齐缺失的数据库表和字段。'),
                    _item('修复升级后打开报错，以及旧版数据库创建群聊失败的问题。'),
                    const SizedBox(height: 10),
                    _sectionTitle('群聊系统修复', cs),
                    _item('群聊会话、消息、分支、摘要和公共事件记忆表自动创建并校验。'),
                    _item('修复群聊自动回复、按角色接话间隔、群聊记忆回流和成员回复问题。'),
                    const SizedBox(height: 10),
                    _sectionTitle('聊天体验修复', cs),
                    _item('修复小说模式段落标点、自定义状态、永久记忆和书签跳转。'),
                    _item('角色手机现在会自动推进，并继承用户当前的壁纸主题。'),
                    const SizedBox(height: 10),
                    _sectionTitle('界面与启动体验', cs),
                    _item('角色手机继承用户壁纸主题，Android 启动页支持深浅色模式。'),
                    _item('官网完成 Bauhaus 主题改版，版本和更新服务同步升级。'),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // ── 确认按钮 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '我已知晓',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }

  Widget _item(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF5F6368))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Color(0xFF3C4043),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
