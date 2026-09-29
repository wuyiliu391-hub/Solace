import 'package:flutter/material.dart';

class SafeWidget extends StatefulWidget {
  final Widget Function(BuildContext) builder;
  final Widget? fallback;

  const SafeWidget({super.key, required this.builder, this.fallback});

  @override
  State<SafeWidget> createState() => _SafeWidgetState();
}

class _SafeWidgetState extends State<SafeWidget> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  void _rebuild() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.fallback != null) return widget.fallback!;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('页面加载异常', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(onPressed: _rebuild, child: const Text('重试')),
          ],
        ),
      );
    }
    try {
      return widget.builder(context);
    } catch (e, stack) {
      debugPrint('SafeWidget caught error: $e\n$stack');
      _error = e.toString();
      return const SizedBox();
    }
  }
}
