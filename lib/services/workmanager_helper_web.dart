import 'dart:async';
import 'package:flutter/foundation.dart';

Timer? _momentPostingTimer;

Future<void> initWorkmanager() async {
  // Web 平台不支持 Workmanager，使用 Timer 回退
}

/// Web 平台启动定时朋友圈发布（前台 Timer 回退）
void startWebMomentPosting(Future<void> Function() onTick) {
  _momentPostingTimer?.cancel();
  _momentPostingTimer = Timer.periodic(
    const Duration(hours: 2),
    (_) async {
      try {
        await onTick();
      } catch (e) {
        debugPrint('Web moment posting tick failed: $e');
      }
    },
  );
  debugPrint('Web 朋友圈发布定时器已启动');
}

void stopWebMomentPosting() {
  _momentPostingTimer?.cancel();
  _momentPostingTimer = null;
}
