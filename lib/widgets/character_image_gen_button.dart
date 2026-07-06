import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/chat/chat_bloc.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../repositories/local_storage_repository.dart';
import '../models/app_config_data.dart';
import '../services/character_image_pipeline.dart';
import '../services/llm_service.dart';
/// 角色画面生成浮动按钮组件
///
/// 在对话页 AppBar 的 actions 中添加此按钮，
/// 点击后自动执行完整生图链路：
///   读取角色信息 → 读取聊天记录 → 生成精准prompt →
///   锚定人物形象 → 调用模型出图 → 返回展示
class CharacterImageGenButton extends StatefulWidget {
  final AICharacter character;
  final List<ChatMessage> recentMessages;
  final String userId;
  final VoidCallback? onImageGenerated;
  final VoidCallback? onError;

  const CharacterImageGenButton({
    super.key,
    required this.character,
    required this.recentMessages,
    required this.userId,
    this.onImageGenerated,
    this.onError,
  });

  @override
  State<CharacterImageGenButton> createState() => _CharacterImageGenButtonState();
}

class _CharacterImageGenButtonState extends State<CharacterImageGenButton> {
  bool _isGenerating = false;

  Future<void> _generateImage() async {
    if (_isGenerating) return;

    // API Key 由服务层内置，无需用户配置

    setState(() => _isGenerating = true);

    try {
      final pipeline = CharacterImagePipeline();

      // 注入 LLM 服务（从本地存储获取当前活跃配置）
      try {
        final storage = context.read<LocalStorageRepository>();
        final activeConfig = await storage.getActiveAIConfig();
        if (activeConfig != null) {
          final llmSettings = LlmSettings(
            apiKey: activeConfig.apiKey,
            baseUrl: activeConfig.baseUrl,
            model: activeConfig.modelName,
            maxTokens: activeConfig.maxTokens,
            temperature: activeConfig.temperature,
          );
          final llmService = LlmService(settings: llmSettings);
          pipeline.setLlmService(llmService);
        }
      } catch (_) {}

      // 显示场景输入对话框
      if (!mounted) return;
      final instruction = await _showSceneInputDialog();
      if (instruction == null) {
        setState(() => _isGenerating = false);
        return;
      }

      // 显示加载提示
      if (!mounted) return;
      _showLoadingDialog();

      final result = await pipeline.generate(
        character: widget.character,
        recentMessages: widget.recentMessages,
        userInstruction: instruction.isNotEmpty ? instruction : null,
        userId: widget.userId,
      );

      // 关闭加载提示
      if (mounted) Navigator.of(context).pop();

      if (result.isSuccess) {
        widget.onImageGenerated?.call();
        if (mounted) {
          _showImageResult(result.imagePath!, result.prompt ?? '');
        }
      } else {
        widget.onError?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.errorMessage ?? '生成失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<String?> _showSceneInputDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('生成角色画面'),
        content: TextField(
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '描述想要的场景（可选）\n如：在樱花树下微笑、在咖啡厅看书...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              // 直接生成，不填场景
              Navigator.of(ctx).pop('');
            },
            child: const Text('直接生成'),
          ),
        ],
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在生成角色画面...'),
                SizedBox(height: 8),
                Text('读取角色信息 → 分析对话上下文 → AI绘画中',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showImageResult(String imagePath, String prompt) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                prompt,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('关闭'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    // TODO: 保存到相册
                    Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.save_alt),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isGenerating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.image_outlined),
      tooltip: '生成角色当前画面',
      onPressed: _isGenerating ? null : _generateImage,
    );
  }
}