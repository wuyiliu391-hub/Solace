import 'package:flutter/material.dart';

class AgeGateDialog extends StatelessWidget {
  const AgeGateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                '年龄确认',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                '根据《人工智能拟人化互动服务管理暂行办法》，本应用仅限18周岁及以上用户使用。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7), height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('我已满18周岁', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('未满18周岁', style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AgeGateBlockedScreen extends StatelessWidget {
  const AgeGateBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: Colors.red[400]),
              const SizedBox(height: 24),
              Text(
                '无法使用',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                '根据相关规定，本应用仅限18周岁及以上用户使用。感谢你的理解。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(0.6), height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
