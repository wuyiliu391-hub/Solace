// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/prefs_helper.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/theme/theme_bloc.dart';
import 'repositories/local_storage_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/terms_agreement_screen.dart';
import 'services/battery_service.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/chat_detail_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/pure_ai/pure_ai_chat_screen.dart';
import 'screens/memory/memory_screen.dart';
import 'screens/moments/moments_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/discover/growth_track_screen.dart';
import 'screens/discover/ai_activity_feed_screen.dart';
import 'screens/discover/relationship_dashboard.dart';
import 'screens/discover/character_psychology_screen.dart';
import 'screens/discover/ai_mailbox_screen.dart';
import 'screens/discover/ai_diary_screen.dart';
import 'screens/discover/entertainment_screen.dart';
import 'screens/discover/bookmark_list_screen.dart';
import 'screens/character/create_character_screen.dart';
import 'screens/settings/ai_config_screen.dart';
import 'screens/profile/settings_screen.dart';
import 'screens/tarot/tarot_screen.dart';
import 'screens/games/lucky_wheel_screen.dart';
import 'screens/novel/novel_shelf_screen.dart';
import 'screens/phone/phone_home_shell.dart';
import 'screens/shop/shop_screen.dart';

import 'blocs/group_chat/group_chat_bloc.dart';

import 'screens/usage/usage_screen.dart';
import 'screens/operit/operit_home_screen.dart';
import 'screens/error/storage_recovery_screen.dart';
import 'services/storage/storage_recovery_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'blocs/chat/chat_bloc.dart';
import 'blocs/pure_ai/pure_ai_chat_bloc.dart';
import 'blocs/shop/shop_bloc.dart';
import 'services/permission_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'services/workmanager_helper.dart'
    if (dart.library.html) 'services/workmanager_helper_web.dart';
import 'widgets/age_declaration_screen.dart';
import 'widgets/update_dialog.dart';
import 'config/constants.dart';
import 'services/log_service.dart';
import 'services/ai_service.dart';
import 'services/bridge/ai_service_adapter.dart';
import 'services/pure_ai_service.dart';
import 'services/emotion_engine.dart';
import 'services/memory_engine.dart';
import 'services/core_hub.dart';
import 'package:intl/intl.dart';
import 'services/usage_meter_service.dart';
import 'services/memory_rebuild_service.dart';
import 'services/background_service.dart';

part 'src/app/auth_gate.dart';
part 'src/app/main_shell.dart';
part 'src/app/discover_page.dart';
part 'src/app/solace_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'zh_CN';
  try {
    await initializeDateFormatting('zh_CN').timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('初始化日期区域失败: $e');
  }

  // 全局错误兜底：防止控件构建异常导致空白灰屏
  FlutterError.onError = (FlutterErrorDetails details) {
    LogService.instance
        .e('FlutterError', '${details.exception}\n${details.stack}');
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    LogService.instance
        .e('ErrorWidget', '${details.exception}\n${details.stack}');
    // debug 模式显示错误详情，release 模式显示极简占位
    if (kDebugMode) {
      return Material(
        color: Colors.red.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Build Error: ${details.exception}',
            style: const TextStyle(fontSize: 10, color: Colors.red),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return const _MiniFallback();
  };

  LogService.instance.i('System', 'App started');

  // 预热 SharedPreferences 缓存
  await PrefsHelper.warmUp();

  // 初始化数据库（核心，必须成功）
  final storageRepo = LocalStorageRepository();
  var storageReady = false;
  try {
    await storageRepo.initialize().timeout(const Duration(seconds: 10));
    storageReady = true;
  } catch (e) {
    debugPrint('数据库初始化超时/失败: $e');
    // 重试一次
    try {
      await storageRepo.initialize().timeout(const Duration(seconds: 10));
      storageReady = true;
    } catch (e2) {
      debugPrint('数据库初始化重试失败: $e2');
    }
  }

  // 初始化 Core Hub 全局中枢（BT 病娇模块升级版）
  try {
    final prefs = await PrefsHelper.instance;
    await CoreHub.init(prefs);
    debugPrint('CoreHub 初始化完成');
  } catch (e) {
    debugPrint('CoreHub 初始化失败: $e');
  }

  // 性能优化 -- 耗电与老手机兼容
  // 关键服务已就绪，立即启动 App 显示首屏
  runApp(SolaceApp(storageRepo: storageRepo, storageReady: storageReady));

  // 以下全部是非关键服务，延迟初始化以加速首屏渲染
  Future.delayed(const Duration(seconds: 3), () async {
    UsageMeterService.instance.warmUp().catchError((e) {
      debugPrint('用量服务预热失败: $e');
    });

    NotificationService()
        .initialize()
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
      debugPrint('通知服务初始化失败: $e');
    });

    PermissionService.requestRequiredPermissions()
        .timeout(const Duration(seconds: 10))
        .catchError((e) {
      debugPrint('权限申请超时/失败: $e');
    });
  });

  // 更低优先级：Hive + 语音 + 电池
  Future.delayed(const Duration(seconds: 6), () async {
    try {
      await Hive.initFlutter();
    } catch (e) {
      debugPrint('Hive 初始化失败: $e');
    }

    BatteryService.init().catchError((e) {
      debugPrint('BatteryService 初始化失败: $e');
    });
  });

  // Workmanager 最后初始化（后台任务，完全不急）
  Future.delayed(const Duration(seconds: 10), () async {
    await initWorkmanager().timeout(const Duration(seconds: 5)).catchError((e) {
      debugPrint('Workmanager 初始化失败: $e');
    });
  });
}

/// 极简兜底组件（小占位），不依赖任何 InheritedWidget/Theme/Directionality
class _MiniFallback extends StatelessWidget {
  const _MiniFallback();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
