import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/usage_record.dart';
import '../../services/usage_meter_service.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  final _meter = UsageMeterService.instance;
  StreamSubscription<void>? _sub;
  UsageRange _range = UsageRange.today;
  UsageSummary _summary = UsageSummary.empty;
  UsagePricing _pricing = UsagePricing.defaults;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = _meter.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _meter.getSummary(_range),
      _meter.getPricing(),
    ]);
    if (!mounted) return;
    final pricing = results[1] as UsagePricing;
    setState(() {
      _summary = results[0] as UsageSummary;
      _pricing = pricing;
      _inputController.text = _formatPrice(pricing.inputPricePerMillion);
      _outputController.text = _formatPrice(pricing.outputPricePerMillion);
      _loading = false;
    });
  }

  Future<void> _savePricing() async {
    await _meter.savePricing(UsagePricing(
      inputPricePerMillion: double.tryParse(_inputController.text.trim()) ??
          _pricing.inputPricePerMillion,
      outputPricePerMillion: double.tryParse(_outputController.text.trim()) ??
          _pricing.outputPricePerMillion,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用量单价已保存，全局生效')),
      );
    }
  }

  Future<void> _resetPricing() async {
    await _meter.resetPricing();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置为默认单价')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('用量'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _buildRangeSwitch(cs),
                const SizedBox(height: 20),
                _buildRingsSection(cs),
                const SizedBox(height: 20),
                _buildInputBreakdownSection(cs),
                const SizedBox(height: 20),
                _buildMetricsGrid(cs),
                const SizedBox(height: 20),
                _buildPricingPanel(cs),
              ],
            ),
    );
  }

  // ── 时间筛选 ──

  Widget _buildRangeSwitch(ColorScheme cs) {
    const items = {
      UsageRange.today: '今日',
      UsageRange.yesterday: '昨日',
      UsageRange.week: '本周',
      UsageRange.all: '总计',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: items.entries.map((entry) {
          final selected = entry.key == _range;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _range = entry.key);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: selected ? cs.primary : Colors.transparent,
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 圆环区域 ──

  Widget _buildRingsSection(ColorScheme cs) {
    return _card(cs,
        child: Column(
          children: [
            // 主圆环：平均每次请求 Token
            _UsageRingWithValue(
              size: 150,
              progress: (_summary.avgTokensPerRequest / 4096).clamp(0.0, 1.0),
              value: _formatTokenCount(_summary.avgTokensPerRequest),
              label: '平均每次请求',
              color: cs.primary,
              onSurface: cs.onSurface,
            ),
            const SizedBox(height: 24),
            // 两个小圆环并排
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: _UsageRing(
                      size: 110,
                      progress: _summary.inputTokenShare,
                      label: '输入占比',
                      color: cs.tertiary,
                      onSurface: cs.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _UsageRing(
                      size: 110,
                      progress: _summary.outputTokenShare,
                      label: '输出占比',
                      color: cs.secondary,
                      onSurface: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ));
  }

  String _formatTokenCount(int tokens) {
    if (tokens >= 10000) return '${(tokens / 1000).toStringAsFixed(1)}k';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}k';
    return '$tokens';
  }

  // ── 输入 Token 拆分 ──

  Widget _buildInputBreakdownSection(ColorScheme cs) {
    final parts = [
      _InputBreakdownPart(
        label: '设定/规则',
        value: _summary.systemTokens,
        color: cs.primary,
        icon: Icons.tune_rounded,
      ),
      _InputBreakdownPart(
        label: '历史/记忆',
        value: _summary.historyTokens,
        color: cs.secondary,
        icon: Icons.history_rounded,
      ),
      _InputBreakdownPart(
        label: '本次消息',
        value: _summary.userMessageTokens,
        color: cs.tertiary,
        icon: Icons.chat_bubble_outline_rounded,
      ),
      _InputBreakdownPart(
        label: '其他输入',
        value: _summary.otherInputTokens,
        color: cs.error,
        icon: Icons.more_horiz_rounded,
      ),
    ];

    return _card(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '输入 Token 拆分',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '输入不是只算你说的话，还包括角色设定、记忆和历史上下文。',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: parts.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final part = parts[index];
              return _InputBreakdownRing(
                part: part,
                share: _summary.inputPartShare(part.value),
                valueText: _formatTokenCount(part.value),
                onSurface: cs.onSurface,
                trackColor: cs.surfaceContainerHighest,
              );
            },
          ),
          if (_summary.cacheHitTokens > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined, color: cs.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '其中 ${_formatTokenCount(_summary.cacheHitTokens)} Token 命中缓存，实际费用通常更低。',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.72),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 数据指标 ──

  Widget _buildMetricsGrid(ColorScheme cs) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _metricTile(cs, '输入 Token', _summary.inputTokens.toString(),
            Icons.input_rounded, cs.primary),
        _metricTile(cs, '输出 Token', _summary.outputTokens.toString(),
            Icons.output_rounded, cs.tertiary),
        _metricTile(cs, '请求次数', _summary.requestCount.toString(),
            Icons.api_rounded, cs.secondary),
        _metricTile(cs, '累计金额', '¥${_summary.totalCost.toStringAsFixed(4)}',
            Icons.account_balance_wallet_outlined, cs.error),
      ],
    );
  }

  Widget _metricTile(
      ColorScheme cs, String title, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── 单价配置 ──

  Widget _buildPricingPanel(ColorScheme cs) {
    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('单价配置',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('单位：元 / 百万 Token，保存后全局生效',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _priceField('输入单价', _inputController, cs)),
                const SizedBox(width: 12),
                Expanded(child: _priceField('输出单价', _outputController, cs)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _savePricing,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('保存配置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetPricing,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('重置单价'),
                  ),
                ),
              ],
            ),
          ],
        ));
  }

  Widget _priceField(
      String label, TextEditingController controller, ColorScheme cs) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        filled: true,
        fillColor: cs.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
    );
  }

  // ── 通用卡片容器 ──

  Widget _card(ColorScheme cs, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  String _formatPrice(double value) =>
      value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 4);
}

class _InputBreakdownPart {
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  const _InputBreakdownPart({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class _InputBreakdownRing extends StatelessWidget {
  final _InputBreakdownPart part;
  final double share;
  final String valueText;
  final Color onSurface;
  final Color trackColor;

  const _InputBreakdownRing({
    required this.part,
    required this.share,
    required this.valueText,
    required this.onSurface,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (share.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: part.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: part.color.withOpacity(0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(70, 70),
                  painter: _RingPainter(
                    progress: share,
                    color: part.color,
                    trackColor: trackColor.withOpacity(0.55),
                  ),
                ),
                Icon(part.icon, color: part.color, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            part.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSurface.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$valueText · $percent%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSurface.withOpacity(0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  环形进度圆环
// ═══════════════════════════════════════════════

class _UsageRing extends StatelessWidget {
  final double size;
  final double progress;
  final String label;
  final Color color;
  final Color onSurface;

  const _UsageRing({
    required this.size,
    required this.progress,
    required this.label,
    required this.color,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).toStringAsFixed(1);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: progress,
              color: color,
              trackColor: color.withOpacity(0.12),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  color: onSurface,
                  fontSize: size > 140 ? 28 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: onSurface.withOpacity(0.5),
                  fontSize: size > 140 ? 12 : 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageRingWithValue extends StatelessWidget {
  final double size;
  final double progress;
  final String value;
  final String label;
  final Color color;
  final Color onSurface;

  const _UsageRingWithValue({
    required this.size,
    required this.progress,
    required this.value,
    required this.label,
    required this.color,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: progress,
              color: color,
              trackColor: color.withOpacity(0.12),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: onSurface,
                  fontSize: size > 140 ? 26 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: onSurface.withOpacity(0.5),
                  fontSize: size > 140 ? 12 : 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    // 轨道
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    // 进度弧
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
