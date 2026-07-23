import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/device_agent_action.dart';
import '../../repositories/local_storage_repository.dart';

/// Device Agent 审计日志
class DeviceAgentAuditScreen extends StatefulWidget {
  const DeviceAgentAuditScreen({super.key});

  @override
  State<DeviceAgentAuditScreen> createState() => _DeviceAgentAuditScreenState();
}

class _DeviceAgentAuditScreenState extends State<DeviceAgentAuditScreen> {
  List<DeviceAgentAction> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = context.read<LocalStorageRepository>();
    final raw = await repo.getDeviceAgentActions(limit: 100);
    final items = raw.map(DeviceAgentAction.fromMap).toList();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Color _resultColor(DeviceActionResult r, ColorScheme cs) {
    switch (r) {
      case DeviceActionResult.success:
        return Colors.green;
      case DeviceActionResult.rejected:
        return Colors.orange;
      case DeviceActionResult.failed:
        return Colors.red;
    }
  }

  String _resultLabel(DeviceActionResult r) {
    switch (r) {
      case DeviceActionResult.success:
        return '成功';
      case DeviceActionResult.rejected:
        return '拒绝';
      case DeviceActionResult.failed:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备操控审计', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    '暂无记录',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = _items[i];
                    final tool = deviceActionToToolName(a.actionType);
                    final time =
                        '${a.createdAt.month}/${a.createdAt.day} ${a.createdAt.hour.toString().padLeft(2, '0')}:${a.createdAt.minute.toString().padLeft(2, '0')}';
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tool,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _resultColor(a.result, cs).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _resultLabel(a.result),
                              style: TextStyle(
                                fontSize: 11,
                                color: _resultColor(a.result, cs),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            a.message.isEmpty
                                ? (a.rejectionReason?.name ?? a.reason)
                                : a.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                          if (a.reason.isNotEmpty)
                            Text(
                              '动机: ${a.reason}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.45),
                              ),
                            ),
                          Text(
                            '$time · ${a.category.name}'
                            '${a.sessionId.isNotEmpty ? ' · ${a.sessionId.length > 8 ? a.sessionId.substring(0, 8) : a.sessionId}' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
