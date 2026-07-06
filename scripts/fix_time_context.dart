import 'dart:io';

void main() {
  final path = r'c:\Users\Administrator\Desktop\Solace\lib\services\ai_service.dart';
  final content = File(path).readAsStringSync();
  final originalLength = content.length;
  print('Original file: $originalLength chars');

  // === Step 1: Extract the time injection block ===
  // Starts at "    final timeNow = DateTime.now();"
  final blockStart = content.indexOf('    final timeNow = DateTime.now();');
  if (blockStart == -1) {
    print('ERROR: blockStart not found');
    exit(1);
  }
  print('Block starts at offset $blockStart');

  // Find the end of time constraints block
  // After the last time constraint line, there's a closing } and blank line
  // The last constraint is "} else { buffer.writeln('【时间约束】现在是夜晚...'); }"
  // Search for the pattern: after all timeHour checks, find the final closing }
  
  // Find "请根据当前真实时间来调整你的回复"
  final instructionIdx = content.indexOf('请根据当前真实时间来调整你的回复', blockStart);
  if (instructionIdx == -1) {
    print('ERROR: instruction not found');
    exit(1);
  }

  // After the instruction, find all the if/else timeHour constraint blocks
  // The last one ends with a closing } followed by \r\n\r\n
  // Search for the pattern: '} else {\n      buffer.writeln(...);\n    }\n\n'
  // Let's find it by looking for the last timeHour reference in this block
  var lastTimeHourIdx = instructionIdx;
  var searchFrom = instructionIdx;
  while (true) {
    final idx = content.indexOf('timeHour', searchFrom);
    if (idx == -1 || idx > instructionIdx + 2000) break;
    lastTimeHourIdx = idx;
    searchFrom = idx + 1;
  }
  print('Last timeHour at offset $lastTimeHourIdx');

  // From lastTimeHourIdx, find the end of the enclosing block
  // Go forward to find the closing } of the else block, then the } of the if block
  var pos = lastTimeHourIdx;
  var braceCount = 0;
  var foundOpen = false;
  while (pos < content.length && pos < lastTimeHourIdx + 500) {
    if (content[pos] == '{') {
      braceCount++;
      foundOpen = true;
    } else if (content[pos] == '}') {
      braceCount--;
      if (foundOpen && braceCount == 0) {
        // Found the closing } of the inner else block
        // Now find the closing } of the outer if block
        pos++;
        while (pos < content.length && content[pos] != '}') pos++;
        // pos is now at the closing } of the if/else block
        // Find end of line
        var blockEnd = content.indexOf('\n', pos) + 1;
        // Skip blank lines
        while (blockEnd < content.length && (content[blockEnd] == '\n' || content[blockEnd] == '\r')) {
          blockEnd++;
        }
        
        final timeBlock = content.substring(blockStart, blockEnd);
        print('Extracted time block: ${timeBlock.length} chars (offset $blockStart to $blockEnd)');
        
        // === Step 2: Remove the time block ===
        final withoutTime = content.substring(0, blockStart) + content.substring(blockEnd);
        print('Removed time block');

        // === Step 3: Find return buffer.toString() in _buildSystemPrompt ===
        // The first return buffer.toString() after where the block was
        final returnSearch = '\r\n    return buffer.toString();\r\n';
        var returnIdx = withoutTime.indexOf(returnSearch, blockStart - 500);
        if (returnIdx == -1) {
          // Try with \n only
          final returnSearch2 = '\n    return buffer.toString();\n';
          returnIdx = withoutTime.indexOf(returnSearch2, blockStart - 500);
        }
        if (returnIdx == -1) {
          print('ERROR: return buffer.toString() not found');
          exit(1);
        }
        print('Found return at offset $returnIdx');

        // Insert time block before return
        var newContent = withoutTime.substring(0, returnIdx) + 
            '\r\n' + timeBlock + 
            withoutTime.substring(returnIdx);
        print('Inserted time block before return');

        // === Step 4: Enhance timeReminder ===
        final reminderIdx = newContent.indexOf("final timeReminder = '【此刻时间");
        if (reminderIdx == -1) {
          print('ERROR: timeReminder not found');
          exit(1);
        }
        print('Found timeReminder at offset $reminderIdx');

        // Find the end of the timeReminder line (the ;)
        var semiIdx = newContent.indexOf("';", reminderIdx + 30);
        if (semiIdx != -1) semiIdx += 2; // include ';

        // Find the messages.add block
        final addIdx = newContent.indexOf('messages.add({', semiIdx);
        final addEndIdx = newContent.indexOf('});', addIdx) + 3;

        final oldBlock = newContent.substring(reminderIdx, addEndIdx);
        print('Old timeReminder block: ${oldBlock.length} chars');

        // Build enhanced version
        final newReminder = "final timeReminder = '【此刻时间：\${now.year}年\${now.month}月\${now.day}日 "
            "'\${now.hour.toString().padLeft(2, '0')}:\${now.minute.toString().padLeft(2, '0')}】\\r\\n"
            "这是你此刻回复的唯一真实时间参考，请严格据此判断时间段，不要说错时间。';\r\n"
            "      messages.add({\r\n"
            "        'role': 'system',\r\n"
            "        'content': timeReminder,\r\n"
            "      });";

        newContent = newContent.substring(0, reminderIdx) + newReminder + newContent.substring(addEndIdx);
        print('Enhanced timeReminder');

        // === Step 5: Write ===
        File(path).writeAsStringSync(newContent);
        print('\nDone! File written.');
        print('Original: $originalLength chars -> New: ${newContent.length} chars');
        return;
      }
    }
    pos++;
  }
  print('ERROR: Could not find end of time constraint block');
}