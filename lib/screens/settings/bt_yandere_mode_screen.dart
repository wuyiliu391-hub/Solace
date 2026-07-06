import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';

/// BT 病娇模式全局独立设置页面
class BtYandereModeScreen extends StatefulWidget {
  const BtYandereModeScreen({super.key});

  @override
  State<BtYandereModeScreen> createState() => _BtYandereModeScreenState();
}

class _BtYandereModeScreenState extends State<BtYandereModeScreen> {
  @override
  Widget build(BuildContext context) {
    final s = context.read<LocalStorageRepository>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BT 病娇模式'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: s.modeSettingsNotifier,
        builder: (ctx, _, __) {
          final master = s.isBtYandereMasterEnabled();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ─── 总开关 ───
              _masterCard(ctx, s, cs, tt, master),
              const SizedBox(height: 12),
              if (!master)
                _frozenBanner(cs, tt)
              else ...[
                _groupCard(ctx, s, cs, tt, '通讯录权限', Icons.contacts_outlined, [
                  _item('修改备注', PrefKeys.btPermissionContactRemark),
                  _item('更换头像', PrefKeys.btPermissionContactAvatar),
                  _item('隐藏联系人', PrefKeys.btPermissionContactHide),
                  _item('删除联系人', PrefKeys.btPermissionContactDelete),
                ]),
                const SizedBox(height: 10),
                _groupCard(
                    ctx, s, cs, tt, '角色 & 互动权限', Icons.smart_toy_outlined, [
                  _item('在线状态', PrefKeys.btPermissionOnlineStatus),
                  _item('保存状态', PrefKeys.btPermissionSaveStatus),
                  _item('消息打扰', PrefKeys.btPermissionMessageDisturb),
                  _item('视频聊天', PrefKeys.btPermissionVideoChat),
                  _item('拉黑', PrefKeys.btPermissionBlock),
                  _item('清空记录', PrefKeys.btPermissionClearHistory),
                  _item('重置人设/记忆', PrefKeys.btPermissionResetPersonaMemory),
                  _item('举报', PrefKeys.btPermissionReport),
                ]),
                const SizedBox(height: 10),
                _groupCard(ctx, s, cs, tt, '发现页权限', Icons.explore_outlined, [
                  _item('朋友圈', PrefKeys.btPermissionMoments),
                  _item('信箱', PrefKeys.btPermissionMailbox),
                  _item('信件', PrefKeys.btPermissionLetters),
                  _item('日记', PrefKeys.btPermissionDiary),
                  _item('幸运转盘', PrefKeys.btPermissionLuckyWheel),
                  _item('全局记忆库', PrefKeys.btPermissionGlobalMemory),
                ]),
                const SizedBox(height: 10),
                _groupCard(ctx, s, cs, tt, '个人资料权限', Icons.person_outline, [
                  _item('修改头像', PrefKeys.btPermissionProfileAvatar),
                  _item('修改昵称', PrefKeys.btPermissionProfileNickname),
                ]),
                const SizedBox(height: 10),
                _groupCard(ctx, s, cs, tt, '外观主题权限', Icons.palette_outlined, [
                  _item('浅色模式', PrefKeys.btPermissionLightTheme),
                  _item('深色模式', PrefKeys.btPermissionDarkTheme),
                  _item('跟随系统', PrefKeys.btPermissionSystemTheme),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _masterCard(
    BuildContext ctx,
    LocalStorageRepository s,
    ColorScheme cs,
    TextTheme tt,
    bool master,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: master ? Colors.red : cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('BT 病娇模式 总开关',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: master ? Colors.red : cs.onSurface)),
                ),
                Switch(
                  value: master,
                  activeColor: Colors.red,
                  onChanged: (v) async {
                    if (v) {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          title: const Text('开启确认'),
                          content:
                              const Text('开启 BT 病娇模式后，AI 将获得部分 APP 内操控权限。\n\n'
                                  'AI 可能删除你的角色数据、修改联系人信息、清空聊天记录等。\n\n'
                                  '确认开启？'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确认开启',
                                    style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (ok != true) return;
                    }
                    await s.setBtYandereMasterEnabled(v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              master
                  ? '已开启：AI 可在权限范围内操控 APP 内数据'
                  : '已关闭：所有 BT 权限冻结，AI 不加载 BT 上下文',
              style: tt.bodySmall?.copyWith(
                  color: master ? Colors.red.shade300 : cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frozenBanner(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('总开关已关闭',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('所有 BT 子权限已冻结，AI 不会加载任何 BT 上下文。\n开启总开关后可配置分类权限。',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _groupCard(
    BuildContext ctx,
    LocalStorageRepository s,
    ColorScheme cs,
    TextTheme tt,
    String title,
    IconData icon,
    List<_PermItem> items,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(title,
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ...items.map((item) {
              final enabled = s.getBool(item.key) ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.label,
                          style: tt.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.85))),
                    ),
                    Switch(
                      value: enabled,
                      activeColor: cs.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) async {
                        await s.setBool(item.key, v);
                        s.modeSettingsNotifier.value++;
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  _PermItem _item(String label, String key) => _PermItem(label, key);
}

class _PermItem {
  final String label;
  final String key;
  const _PermItem(this.label, this.key);
}
