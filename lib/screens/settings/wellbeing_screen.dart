import 'package:flutter/material.dart';
import '../../services/wellbeing_service.dart';

/// 作息陪伴设置页（纯本地）
///
/// 让用户开启/关闭作息陪伴，授予「仅锁屏」的设备管理员与「使用情况访问」，
/// 并配置就寝时段、连续使用上限、触发规则。
///
/// 所有配置本地存储，所有感知本地读取，所有锁屏本地触发——零数据外传。
/// AI 只能通过 [rest_suggest] 标记「提议」休息，是否真锁屏由本页规则决定。
class WellbeingScreen extends StatefulWidget {
  const WellbeingScreen({super.key});

  @override
  State<WellbeingScreen> createState() => _WellbeingScreenState();
}

class _WellbeingScreenState extends State<WellbeingScreen> {
  final _service = WellbeingService();

  WellbeingConfig _cfg = const WellbeingConfig();
  bool _adminActive = false;
  bool _usageAccess = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final cfg = await _service.loadConfig();
    final admin = await _service.isAdminActive();
    final usage = await _service.hasUsageAccess();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _adminActive = admin;
      _usageAccess = usage;
      _loading = false;
    });
  }

  Future<void> _update(WellbeingConfig next) async {
    setState(() => _cfg = next);
    await _service.saveConfig(next);
  }

  String _fmt(int min) =>
      '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool isStart) async {
    final cur = isStart ? _cfg.bedStartMin : _cfg.bedEndMin;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    _update(isStart
        ? WellbeingConfig(
            enabled: _cfg.enabled,
            bedStartMin: m,
            bedEndMin: _cfg.bedEndMin,
            maxUsageMin: _cfg.maxUsageMin,
            lockOnBedtime: _cfg.lockOnBedtime,
            lockOnOveruse: _cfg.lockOnOveruse,
          )
        : WellbeingConfig(
            enabled: _cfg.enabled,
            bedStartMin: _cfg.bedStartMin,
            bedEndMin: m,
            maxUsageMin: _cfg.maxUsageMin,
            lockOnBedtime: _cfg.lockOnBedtime,
            lockOnOveruse: _cfg.lockOnOveruse,
          ));
  }

  // BODY_PLACEHOLDER

  List<Widget> _buildChildren(ColorScheme cs) {
    return [
      // 说明卡片
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.favorite_outline, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'TA 会在你设定的休息时段温柔提醒你放下手机。所有感知与锁屏都在本机完成，'
                '不上传任何数据；锁屏后用你自己的密码即可解开，可随时关闭。',
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: cs.onSurface.withOpacity(0.75)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // 主开关
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('启用作息陪伴'),
        subtitle: const Text('开启后 AI 才会感知作息并可能提议休息'),
        value: _cfg.enabled,
        onChanged: (v) => _update(WellbeingConfig(
          enabled: v,
          bedStartMin: _cfg.bedStartMin,
          bedEndMin: _cfg.bedEndMin,
          maxUsageMin: _cfg.maxUsageMin,
          lockOnBedtime: _cfg.lockOnBedtime,
          lockOnOveruse: _cfg.lockOnOveruse,
        )),
      ),
      const Divider(),

      // 授权区
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          _adminActive ? Icons.check_circle : Icons.lock_outline,
          color: _adminActive ? Colors.green : cs.onSurface.withOpacity(0.5),
        ),
        title: const Text('锁屏权限（设备管理员）'),
        subtitle: Text(_adminActive ? '已授权 · 仅用于锁屏，可在系统设置撤销' : '未授权 · 点击授予'),
        trailing: _adminActive ? null : const Icon(Icons.chevron_right),
        onTap: _adminActive
            ? null
            : () async {
                await _service.requestAdmin();
                await Future.delayed(const Duration(milliseconds: 400));
                _refresh();
              },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          _usageAccess ? Icons.check_circle : Icons.bar_chart_outlined,
          color: _usageAccess ? Colors.green : cs.onSurface.withOpacity(0.5),
        ),
        title: const Text('使用情况访问'),
        subtitle: Text(_usageAccess
            ? '已授权 · 仅读前台应用时长，读不到应用内容'
            : '未授权 · 点击授予（用于感知使用时长）'),
        trailing: _usageAccess ? null : const Icon(Icons.chevron_right),
        onTap: _usageAccess
            ? null
            : () async {
                await _service.requestUsageAccess();
                await Future.delayed(const Duration(milliseconds: 400));
                _refresh();
              },
      ),
      const Divider(),

      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('休息规则',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.6))),
      ),

      // 规则一：就寝时段锁屏
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('就寝时段提议锁屏'),
        subtitle: Text('${_fmt(_cfg.bedStartMin)} — ${_fmt(_cfg.bedEndMin)}'),
        value: _cfg.lockOnBedtime,
        onChanged: (v) => _update(WellbeingConfig(
          enabled: _cfg.enabled,
          bedStartMin: _cfg.bedStartMin,
          bedEndMin: _cfg.bedEndMin,
          maxUsageMin: _cfg.maxUsageMin,
          lockOnBedtime: v,
          lockOnOveruse: _cfg.lockOnOveruse,
        )),
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.bedtime_outlined, size: 18),
              label: Text('就寝 ${_fmt(_cfg.bedStartMin)}'),
              onPressed: () => _pickTime(true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.wb_sunny_outlined, size: 18),
              label: Text('起床 ${_fmt(_cfg.bedEndMin)}'),
              onPressed: () => _pickTime(false),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),

      // 规则二：连续使用超限锁屏
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('连续使用超限提议锁屏'),
        subtitle: Text('单次使用超过 ${_cfg.maxUsageMin} 分钟'),
        value: _cfg.lockOnOveruse,
        onChanged: (v) => _update(WellbeingConfig(
          enabled: _cfg.enabled,
          bedStartMin: _cfg.bedStartMin,
          bedEndMin: _cfg.bedEndMin,
          maxUsageMin: _cfg.maxUsageMin,
          lockOnBedtime: _cfg.lockOnBedtime,
          lockOnOveruse: v,
        )),
      ),
      if (_cfg.lockOnOveruse)
        Slider(
          value: _cfg.maxUsageMin.toDouble().clamp(30, 240),
          min: 30,
          max: 240,
          divisions: 7,
          label: '${_cfg.maxUsageMin} 分钟',
          onChanged: (v) => _update(WellbeingConfig(
            enabled: _cfg.enabled,
            bedStartMin: _cfg.bedStartMin,
            bedEndMin: _cfg.bedEndMin,
            maxUsageMin: v.round(),
            lockOnBedtime: _cfg.lockOnBedtime,
            lockOnOveruse: _cfg.lockOnOveruse,
          )),
        ),
      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('作息陪伴')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _buildChildren(cs),
            ),
    );
  }
}
