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
                    '🎉 Solace ${AppVersion.version} 大版本更新',
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
                    _sectionTitle('🤖 GPT 能力升级', cs),
                    _item('GPT-5.5 多模态理解上线，支持图片识别和图文对话。'),
                    _item('GPT Image 2.0 文生图、图生图全面开放。'),
                    const SizedBox(height: 10),
                    _sectionTitle('✨ 人生系统', cs),
                    _item('全新人生系统，数字生命拥有完整生命周期。'),
                    _item('人生线时间线，记录角色每一个关键时刻。'),
                    _item('人格五因子动态演化，实时对比基线变化。'),
                    _item('马斯洛需求层次可视化，洞察角色内心世界。'),
                    _item('身份认同、三观标签、情绪八维全面展示。'),
                    _item('生命阶段自动推进，从婴儿到暮年全程陪伴。'),
                    _item('数字永生机制，角色可超越肉体永存于世。'),
                    const SizedBox(height: 10),
                    _sectionTitle('⚔️ 宫斗战 & AI 自主', cs),
                    _item('宫斗战系统震撼登场，角色间明争暗斗。'),
                    _item('AI 自主系统全面升级，角色拥有独立社交能力。'),
                    _item('角色间可互读聊天记录和记忆库。'),
                    _item('社交网络支持好友申请与关系建立。'),
                    _item('朋友圈打通，角色间可互相点赞评论。'),
                    _item('自主控制面板支持心跳监控与手动触发。'),
                    const SizedBox(height: 10),
                    _sectionTitle('🔧 系统优化', cs),
                    _item('观察功能支持多角色自由切换。'),
                    _item('关系图谱修复空白，数据全面打通。'),
                    _item('角色年龄支持手动编辑。'),
                    _item('聊天页面修复 30 余处中文乱码。'),
                    _item('清理冗余数据库代码，性能更优。'),
                    const SizedBox(height: 10),
                    _sectionTitle('⚠️ 注意事项', cs),
                    _item('GPT 功能每日 9 点至次日凌晨可用。'),
                    _item('人生系统和宫斗战会消耗额外 Token。'),
                    _item('谨慎开启宫斗战，剧情不可预测。'),
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
          const Text('·  ', style: TextStyle(fontSize: 11, color: Color(0xFF5F6368))),
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
