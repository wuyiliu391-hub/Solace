import 'dart:io';

void main() {
  final path = r'c:\Users\Administrator\Desktop\Solace\lib\services\ai_service.dart';
  final content = File(path).readAsStringSync();
  
  // Find time-related code
  final timeIdx = content.indexOf('当前时间');
  if (timeIdx == -1) {
    print('当前时间 NOT FOUND');
    return;
  }
  print('Found 当前时间 at offset $timeIdx');
  
  // Show 200 chars before
  final start = timeIdx - 300;
  if (start >= 0) {
    print('\n--- 300 chars before 当前时间 ---');
    print(content.substring(start, timeIdx));
  }
  
  // Show the time block
  print('\n--- From 当前时间 onwards (500 chars) ---');
  print(content.substring(timeIdx, timeIdx + 500));
  
  // Find the exact line with DateTime.now
  final dtIdx = content.indexOf('DateTime.now()', timeIdx - 500);
  if (dtIdx != -1) {
    print('\nDateTime.now() found at offset $dtIdx');
    // Show context
    final lineStart = content.lastIndexOf('\n', dtIdx) + 1;
    final lineEnd = content.indexOf('\n', dtIdx);
    print('Line: ${content.substring(lineStart, lineEnd)}');
  }
  
  // Find all occurrences of timeNow
  var searchFrom = 0;
  while (true) {
    final idx = content.indexOf('timeNow', searchFrom);
    if (idx == -1) break;
    final lineStart = content.lastIndexOf('\n', idx) + 1;
    final lineEnd = content.indexOf('\n', idx);
    print('timeNow at $idx: ${content.substring(lineStart, lineEnd).trim()}');
    searchFrom = idx + 1;
  }
  
  // Find all occurrences of timeHour
  searchFrom = 0;
  while (true) {
    final idx = content.indexOf('timeHour', searchFrom);
    if (idx == -1) break;
    final lineStart = content.lastIndexOf('\n', idx) + 1;
    final lineEnd = content.indexOf('\n', idx);
    print('timeHour at $idx: ${content.substring(lineStart, lineEnd).trim()}');
    searchFrom = idx + 1;
  }
  
  // Find timePeriod
  searchFrom = 0;
  while (true) {
    final idx = content.indexOf('timePeriod', searchFrom);
    if (idx == -1) break;
    final lineStart = content.lastIndexOf('\n', idx) + 1;
    final lineEnd = content.indexOf('\n', idx);
    print('timePeriod at $idx: ${content.substring(lineStart, lineEnd).trim()}');
    searchFrom = idx + 1;
  }
}