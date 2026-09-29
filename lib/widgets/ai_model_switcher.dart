import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ai_config.dart';
import '../repositories/local_storage_repository.dart';
import '../screens/settings/ai_config_screen.dart';

/// 聊天页通用「当前模型」切换入口。
/// 设置里配置过的供应商均可一键切换，模型挂了不用跳出聊天去设置页。
class AiModelSwitcher extends StatefulWidget {
  final Color? iconColor;

  const AiModelSwitcher({super.key, this.iconColor});

  @override
  State<AiModelSwitcher> createState() => _AiModelSwitcherState();
}

class _AiModelSwitcherState extends State<AiModelSwitcher> {
  AIConfig? _active;
  List<AIConfig> _all = const [];
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await storage.getAllAIConfigs();
    if (!mounted) return;
    setState(() {
      _all = all;
      _active = all.cast<AIConfig?>().firstWhere(
            (c) => c?.isActive == true,
            orElse: () => null,
          );
      _loading = false;
    });
  }

  String get _shortLabel {
    if (_loading) return '模型';
    final model = _active?.modelName.trim() ?? '';
    if (model.isEmpty) return '未配置';
    if (model.length <= 10) return model;
    return '${model.substring(0, 10)}…';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.iconColor ?? Theme.of(context).iconTheme.color;
    return TextButton.icon(
      onPressed: () => AiModelPicker.show(context, onChanged: _load),
      icon: Icon(Icons.memory_rounded, size: 18, color: color),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: Text(
          _shortLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 底部弹层：列出全部已配置 AI，点选即切换全局生效模型。
class AiModelPicker {
  const AiModelPicker._();

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onChanged,
  }) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final configs = await storage.getAllAIConfigs();
    if (!context.mounted) return;

    if (configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('尚未配置 AI 供应商，请先到设置 → AI 配置添加'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final activeId = configs
        .cast<AIConfig?>()
        .firstWhere((c) => c?.isActive == true, orElse: () => null)
        ?.id;

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final maxH = media.size.height * 0.70;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.memory_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '切换模型（全局生效）',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AIConfigScreen(),
                            ),
                          );
                        },
                        child: const Text('管理配置', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH - 72),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: configs.length,
                      itemBuilder: (_, i) {
                        final c = configs[i];
                        final selected = c.id == activeId;
                        final family = c.modelFamily;
                        return ListTile(
                          leading: Icon(
                            _familyIcon(family),
                            color: selected
                                ? Theme.of(sheetContext).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            c.modelName.isEmpty ? '(未命名模型)' : c.modelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (c.providerName.trim().isNotEmpty)
                                c.providerName.trim(),
                              _hostOf(c.baseUrl),
                              if (c.isThinkingModel) '推理',
                              if (c.faOverseasBoost) '海外',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: selected
                              ? Icon(Icons.check_circle_rounded,
                                  color:
                                      Theme.of(sheetContext).colorScheme.primary)
                              : null,
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _activate(storage, configs, c);
                            onChanged?.call();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已切换到 ${c.modelName.isEmpty ? c.providerName : c.modelName}',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _activate(
    LocalStorageRepository storage,
    List<AIConfig> all,
    AIConfig target,
  ) async {
    for (final c in all) {
      if (c.id != target.id && c.isActive) {
        await storage.saveAIConfig(c.copyWith(isActive: false));
      }
    }
    await storage.saveAIConfig(target.copyWith(isActive: true));
  }

  static String _hostOf(String baseUrl) {
    try {
      final uri = Uri.parse(baseUrl.trim());
      return uri.host.isEmpty ? baseUrl : uri.host;
    } catch (_) {
      return baseUrl;
    }
  }

  static IconData _familyIcon(ModelFamily family) {
    switch (family) {
      case ModelFamily.openai:
        return Icons.bolt_rounded;
      case ModelFamily.anthropic:
        return Icons.psychology_alt_outlined;
      case ModelFamily.google:
        return Icons.auto_awesome_outlined;
      case ModelFamily.xai:
        return Icons.blur_on_rounded;
      case ModelFamily.domestic:
        return Icons.cloud_outlined;
      case ModelFamily.other:
        return Icons.hub_outlined;
    }
  }
}
