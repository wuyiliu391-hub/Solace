// ignore_for_file: equal_keys_in_map

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/business_rules.dart';
import '../utils/message_sanitizer.dart';
import '../utils/response_decoder.dart';
import '../utils/global_mode_prompt.dart';
import '../models/proactive_policy.dart';
import '../models/moment.dart';
import '../models/ai_character.dart';
import '../models/life/daily_schedule.dart';
import '../models/life/life_log.dart';
import '../repositories/local_storage_repository.dart';
import 'ai_service.dart';
import 'moment_interaction_service.dart';
import 'proactive_policy_service.dart';
import 'life/active_share_service.dart';
import 'life/daily_schedule_service.dart';
import 'life/life_log_service.dart';
import 'life/timed_event_service.dart';
import 'wechat/ilink_client.dart';
import 'wechat/wechat_bot_store.dart';
part 'background_parts/bg_ai_core.dart';
part 'background_parts/bg_normalize.dart';
part 'background_parts/bg_wechat.dart';
part 'background_parts/bg_maintain.dart';
part 'background_parts/bg_notify.dart';
part 'background_parts/bg_proactive.dart';
part 'background_parts/bg_moments.dart';
part 'background_parts/bg_letters.dart';
part 'background_parts/bg_comment_interact.dart';
part 'background_parts/bg_content.dart';

const String bgTaskName = 'proactiveChatMessage';
const String bgTaskMomentPost = 'aiMomentPost';
const String bgTaskCommentReply = 'aiCommentReply';
const String bgTaskMomentInteract = 'aiMomentInteract';
const String bgTaskLetter = 'aiLetter';
const String bgTaskWeChatPoll = 'wechatPoll';
const String bgTaskUnique = MethodChannels.background;
bool _foregroundProactiveRunning = false;

/// 后台 isolate 内读 SP 判断是否允许消耗（总开关 + 分项）
Future<bool> _bgUsageAllowed(String featureKey) async {
  final prefs = await SharedPreferences.getInstance();
  final master = prefs.getBool(PrefKeys.aiUsageMaster) ?? true;
  if (!master) return false;
  return prefs.getBool(featureKey) ?? true;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      switch (taskName) {
        case bgTaskMomentPost:
          return await handleMomentPostTask(inputData);
        case bgTaskCommentReply:
          return await handleCommentReplyTask(inputData);
        case bgTaskMomentInteract:
          return await handleMomentInteractTask(inputData);
        case bgTaskLetter:
          return await _handleLetterPost(inputData);
        case bgTaskWeChatPoll:
          return await handleWeChatPollTask(inputData);
        case bgTaskName:
        default:
          return await _handleProactiveChat(inputData);
      }
    } catch (e) {
      debugPrint('Background task failed ($taskName): $e');
      return false;
    }
  });
}

/// 前台兜底 / 测试入口：角色主动发动态
Future<bool> handleMomentPostTask(Map<String, dynamic>? inputData) =>
    _handleMomentPost(inputData);

// ═══════════════ 微信 iLink Bot 后台兜底 ═══════════════
//
// Workmanager 最小周期 15 分钟，只做「拉取 + 落库 + 简化回复 + 通知」。
// 完整人格管线（记忆/亲密度/清洗）回复由前台 WeChatBotService 负责。

/// 后台微信轮询：拉取新消息，白名单内联系人生成简化回复并发回。
Future<bool> handleCommentReplyTask(Map<String, dynamic>? inputData) =>
    _handleCommentReply(inputData);

/// 前台兜底：角色互动用户动态
Future<bool> handleMomentInteractTask(Map<String, dynamic>? inputData) =>
    _handleMomentInteract(inputData);

/// 前台心跳入口：应用仍在前台时，主动消息不依赖当前打开的聊天页面。
/// 每次只处理到期的角色；消息直接落库，当前页面/其他页面都能在下次刷新时看到。
Future<void> handleForegroundProactiveChatTask() async {
  if (_foregroundProactiveRunning) return;
  _foregroundProactiveRunning = true;
  final db = await _openRawDb();
  try {
    final rows = await db.query('ai_characters');
    for (final character in rows) {
      final characterId = character['id']?.toString();
      if (characterId == null || characterId.isEmpty) continue;
      final sessions = await db.query(
        'chat_sessions',
        where: 'aiCharacterId = ?',
        whereArgs: [characterId],
        orderBy: 'updatedAt DESC',
        limit: 1,
      );
      if (sessions.isEmpty) continue;
      final session = sessions.first;
      await _handleProactiveChat({
        'characterId': characterId,
        'sessionId': session['id']?.toString(),
        'intimacyLevel': session['intimacyLevel'] as int? ?? 0,
        'foreground': true,
      });
    }

    // ─── v72 新增：AI 主动生活维护（日程 + 生活日志）───
    // 每次前台心跳顺带跑一次；内部按「同一天只生成一次日程」幂等
    try {
      await _maintainAiLife(db);
    } catch (e) {
      debugPrint('Background: AI 主动生活维护失败: $e');
    }
  } finally {
    await db.close();
    _foregroundProactiveRunning = false;
  }
}
