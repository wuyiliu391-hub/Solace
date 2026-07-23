import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/proactive_scheduler.dart';
import '../../services/voice_clone_service.dart';

class InteractionSettingsScreen extends StatefulWidget {
  final AICharacter character;
  final String sessionId;

  const InteractionSettingsScreen({
    super.key,
    required this.character,
    required this.sessionId,
  });

  @override
  State<InteractionSettingsScreen> createState() =>
      _InteractionSettingsScreenState();
}

class _InteractionSettingsScreenState extends State<InteractionSettingsScreen> {
  bool _enableMorningGreeting = true;
  bool _enableNightGreeting = true;
  bool _enableFestivalGreeting = true;
  bool _enableCareReminder = true;
  bool _enableMomentInteraction = true;
  bool _enableUserMomentInteraction = true;
  int _activeMessageFrequency = 2;
  ReplyMode _replyMode = ReplyMode.normal;
  int _replyDelaySeconds = 5;
  bool _voiceReplyEnabled = false;
  bool _enableStickerReply = true;
  bool _enableProactiveDevice = true;
  bool _enableReadNotifications = true;
  bool _enableLlmDesireRefine = true;
  TimeOfDay? _morningGreetingTime;
  TimeOfDay? _nightGreetingTime;
  bool _ready = false;
  bool _dirty = false;
  bool _saving = false;
  int _loadGen = 0;
  AICharacter? _latestSaved;

  @override
  void initState() {
    super.initState();
    _applyConfig(widget.character.interactionConfig);
    _loadCharacter();
  }

  void _applyConfig(AIInteractionConfig? config) {
    _enableMorningGreeting = config?.enableMorningGreeting ?? true;
    _enableNightGreeting = config?.enableNightGreeting ?? true;
    _enableFestivalGreeting = config?.enableFestivalGreeting ?? true;
    _enableCareReminder = config?.enableCareReminder ?? true;
    _enableMomentInteraction = config?.enableMomentInteraction ?? true;
    _enableUserMomentInteraction = config?.enableUserMomentInteraction ?? true;
    _activeMessageFrequency = config?.activeMessageFrequency ?? 2;
    _replyMode = config?.replyMode ?? ReplyMode.normal;
    _replyDelaySeconds = config?.replyDelaySeconds ?? 5;
    _voiceReplyEnabled = config?.voiceReplyEnabled ?? false;
    _enableStickerReply = config?.enableStickerReply ?? true;
    _enableProactiveDevice = config?.enableProactiveDevice ?? true;
    _enableReadNotifications = config?.enableReadNotifications ?? true;
    _enableLlmDesireRefine = config?.enableLlmDesireRefine ?? true;

    if (config?.morningGreetingTime != null) {
      final parts = config!.morningGreetingTime!.split(':');
      if (parts.length == 2) {
        _morningGreetingTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    } else {
      _morningGreetingTime = const TimeOfDay(hour: 8, minute: 0);
    }

    if (config?.nightGreetingTime != null) {
      final parts = config!.nightGreetingTime!.split(':');
      if (parts.length == 2) {
        _nightGreetingTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 22,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    } else {
      _nightGreetingTime = const TimeOfDay(hour: 22, minute: 0);
    }
  }

  Future<void> _loadCharacter() async {
    final gen = ++_loadGen;
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final fresh = await storage.getAICharacter(widget.character.id);
      // 用户已改过设置时，禁止用旧的 DB 快照覆盖 UI（竞态根因）
      if (!mounted || gen != _loadGen || _dirty) return;
      if (fresh != null) {
        setState(() {
          _applyConfig(fresh.interactionConfig);
          _ready = true;
        });
      } else if (mounted) {
        setState(() => _ready = true);
      }
    } catch (_) {
      if (mounted && gen == _loadGen) setState(() => _ready = true);
    }
  }

  AIInteractionConfig _buildConfig() {
    final morningStr =
        '${_morningGreetingTime?.hour.toString().padLeft(2, '0')}:${_morningGreetingTime?.minute.toString().padLeft(2, '0')}';
    final nightStr =
        '${_nightGreetingTime?.hour.toString().padLeft(2, '0')}:${_nightGreetingTime?.minute.toString().padLeft(2, '0')}';
    return AIInteractionConfig(
      enableMorningGreeting: _enableMorningGreeting,
      enableNightGreeting: _enableNightGreeting,
      enableFestivalGreeting: _enableFestivalGreeting,
      enableCareReminder: _enableCareReminder,
      enableMomentInteraction: _enableMomentInteraction,
      enableUserMomentInteraction: _enableUserMomentInteraction,
      activeMessageFrequency: _activeMessageFrequency,
      morningGreetingTime: morningStr,
      nightGreetingTime: nightStr,
      replyMode: _replyMode,
      replyDelaySeconds: _replyDelaySeconds,
      voiceReplyEnabled: _voiceReplyEnabled,
      enableStickerReply: _enableStickerReply,
      enableProactiveDevice: _enableProactiveDevice,
      enableReadNotifications: _enableReadNotifications,
      enableLlmDesireRefine: _enableLlmDesireRefine,
    );
  }

  Future<AICharacter?> _saveSettings() async {
    if (_saving) return _latestSaved;
    setState(() => _saving = true);
    try {
      final config = _buildConfig();
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final freshCharacter = await storage.getAICharacter(widget.character.id);
      final baseCharacter = freshCharacter ?? widget.character;
      final updatedCharacter = baseCharacter.copyWith(
        interactionConfig: config,
        updatedAt: DateTime.now(),
      );

      await storage.saveAICharacter(updatedCharacter);

      // 回读校验，确保真正落库
      final verified = await storage.getAICharacter(widget.character.id);
      final saved = verified ?? updatedCharacter;
      _latestSaved = saved;
      _dirty = false;

      final scheduler = ProactiveScheduler(storage);
      scheduler.cancelAllForCharacter(widget.character.id);
      unawaited(scheduler.scheduleAllGreetings().catchError((_) {}));
      unawaited(scheduler.scheduleAITransfers().catchError((_) {}));
      return saved;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSettingsWithFeedback(String message) async {
    try {
      final saved = await _saveSettings();
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败'), backgroundColor: Colors.red),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveAndClose() async {
    try {
      final saved = await _saveSettings();
      if (!mounted) return;
      Navigator.pop(context, saved ?? true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _popWithResult() async {
    if (_dirty && !_saving) {
      try {
        await _saveSettings();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context, _latestSaved ?? true);
  }

  Future<void> _pickTime({required bool isMorning}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isMorning
          ? (_morningGreetingTime ?? const TimeOfDay(hour: 8, minute: 0))
          : (_nightGreetingTime ?? const TimeOfDay(hour: 22, minute: 0)),
    );

    if (picked != null && mounted) {
      setState(() {
        _dirty = true;
        if (isMorning) {
          _morningGreetingTime = picked;
        } else {
          _nightGreetingTime = picked;
        }
      });
      final label = isMorning ? '早安' : '晚安';
      await _saveSettingsWithFeedback(
          '$label时间已保存为 ${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Widget buildSettingsCard({required List<Widget> children}) {
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
    }

    Widget buildDivider() {
      return Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant);
    }

    Widget buildTile({
      required String title,
      required Widget trailing,
      Color? titleColor,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      color: titleColor ?? colorScheme.onSurface)),
              trailing,
            ],
          ),
        ),
      );
    }

    Widget buildSwitchTile({
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, color: colorScheme.onSurface)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.5))),
                    ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
              activeTrackColor: colorScheme.primary.withOpacity(0.35),
              inactiveThumbColor:
                  isDark ? const Color(0xFF555555) : const Color(0xFFE0E0E0),
              inactiveTrackColor:
                  isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );
    }

    Widget buildNumberInputTile({
      required String title,
      required int value,
      required ValueChanged<int> onChanged,
      String? suffixTag,
      String? description,
      Future<void> Function()? onSubmitted,
    }) {
      final controller = TextEditingController(text: value.toString());
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style:
                        TextStyle(fontSize: 15, color: colorScheme.onSurface)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 32,
                      child: TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            fontSize: 14, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: colorScheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: colorScheme.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: colorScheme.primary, width: 1.2),
                          ),
                        ),
                        onSubmitted: (s) async {
                          final n = int.tryParse(s) ?? value;
                          onChanged(n > 0 ? n : value);
                          if (onSubmitted != null) await onSubmitted();
                        },
                      ),
                    ),
                    if (suffixTag != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(suffixTag,
                            style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outlineVariant,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(description!,
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.4))),
              ),
          ],
        ),
      );
    }

    Widget buildTimeTile({
      required String title,
      required String subtitle,
      TimeOfDay? time,
      required VoidCallback onTap,
      bool? isEnabled,
    }) {
      final timeStr = time != null ? time.format(context) : '未设置';
      final displayText = (isEnabled ?? true) ? timeStr : '已禁用';

      return InkWell(
        onTap: (isEnabled ?? true) ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15, color: colorScheme.onSurface)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayText,
                    style: TextStyle(
                      fontSize: 14,
                      color: (isEnabled ?? true)
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant, size: 20),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSaveButton() {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _saving ? null : _saveAndClose,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('保存设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _popWithResult,
                    child: Icon(Icons.arrow_back_ios,
                        size: 20, color: colorScheme.onSurface),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '互动设置',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 16),

                  // 主动消息设置
                  Text('主动消息',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary)),
                  const SizedBox(height: 8),
                  buildSettingsCard(children: [
                    buildSwitchTile(
                      title: '角色主动发消息',
                      subtitle: '开启后TA会主动找你聊天',
                      value: _enableMomentInteraction,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableMomentInteraction = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启角色主动发消息' : '已关闭角色主动发消息');
                      },
                    ),
                    if (_enableMomentInteraction) ...[
                      buildDivider(),
                      buildNumberInputTile(
                        title: '互动频率',
                        value: _activeMessageFrequency,
                        suffixTag: '小时',
                        description: '每隔多久TA会主动发消息',
                        onChanged: (v) => setState(() {
                          _dirty = true;
                          _activeMessageFrequency = v;
                        }),
                        onSubmitted: () => _saveSettingsWithFeedback(
                            '互动频率已保存为$_activeMessageFrequency小时'),
                      ),
                    ],
                    buildDivider(),
                    buildSwitchTile(
                      title: '朋友圈互动',
                      subtitle: '发动态后TA会来点赞评论',
                      value: _enableUserMomentInteraction,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableUserMomentInteraction = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启朋友圈互动' : '已关闭朋友圈互动');
                      },
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // 问候设置
                  Text('定时问候',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary)),
                  const SizedBox(height: 8),
                  buildSettingsCard(children: [
                    buildSwitchTile(
                      title: '早安问候',
                      subtitle: '每天早上向你问好',
                      value: _enableMorningGreeting,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableMorningGreeting = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启早安问候' : '已关闭早安问候');
                      },
                    ),
                    if (_enableMorningGreeting) ...[
                      buildDivider(),
                      buildTimeTile(
                        title: '早安时间',
                        subtitle: '发送早安的时间',
                        time: _morningGreetingTime,
                        isEnabled: _enableMorningGreeting,
                        onTap: () => _pickTime(isMorning: true),
                      ),
                    ],
                    buildDivider(),
                    buildSwitchTile(
                      title: '晚安问候',
                      subtitle: '每晚睡前说晚安',
                      value: _enableNightGreeting,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableNightGreeting = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启晚安问候' : '已关闭晚安问候');
                      },
                    ),
                    if (_enableNightGreeting) ...[
                      buildDivider(),
                      buildTimeTile(
                        title: '晚安时间',
                        subtitle: '发送晚安的时间',
                        time: _nightGreetingTime,
                        isEnabled: _enableNightGreeting,
                        onTap: () => _pickTime(isMorning: false),
                      ),
                    ],
                    buildDivider(),
                    buildSwitchTile(
                      title: '节日祝福',
                      subtitle: '重要节日发送祝福',
                      value: _enableFestivalGreeting,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableFestivalGreeting = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启节日祝福' : '已关闭节日祝福');
                      },
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // 回复设置
                  Text('回复行为',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary)),
                  const SizedBox(height: 8),
                  buildSettingsCard(children: [
                    buildSwitchTile(
                      title: '手动回复模式',
                      subtitle: '需要上滑才触发回复',
                      value: _replyMode == ReplyMode.manual,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _replyMode =
                              v ? ReplyMode.manual : ReplyMode.normal;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启手动回复模式' : '已关闭手动回复模式');
                      },
                    ),
                    buildDivider(),
                    buildSwitchTile(
                      title: '等待你回复提醒',
                      subtitle: '长时间未回复时提醒你',
                      value: _enableCareReminder,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableCareReminder = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启等待你回复提醒' : '已关闭等待你回复提醒');
                      },
                    ),
                    buildDivider(),
                    buildSwitchTile(
                      title: 'AI 表情包回复',
                      subtitle: '允许AI在回复中附带表情包',
                      value: _enableStickerReply,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableStickerReply = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启AI表情包回复' : '已关闭AI表情包回复');
                      },
                    ),
                    buildDivider(),
                    buildSwitchTile(
                      title: '主动设备操控',
                      subtitle: '允许该角色在聊天中主动操控设备（仍受全局开关约束）',
                      value: _enableProactiveDevice,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableProactiveDevice = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启主动设备操控' : '已关闭主动设备操控');
                      },
                    ),
                    buildDivider(),
                    buildSwitchTile(
                      title: '允许读取通知',
                      subtitle: '该角色可因好奇/查岗类动机读通知摘要',
                      value: _enableReadNotifications,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableReadNotifications = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启允许读取通知' : '已关闭允许读取通知');
                      },
                    ),
                    buildDivider(),
                    buildSwitchTile(
                      title: 'LLM 精炼欲望画像',
                      subtitle: '人设变更时用模型分析动机权重（有缓存，非每轮）',
                      value: _enableLlmDesireRefine,
                      onChanged: (v) async {
                        setState(() {
                          _dirty = true;
                          _enableLlmDesireRefine = v;
                        });
                        await _saveSettingsWithFeedback(
                            v ? '已开启LLM精炼欲望画像' : '已关闭LLM精炼欲望画像');
                      },
                    ),
                    if (_replyMode == ReplyMode.normal) ...[
                      buildDivider(),
                      buildNumberInputTile(
                        title: '回复延迟',
                        value: _replyDelaySeconds,
                        suffixTag: '秒',
                        description: '模拟打字时间的延迟',
                        onChanged: (v) => setState(() {
                          _dirty = true;
                          _replyDelaySeconds = v.clamp(1, 30);
                        }),
                        onSubmitted: () => _saveSettingsWithFeedback(
                            '回复延迟已保存为$_replyDelaySeconds秒'),
                      ),
                    ],
                  ]),

                  // AI 语音回复（始终显示，让用户自主选择）
                  const SizedBox(height: 16),
                  Text('语音回复',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary)),
                  const SizedBox(height: 8),
                  buildSettingsCard(children: [
                    buildSwitchTile(
                      title: 'AI 语音回复',
                      subtitle:
                          VoiceCloneService().hasVoice(widget.character.id)
                              ? '开启后AI会发送语音消息（像微信语音条）'
                              : '尚未配置音色，请先上传音色样本',
                      value: _voiceReplyEnabled,
                      onChanged:
                          VoiceCloneService().hasVoice(widget.character.id)
                              ? (v) async {
                                  setState(() {
                                    _dirty = true;
                                    _voiceReplyEnabled = v;
                                  });
                                  await _saveSettingsWithFeedback(
                                      v ? '已开启语音回复' : '已关闭语音回复');
                                }
                              : (_) {}, // 无音色时点击无效果
                    ),
                  ]),

                  const SizedBox(height: 16),

                  const SizedBox(height: 24),
                  buildSaveButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
