import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../blocs/group_chat/group_chat_event.dart';
import '../../models/group_chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/scenario_service.dart';

class GroupChatSettingsScreen extends StatefulWidget {
  final GroupChatSession session;

  const GroupChatSettingsScreen({super.key, required this.session});

  @override
  State<GroupChatSettingsScreen> createState() => _GroupChatSettingsScreenState();
}

class _GroupChatSettingsScreenState extends State<GroupChatSettingsScreen> {
  late GroupChatSession _session;
  final _nameController = TextEditingController();
  final List<ScenarioTemplate> _templates = ScenarioService.getTemplates();
  
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _nameController.text = _session.name;
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_nameController.text != _session.name) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveSettings() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      
      // 更新会话名称
      final updatedSession = _session.copyWith(
        name: _nameController.text.trim(),
        loverModeEnabled: _session.loverModeEnabled,
        openModeEnabled: _session.openModeEnabled,
        faModeEnabled: _session.faModeEnabled,
        daoModeEnabled: _session.daoModeEnabled,
      );
      
      await storage.saveGroupChatSession(updatedSession);
      
      // 通知BLoC刷新
      if (mounted) {
        context.read<GroupChatBloc>().add(GroupChatLoadSessions(_session.userId));
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleMode(String mode) {
    setState(() {
      switch (mode) {
        case 'lover':
          _session = _session.copyWith(loverModeEnabled: !_session.loverModeEnabled);
          break;
        case 'open':
          _session = _session.copyWith(openModeEnabled: !_session.openModeEnabled);
          break;
        case 'fa':
          _session = _session.copyWith(faModeEnabled: !_session.faModeEnabled);
          break;
        case 'dao':
          _session = _session.copyWith(daoModeEnabled: !_session.daoModeEnabled);
          break;
      }
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('酒馆设置'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: const Text('保存'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 酒馆名称
          _buildSectionTitle('酒馆名称', colorScheme),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: '输入酒馆名称',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),

          // 场景设置
          _buildSectionTitle('场景设定', colorScheme),
          const SizedBox(height: 8),
          _buildScenarioCard(colorScheme),
          const SizedBox(height: 24),

          // 功能模式
          _buildSectionTitle('功能模式', colorScheme),
          const SizedBox(height: 8),
          _buildModeCard(
            colorScheme: colorScheme,
            icon: Icons.favorite,
            iconColor: Colors.pink,
            title: '恋人模式',
            subtitle: '开启亲密互动和恋爱氛围',
            isEnabled: _session.loverModeEnabled,
            onToggle: () => _toggleMode('lover'),
          ),
          const SizedBox(height: 8),
          _buildModeCard(
            colorScheme: colorScheme,
            icon: Icons.lock_open,
            iconColor: Colors.green,
            title: '开放模式',
            subtitle: '允许更自由的对话内容',
            isEnabled: _session.openModeEnabled,
            onToggle: () => _toggleMode('open'),
          ),
          const SizedBox(height: 8),
          _buildModeCard(
            colorScheme: colorScheme,
            icon: Icons.balance,
            iconColor: Colors.orange,
            title: '法模式',
            subtitle: '成人向内容（需年满18岁）',
            isEnabled: _session.faModeEnabled,
            onToggle: () => _toggleMode('fa'),
          ),
          const SizedBox(height: 8),
          _buildModeCard(
            colorScheme: colorScheme,
            icon: Icons.auto_fix_high,
            iconColor: Colors.purple,
            title: '刀模式',
            subtitle: '虐心悲剧向剧情演绎',
            isEnabled: _session.daoModeEnabled,
            onToggle: () => _toggleMode('dao'),
          ),
          const SizedBox(height: 24),

          // 回复模式
          _buildSectionTitle('回复模式', colorScheme),
          const SizedBox(height: 8),
          _buildReplyModeCard(colorScheme),
          const SizedBox(height: 24),

          // 参与角色
          _buildSectionTitle('参与角色', colorScheme),
          const SizedBox(height: 8),
          _buildParticipantsCard(colorScheme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildScenarioCard(ColorScheme colorScheme) {
    final currentTemplate = _session.scenarioTemplate != null
        ? _templates.firstWhere(
            (t) => t.id == _session.scenarioTemplate,
            orElse: () => _templates.first,
          )
        : null;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: _showScenarioPicker,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: currentTemplate?.icon != null
                      ? Text(
                          currentTemplate!.icon,
                          style: const TextStyle(fontSize: 24),
                        )
                      : const Icon(Icons.location_on, size: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTemplate?.name ?? '自定义场景',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentTemplate?.description ?? _session.scenario ?? '未设置场景',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScenarioPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '选择场景',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._templates.map((template) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.location_city, color: Colors.white),
                ),
                title: Text(template.name),
                subtitle: Text(
                  template.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _session.scenarioTemplate == template.id
                    ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() {
                    _session = _session.copyWith(
                      scenarioTemplate: template.id,
                      scenario: template.description,
                    );
                    _hasChanges = true;
                  });
                  Navigator.pop(ctx);
                },
              )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required VoidCallback onToggle,
  }) {
    return Card(
      elevation: 0,
      color: isEnabled
          ? iconColor.withOpacity(0.1)
          : colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isEnabled
            ? BorderSide(color: iconColor.withOpacity(0.5), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isEnabled ? iconColor : iconColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: isEnabled ? Colors.white : iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isEnabled ? iconColor : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: (_) => onToggle(),
                activeColor: iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyModeCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  _session.replyMode == ReplyMode.flash ? '快闪模式' : '顺序模式',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _session.replyMode == ReplyMode.flash
                  ? '单次API生成多个角色回复，模拟七嘴八舌'
                  : '角色按顺序依次回复，更有条理',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ReplyMode>(
              segments: const [
                ButtonSegment(
                  value: ReplyMode.flash,
                  label: Text('快闪'),
                  icon: Icon(Icons.flash_on),
                ),
                ButtonSegment(
                  value: ReplyMode.sequential,
                  label: Text('顺序'),
                  icon: Icon(Icons.format_list_numbered),
                ),
              ],
              selected: {_session.replyMode},
              onSelectionChanged: (Set<ReplyMode> newSelection) {
                setState(() {
                  _session = _session.copyWith(replyMode: newSelection.first);
                  _hasChanges = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantsCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ...List.generate(_session.participantIds.length, (index) {
            final name = _session.participantNames[index];
            final avatar = index < _session.participantAvatars.length
                ? _session.participantAvatars[index]
                : null;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: avatar != null ? FileImage(File(avatar)) : null,
                child: avatar == null
                    ? Text(name.characters.first)
                    : null,
              ),
              title: Text(name),
              trailing: TextButton(
                onPressed: () => _showMemberSettings(index),
                child: const Text('设置'),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showMemberSettings(int index) {
    // TODO: 实现成员单独设置
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('成员设置功能开发中')),
    );
  }
}
