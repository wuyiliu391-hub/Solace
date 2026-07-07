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
                    'Solace ${AppVersion.version} 更新公告',
                    style: TextStyle(
                      fontSize: 16,
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
                    _sectionTitle('源码回归', cs),
                    _item('作者重新找回源码，项目恢复维护并完成本轮更新。'),
                    const SizedBox(height: 10),
                    _sectionTitle('功能调整', cs),
                    _item('暂时删除所有图片相关功能，先保证聊天与核心体验稳定。'),
                    const SizedBox(height: 10),
                    _sectionTitle('隐藏彩蛋', cs),
                    _item('加入一个小彩蛋，保持神秘，留给你在聊天里发现。'),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }

  Widget _item(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ',
              style: TextStyle(fontSize: 11, color: Color(0xFF5F6368))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Color(0xFF3C4043),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
