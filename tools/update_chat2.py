repo = r"C:\Users\Administrator\Desktop\solace\lib\screens\chat\chat_detail_screen.dart"
with open(repo, "r", encoding="utf-8-sig") as f:
    content = f.read()

# Find and replace the gallery save section
# The exact text after saveChatMessage(imageMsg)
old_text = "        await storage.saveChatMessage(imageMsg);\n\n        // 6."
new_text = """        await storage.saveChatMessage(imageMsg);

        // 5.5 归档到角色图片画廊
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
          debugPrint('[Gallery] archive failed: $e');
        }

        // 6."""

if old_text in content:
    content = content.replace(old_text, new_text)
    print("Gallery save added!")
else:
    print("Pattern not found, trying line-by-line approach")
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if 'saveChatMessage(imageMsg)' in line and i > 1900 and i < 2000:
            print(f"Found at line {i}: {line.strip()}")
            # Check next line
            print(f"Next line: {lines[i+1].strip()}")
            print(f"Line+2: {lines[i+2].strip()}")

with open(repo, "w", encoding="utf-8") as f:
    f.write(content)