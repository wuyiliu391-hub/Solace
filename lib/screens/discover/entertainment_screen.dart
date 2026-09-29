import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';

/// 娱乐互动页面 — 降压维护后仅保留轻量入口（塔罗 / 故事书）
class EntertainmentScreen extends StatefulWidget {
  final Function(String)? onNavigate;
  const EntertainmentScreen({super.key, this.onNavigate});

  @override
  State<EntertainmentScreen> createState() => _EntertainmentScreenState();
}

class _EntertainmentScreenState extends State<EntertainmentScreen> {
  List<AICharacter> _characters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();
    if (mounted) {
      setState(() {
        _characters = characters.where((c) => !c.isHidden).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('娱乐互动'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCharacters,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_characters.isNotEmpty) ...[
                    Text('选择角色开始互动',
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _characters.length,
                        itemBuilder: (context, index) {
                          return _CharacterPickerCard(
                              character: _characters[index]);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text('更多娱乐',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _QuickEntryTile(
                    icon: Icons.auto_fix_high,
                    title: '塔罗牌',
                    subtitle: '每日占卜，预见未来',
                    color: const Color(0xFF7E57C2),
                    onTap: () => widget.onNavigate?.call('/tarot'),
                  ),
                  _QuickEntryTile(
                    icon: Icons.auto_stories,
                    title: '故事书',
                    subtitle: '与角色共创故事（走塔罗占卜入口）',
                    color: const Color(0xFF42A5F5),
                    onTap: () => widget.onNavigate?.call('/tarot'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CharacterPickerCard extends StatelessWidget {
  final AICharacter character;
  const _CharacterPickerCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final name = character.userAlias ?? character.name;
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: AvatarResolver.imageProvider(character.avatarUrl),
            child: AvatarResolver.imageProvider(character.avatarUrl) == null
                ? Text(name.isNotEmpty ? name[0] : '?')
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _QuickEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      trailing:
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
      onTap: onTap,
    );
  }
}
