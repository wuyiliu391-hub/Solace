import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/phone_app_icons.dart';
import '../../widgets/phone/phone_app_icon.dart';

/// 图标预览页：检查 AI 出图是否加载成功，一键复制 Prompt。
///
/// 入口可在设置/发现临时挂上，出图验收完可保留给设计师用。
class PhoneIconPreviewScreen extends StatelessWidget {
  const PhoneIconPreviewScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
        builder: (_) => const PhoneIconPreviewScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final p0 = PhoneAppIconCatalog.byPriority(PhoneIconPriority.p0);
    final p1 = PhoneAppIconCatalog.byPriority(PhoneIconPriority.p1);
    final p2 = PhoneAppIconCatalog.byPriority(PhoneIconPriority.p2);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF7EC8E3),
              Color(0xFFB8DFF0),
              Color(0xFFE8F6FC),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                pinned: true,
                title: const Text('桌面图标预览'),
                actions: [
                  IconButton(
                    tooltip: '复制全部 P0 Prompt',
                    onPressed: () => _copyBatch(context, p0),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    '将 AI 图放到 assets/phone_icons/generated/{id}.webp\n'
                    '有图显示插画，无图显示玻璃占位。点图标复制单条 Prompt。',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              _section('Dock 预览', PhoneAppIconCatalog.defaultDockIds),
              _sectionLabel('P0 优先出图'),
              _grid(p0),
              _sectionLabel('P1'),
              _grid(p1),
              _sectionLabel('P2'),
              _grid(p2),
              _sectionLabel('桌面网格默认布局'),
              _section('首页', PhoneAppIconCatalog.homePage1Ids),
              _section('第二页', PhoneAppIconCatalog.homePage2Ids),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sectionLabel(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  static Widget _section(String title, List<String> ids) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 14,
              children: [
                for (final id in ids)
                  PhoneAppIcon.fromId(
                    id,
                    size: 64,
                    onTap: () {},
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _grid(List<PhoneAppIconDef> defs) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          crossAxisSpacing: 6,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final def = defs[i];
            return PhoneAppIcon(
              def: def,
              size: 64,
              isNew: def.priority == PhoneIconPriority.p0,
              onTap: () => _copyOne(context, def),
            );
          },
          childCount: defs.length,
        ),
      ),
    );
  }

  static Future<void> _copyOne(BuildContext context, PhoneAppIconDef def) async {
    final text = PhoneAppIconCatalog.buildAiPrompt(def);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 Prompt：${def.id}（${def.label}）'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static Future<void> _copyBatch(
      BuildContext context, List<PhoneAppIconDef> defs) async {
    final buf = StringBuffer();
    for (final d in defs) {
      buf.writeln('===== ${d.id} / ${d.label} =====');
      buf.writeln(PhoneAppIconCatalog.buildAiPrompt(d));
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${defs.length} 条 P0 Prompt'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
