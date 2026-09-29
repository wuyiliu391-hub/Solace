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
                    _sectionTitle('语音与音色修复', cs),
                    _item('修复内置 TTS 音色切换无效、切换后仍播放旧音色的问题。'),
                    _item('切换预置音色时自动清理内存缓存，确保新音色立即生效。'),
                    const SizedBox(height: 10),
                    _sectionTitle('聊天功能修复', cs),
                    _item('修复角色消息重新生成失败、生成中断后无法恢复的问题。'),
                    _item('重新生成增加超时保护和异常恢复，避免卡死或消息丢失。'),
                    _item('修复主页联系人列表打开后不显示角色和聊天记录的问题。'),
                    const SizedBox(height: 10),
                    _sectionTitle('微信机器人优化', cs),
                    _item('新增「同步到聊天列表」开关，微信聊天记录默认与主列表隔离。'),
                    _item('新增「连接记忆库」开关，用户可自主选择是否让微信 AI 读取记忆。'),
                    _item('修复微信回复极慢（10分钟+）的问题，增加 90 秒超时保护。'),
                    _item('优化 typing 状态请求，避免网络抖动导致整体卡住。'),
                    const SizedBox(height: 10),
                    _sectionTitle('界面与体验', cs),
                    _item('微信机器人设置页新增功能开关，支持明暗主题自适应。'),
                    _item('修复多行输入框第二行文字被遮挡的问题。'),
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
