import 'package:flutter/material.dart';
import '../../services/wellbeing_service.dart';

/// 作息陪伴设置页（纯本地）
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

  // 测试按钮状态
  bool _testingLock = false;
  bool _testingEval = false;
  String? _lastEvalResult;

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

  /// 手动强制测试锁屏
  Future<void> _testLockNow() async {
    setState(() => _testingLock = true);
    final ok = await _service.lockNow();
    if (!mounted) return;
    setState(() => _testingLock = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('锁屏失败 — 请先授予设备管理员权限')),
      );
    }
    // 成功则屏幕直接熄灭，不需要提示
  }

  /// 手动触发一次规则评估（不锁屏，只看结果）
  Future<void> _testEvaluate() async {
    setState(() {
      _testingEval = true;
      _lastEvalResult = null;
    });
    final decision = await _service.evaluate(aiSuggests: false);
    if (!mounted) return;
    setState(() {
      _testingEval = false;
      _lastEvalResult = decision.allow
          ? '✅ 规则命中，会触发锁屏\n原因：${decision.reason}'
          : '⏸ 规则未命中，不锁屏\n原因：${decision.reason}';
    });
  }

  List<Widget> _buildChildren(ColorScheme cs) {
    return [
      // ── 功能说明卡片 ──
      _buildCapabilityCard(cs),
      const SizedBox(height: 16),

      // ── 触发时机说明 ──
      _buildTriggerCard(cs),
      const SizedBox(height: 16),

      // 主开关
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('启用作息陪伴'),
        subtitle: const Text('开启后心跳服务每 2-5 分钟自动检查一次规则'),
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

      // ── 授权区 ──
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
            : '未授权 · 点击授予（用于感知连续使用时长）'),
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

      // ── 休息规则 ──
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('休息规则',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.6))),
      ),

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

      const Divider(),

      // ── 手动测试区 ──
      _buildTestSection(cs),
      const SizedBox(height: 32),
    ];
  }

  /// 功能能力说明卡
  Widget _buildCapabilityCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_outline, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('TA 能做什么',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 10),
          _capabilityRow(Icons.lock_outline, '锁屏', '到了就寝时间或使用超限，自动锁屏。你用自己的密码即可解锁，随时可关闭。', cs),
          const SizedBox(height: 6),
          _capabilityRow(Icons.bar_chart_outlined, '使用时长感知', '仅读「本机前台 App 名 + 使用分钟数」，读不到任何应用内文字或内容。', cs),
          const SizedBox(height: 6),
          _capabilityRow(Icons.chat_bubble_outline, 'AI 提议', '聊天中 AI 可以建议你休息（[rest_suggest] 标记），但最终是否锁屏由这里的规则说了算。', cs),
          const SizedBox(height: 8),
          Divider(height: 1, color: cs.outline.withOpacity(0.3)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.block, size: 14, color: cs.error.withOpacity(0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '不上传任何数据 · 不读屏 · 不模拟点击 · 不远程控制',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capabilityRow(IconData icon, String title, String desc, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary.withOpacity(0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.75), height: 1.4),
              children: [
                TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 触发时机说明卡
  Widget _buildTriggerCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('触发时机',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          _triggerRow('📡', '心跳自动检查', 'App 在前台时每 2-5 分钟自动检查一次规则，无需用户操作', cs),
          const SizedBox(height: 4),
          _triggerRow('💬', 'AI 对话触发', '聊天中 AI 发出 [rest_suggest] 时立即触发一次规则判断', cs),
          const SizedBox(height: 4),
          _triggerRow('🔘', '手动测试', '下方按钮可随时手动触发，验证配置是否生效', cs),
        ],
      ),
    );
  }

  Widget _triggerRow(String emoji, String title, String desc, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7), height: 1.4),
              children: [
                TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 手动测试区域
  Widget _buildTestSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('手动测试',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.6))),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: _testingEval
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rule, size: 18),
                label: const Text('检查规则'),
                onPressed: _testingEval ? null : _testEvaluate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: _testingLock
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock, size: 18),
                label: const Text('立即锁屏'),
                style: FilledButton.styleFrom(backgroundColor: cs.error),
                onPressed: (_testingLock || !_adminActive) ? null : _testLockNow,
              ),
            ),
          ],
        ),
        if (!_adminActive)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('需先授予设备管理员权限才能使用立即锁屏',
                style: TextStyle(fontSize: 12, color: cs.error.withOpacity(0.8))),
          ),
        if (_lastEvalResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_lastEvalResult!,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: cs.onSurface.withOpacity(0.85))),
          ),
        ],
      ],
    );
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
