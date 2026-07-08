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
                    'Solace ${AppVersion.version} 大型版本更新',
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
                    _sectionTitle('单聊界面优化', cs),
                    _item('对话文本与旁白内容分隔展示，AI 输出文字统一采用蓝色字体。'),
                    _item('该功能在部分场景下仍存在未知 BUG，后续版本持续修复优化。'),
                    const SizedBox(height: 10),
                    _sectionTitle('功能入口调整', cs),
                    _item('故事书入口迁移至发现页面，访问更便捷。'),
                    const SizedBox(height: 10),
                    _sectionTitle('输出逻辑修复', cs),
                    _item('解决多款模式下内容分段异常、一次性完整刷屏输出的故障。'),
                    const SizedBox(height: 10),
                    _sectionTitle('仿生沉浸体验深度升级', cs),
                    _item('消息持久化存储'),
                    _item('角色情绪状态持久化'),
                    _item('动态打字延迟效果'),
                    _item('角色结构化特征存档'),
                    _item('用户每日行为轨迹持久保存'),
                    _item('增量记忆库二次迭代更新'),
                    _item('情绪感知敏感度全面加深'),
                    const SizedBox(height: 10),
                    _sectionTitle('设备操控测试版', cs),
                    _item('上线锁屏专属交互模式。'),
                    const SizedBox(height: 10),
                    _sectionTitle('内置官方角色', cs),
                    _item('内置官方角色「老大」（项目作者），内置强制规范：严禁色情、违法、调教、低俗类相关内容。'),
                    const SizedBox(height: 10),
                    _sectionTitle('发现页面全新改版', cs),
                    _item('支持左滑切换第二分页'),
                    _item('新增娱乐专区：真心话大冒险、默契测试、心有灵犀、角色印象'),
                    _item('旧版全部历史功能统一收纳至「更多娱乐」入口'),
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
