repo = r"C:\Users\Administrator\Desktop\solace\lib\screens\chat\chat_detail_screen.dart"
with open(repo, "r", encoding="utf-8-sig") as f:
    content = f.read()

# 1. Add imports for new services
old_import = "import '../../services/image_prompt_engine.dart';"
new_import = """import '../../services/image_prompt_engine.dart';
import '../../services/character_image_pipeline.dart';
import '../../config/gender_prompt_config.dart';"""

if old_import in content and "character_image_pipeline" not in content:
    content = content.replace(old_import, new_import)
    print("Step 1: imports added")
else:
    print("Step 1: skipped (already exists or not found)")

# 2. Update _handleImageGeneration to use enhanced negative prompt and gallery save
old_gen = """      // 4. 判断使用文生图还是图生图（有参考图时用图生图锚定）
      AgnesImageResult result;
      if (character.referenceImg != null && character.referenceImg!.isNotEmpty) {"""

new_gen = """      // 4. 注入 LLM 服务（启用智能 Prompt 翻译）
      try {
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthLoaded) {
          ImagePromptEngine.setLlmService(
            LlmService(settings: authState.activeLlmSettings),
          );
        }
      } catch (_) {}

      // 5. 判断使用文生图还是图生图（有参考图时用图生图锚定）
      AgnesImageResult result;
      final enhancedNegative = await ImagePromptEngine.getEnhancedNegativePrompt(character);
      if (character.referenceImg != null && character.referenceImg!.isNotEmpty) {"""

if old_gen in content and "注入 LLM 服务" not in content:
    content = content.replace(old_gen, new_gen)
    print("Step 2: LLM injection added")
else:
    print("Step 2: skipped")

# 3. After saving the image message, add gallery save
old_save = """        await storage.saveChatMessage(imageMsg);

        // 6. 同步保存用户消息"""
new_save = """        await storage.saveChatMessage(imageMsg);

        // 5.5 归档到角色图片画廊（自动归档，不影响主流程）
        try {
          final galleryImage = {
            'id': imageMsg.id,
            'characterId': character.id,
            'userId': user.id,
            'localPath': result.imagePath!,
            'promptUsed': 'generated',
            'sceneDescription': userMessage,
            'referenceImagePath': character.referenceImg,
            'generationSeed': character.fixedSeed,
            'resolution': await ImageGenConfig.defaultResolution,
            'styleLock': character.styleLock,
            'createdAt': DateTime.now().toIso8601String(),
            'isFavorite': 0,
          };
          await storage.insertCharacterImage(galleryImage);
        } catch (e) {
          debugPrint('[Gallery] 画廊归档失败（不影响主流程）: $e');
        }

        // 6. 同步保存用户消息"""

if old_save in content and "角色图片画廊" not in content:
    content = content.replace(old_save, new_save)
    print("Step 3: gallery save added")
else:
    print("Step 3: skipped")

with open(repo, "w", encoding="utf-8") as f:
    f.write(content)
print("Chat screen updated!")