import 'package:flutter/material.dart';
import 'age_gate_dialog.dart';

enum AgeRange { under14, age15to18, over18 }

class AgeDeclarationScreen extends StatefulWidget {
  const AgeDeclarationScreen({super.key});

  @override
  State<AgeDeclarationScreen> createState() => _AgeDeclarationScreenState();
}

class _AgeDeclarationScreenState extends State<AgeDeclarationScreen> {
  AgeRange? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('年龄确认与责任声明'),
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_outlined, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                '年龄确认与责任声明',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.error.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '重要声明',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: cs.error),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '开发者目前为未成年人，无法接入官方实名认证系统。'
                      '请如实选择你的年龄段：\n\n'
                      '• 14岁以下：禁止使用此应用\n'
                      '• 15-18岁：可用于非恋人陪伴功能\n'
                      '• 18岁以上：可使用全部功能\n\n'
                      '刻意虚报年龄，导致意外风险和事故，'
                      '责任全部由使用者和监护人承担。',
                      style: TextStyle(color: cs.error, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildButton(
                icon: Icons.block,
                bgColor: Colors.red,
                title: '14岁以下',
                subtitle: '禁止使用此应用',
                selected: _selected == AgeRange.under14,
                onTap: () => _select(AgeRange.under14),
              ),
              const SizedBox(height: 12),
              _buildButton(
                icon: Icons.person_outline,
                bgColor: Colors.orange,
                title: '15-18岁',
                subtitle: '功能受限 · 恋人模式不可用',
                selected: _selected == AgeRange.age15to18,
                onTap: () => _select(AgeRange.age15to18),
              ),
              const SizedBox(height: 12),
              _buildButton(
                icon: Icons.verified_user,
                bgColor: Colors.green,
                title: '18岁以上',
                subtitle: '可使用全部功能',
                selected: _selected == AgeRange.over18,
                onTap: () => _select(AgeRange.over18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required Color bgColor,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? bgColor.withOpacity(0.1)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? bgColor : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: bgColor),
          ],
        ),
      ),
    );
  }

  Future<void> _select(AgeRange range) async {
    setState(() => _selected = range);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('再次确认年龄'),
        content: Text(_confirmMessage(range)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('重新选择'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认无误'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (range == AgeRange.under14) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const AgeGateBlockedScreen()),
        );
      } else {
        Navigator.pop(context, range);
      }
    } else {
      setState(() => _selected = null);
    }
  }

  String _confirmMessage(AgeRange range) {
    switch (range) {
      case AgeRange.under14:
        return '你选择的是「14岁以下」。\n\n'
            '根据规定，14岁以下禁止使用此应用。请确认是否继续。';
      case AgeRange.age15to18:
        return '你选择的是「15-18岁」（功能受限）。\n\n'
            '在此年龄段，你仅可使用非恋人陪伴功能，'
            '恋人模式和成人内容不可用。\n\n'
            '请再次确认：你选择的年龄是真实的。'
            '虚假申报导致的全部风险和责任由你和监护人承担。';
      case AgeRange.over18:
        return '你选择的是「18岁以上」（全部功能）。\n\n'
            '请再次确认：你已年满18周岁，选择的年龄是真实的。'
            '虚假申报导致的全部风险和责任由你和监护人承担。';
    }
  }
}
