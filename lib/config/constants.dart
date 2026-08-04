class AppDurations {
  AppDurations._();

  // ─── Network Timeouts ───
  static const aiRequest = Duration(seconds: 90);
  static const personaAnalysis = Duration(seconds: 120);
  static const updateCheck = Duration(seconds: 10);
  static const announcementFetch = Duration(seconds: 8);

  // ─── Retry Delays ───
  static const maxRetries = 3;

  // ─── UI Animations ───
  static const typingIndicator = Duration(milliseconds: 600);
  static const skeletonLoading = Duration(milliseconds: 1200);
  static const listItemAnimate = Duration(milliseconds: 400);
  static const navigationTransition = Duration(milliseconds: 300);
  static const fadeTransition = Duration(milliseconds: 1000);
  static const splashSnackBar = Duration(seconds: 3);
  static const silenceTimerInterval = Duration(minutes: 1);

  // ─── AI Typing Delays ───
  static const instantReplyDelay = Duration(milliseconds: 300);
  static const multiMessageDelay = Duration(milliseconds: 400);
  /// normal 模式拟人延迟上限（过大会被当成「卡住」）
  static const typingDelayMinMs = 200;
  static const typingDelayMaxMs = 1800;
  /// 流式 UI 刷新最小间隔，避免每 token 全量重建
  static const streamUiThrottle = Duration(milliseconds: 80);
}

class ApiDefaults {
  ApiDefaults._();

  // ─── 对抗复读（治「AI 反复讲同一件事」）───
  /// 惩罚已出现过的 token，降低逐字重复
  static const double chatFrequencyPenalty = 0.4;

  /// 惩罚已出现过的话题，降低反复讲同一件事
  static const double chatPresencePenalty = 0.4;

  /// 小说模式（完整输出）的 max_tokens 下限。
  /// 不传 max_tokens 会退回服务端默认（很多模型只有几百 token）导致「只出一句话」。
  static const int novelMaxTokensFloor = 4096;

  // ─── API URLs ───
  static const String chatCompletionsPath = '/chat/completions';

  static const String adminStatsUrl = '/api/v1/admin/stats';
  static const String downloadApiUrl = '/api/v1/download';
  static const String versionCheckUrl = '/api/v1/version';
  static const String announcementsUrl = '/api/v1/announcements';

  /// 联网搜索 API（UAPI Pro 免费搜索，无需 API Key）
  /// 文档: https://uapis.cn
  static const String searchApiUrl = 'https://uapis.cn/api/v1/search/aggregate';

  // ─── Default Model Params ───
  static const double defaultTemperature = 0.7;
  static const int defaultMaxTokens = 2000;
  static const double reflectiveTemp = 0.7;
  static const int reflectiveMaxTokens = 200;
  static const double proactiveTemp = 0.8;
  static const int proactiveMaxTokens = 200;
}

/// 已移除的内置模型 ID（用于清理本地残留配置）
class RemovedBuiltInAIProviders {
  RemovedBuiltInAIProviders._();

  static const String nvidiaStep37FlashId = 'builtin_nvidia_step37_flash';
  static const String siliconflowGlmZ19BId = 'builtin_siliconflow_glm_z1_9b';

  static const List<String> ids = [
    nvidiaStep37FlashId,
    siliconflowGlmZ19BId,
  ];
}

class PrefKeys {
  PrefKeys._();

  static const String currentUserId = 'current_user_id';
  static const String activeConfigId = 'active_config_id';
  static const String lastAppBuild = 'last_app_build';
  static const String termsAccepted = 'terms_accepted';
  static const String ageConfirmed = 'age_confirmed';
  static const String age18Gate = 'age18_gate_v2';
  static const String userAge = 'user_age';
  static const String idCardVerified = 'id_card_verified';
  static const String loverModeEnabled = 'lover_mode_enabled';
  static const String openModeEnabled = 'open_mode_enabled';
  static const String faModeEnabled = 'fa_mode_enabled';
  static const String faVerified = 'fa_verified';
  static const String daoModeEnabled = 'dao_mode_enabled';
  static const String chatStyleMode = 'chat_style_mode';
  static const String novelDialogueColor = 'novel_dialogue_color';
  static const String autoDiaryEnabled = 'auto_diary_enabled';
  static const String appUsageAwareness = 'app_usage_awareness';
  static const String pureAiModeEnabled = 'pure_ai_mode_enabled';
  static const String idCardChangeCount = 'id_card_change_count';
  static const String lastCheckInDate = 'last_check_in_date';
  /// 每日首次登录奖励发放日期（yyyy-MM-dd），与签到独立可叠
  static const String lastLoginBonusDate = 'last_login_bonus_date';
  /// 金币经济：是否启用消耗（false=免费模式，扣款恒成功不减币）
  static const String coinEconomyEnabled = 'coin_economy_enabled';
  /// 自定义：发消息消耗（null 用默认 CoinRules）
  static const String coinMessageCost = 'coin_message_cost';
  /// 自定义：朋友圈互动消耗
  static const String coinMomentCost = 'coin_moment_cost';
  /// 自定义：每日登录奖励
  static const String coinLoginBonus = 'coin_login_bonus';
  /// 自定义：每日签到奖励
  static const String coinCheckInReward = 'coin_check_in_reward';
  static const String latestAvailableBuild = 'latest_available_build';
  static const String momentsBackgroundImage = 'moments_background_image';
  static const String pendingBackgroundMessages = 'pending_background_messages';
  static const String lastMomentsViewTime = 'last_moments_view_time';
  static const String diaryEntriesV2 = 'diary_entries_v2';
  static const String diaryEntries = 'diary_entries';
  static const String lastSeenAnnouncementId = 'last_seen_announcement_id';
  static const String themeMode = 'app_theme_mode';
  static const String visualStyle = 'app_visual_style';
  /// 是否使用虚拟手机桌面壳作为主界面（false=经典底部导航）
  /// 默认 false：未设置时走经典底部导航，用户可在设置中开启小手机
  static const String phoneDesktopShell = 'phone_desktop_shell_enabled';
  /// 小手机壁纸主题：dawn / dusk / night
  static const String phoneWallpaperTheme = 'phone_wallpaper_theme';
  static const String lockTextColor = 'lock_screen_text_color';
  static const String globalResponseStyle = 'global_response_style';
  static const String globalMemoryMode = 'global_memory_mode';
  static const String btModeNoticeV1310Shown = 'bt_mode_notice_v1310_shown';
  static const String forceModeConfirmV14 = 'force_mode_confirm_v14';
  static const String versionFeatureAck275 = 'version_feature_ack_v275';
  static const String versionFeatureAck277 = 'version_feature_ack_v277';
  static const String versionFeatureAck278 = 'version_feature_ack_v278';
  static const String btYandereMasterEnabled = 'bt_yandere_master_enabled';
  static const String btPermissionContactRemark =
      'bt_permission_contact_remark';
  static const String btPermissionContactAvatar =
      'bt_permission_contact_avatar';
  static const String btPermissionContactHide = 'bt_permission_contact_hide';
  static const String btPermissionContactDelete =
      'bt_permission_contact_delete';
  static const String btPermissionOnlineStatus = 'bt_permission_online_status';
  static const String btPermissionSaveStatus = 'bt_permission_save_status';
  static const String btPermissionMessageDisturb =
      'bt_permission_message_disturb';
  static const String btPermissionVideoChat = 'bt_permission_video_chat';
  static const String btPermissionBlock = 'bt_permission_block';
  static const String btPermissionClearHistory = 'bt_permission_clear_history';
  static const String btPermissionResetPersonaMemory =
      'bt_permission_reset_persona_memory';
  static const String btPermissionReport = 'bt_permission_report';
  static const String btPermissionMoments = 'bt_permission_moments';
  static const String btPermissionMailbox = 'bt_permission_mailbox';
  static const String btPermissionLetters = 'bt_permission_letters';
  static const String btPermissionDiary = 'bt_permission_diary';
  static const String btPermissionLuckyWheel = 'bt_permission_lucky_wheel';
  static const String btPermissionGlobalMemory = 'bt_permission_global_memory';
  static const String btPermissionProfileAvatar =
      'bt_permission_profile_avatar';
  static const String btPermissionProfileNickname =
      'bt_permission_profile_nickname';
  static const String btPermissionLightTheme = 'bt_permission_light_theme';
  static const String btPermissionDarkTheme = 'bt_permission_dark_theme';
  static const String btPermissionSystemTheme = 'bt_permission_system_theme';

  // ─── Device Agent（角色主动操控真实设备 · 全量） ───
  static const String deviceAgentMasterEnabled = 'device_agent_master_enabled';
  static const String devicePermissionRead = 'device_permission_read';
  static const String devicePermissionDisplay = 'device_permission_display';
  static const String devicePermissionAudio = 'device_permission_audio';
  static const String devicePermissionLock = 'device_permission_lock';
  static const String devicePermissionApp = 'device_permission_app';
  static const String devicePermissionNetwork = 'device_permission_network';
  static const String devicePermissionUi = 'device_permission_ui';
  static const String devicePermissionShell = 'device_permission_shell';
  static const String deviceAgentAuditLog = 'device_agent_audit_log';
  /// 小说/法模式下是否仍允许 Device Agent（默认关，防叙事混乱）
  static const String deviceAgentAllowInNarrative =
      'device_agent_allow_in_narrative';

  static const List<String> deviceAllPermissionKeys = [
    devicePermissionRead,
    devicePermissionDisplay,
    devicePermissionAudio,
    devicePermissionLock,
    devicePermissionApp,
    devicePermissionNetwork,
    devicePermissionUi,
    devicePermissionShell,
  ];

  static const List<String> btAllPermissionKeys = [
    btPermissionContactRemark,
    btPermissionContactAvatar,
    btPermissionContactHide,
    btPermissionContactDelete,
    btPermissionOnlineStatus,
    btPermissionSaveStatus,
    btPermissionMessageDisturb,
    btPermissionVideoChat,
    btPermissionBlock,
    btPermissionClearHistory,
    btPermissionResetPersonaMemory,
    btPermissionReport,
    btPermissionMoments,
    btPermissionMailbox,
    btPermissionLetters,
    btPermissionDiary,
    btPermissionLuckyWheel,
    btPermissionGlobalMemory,
    btPermissionProfileAvatar,
    btPermissionProfileNickname,
    btPermissionLightTheme,
    btPermissionDarkTheme,
    btPermissionSystemTheme,
  ];

  // ─── Core Hub 中层 ───
  static const String coreHubPersonaRules = 'core_hub_persona_rules';
  static const String coreHubTaskQueuePending = 'core_hub_task_queue_pending';
  static const String coreHubTaskQueueCompleted =
      'core_hub_task_queue_completed';
  static const String siliconeApiKey = 'siliconflow_api_key';
  static const String ttsApiKey = 'tts_api_key';
  static const String brevoApiKey = 'brevo_api_key';
  static const String brevoSenderEmail = 'brevo_sender_email';
  static const String brevoSenderName = 'brevo_sender_name';
  static const String userEmail = 'user_email';

  static const String userPrefix = 'user_';
  static const String characterPrefix = 'character_';
  static const String configPrefix = 'config_';
  static const String sessionPrefix = 'session_';
  static const String messagePrefix = 'message_';
  static const String memoryPrefix = 'memory_';
  static const String emotionPrefix = 'emotion_';
  static const String emotionTypeSuffix = '_type';
  static const String emotionIntensitySuffix = '_intensity';
  static const String emotionTriggerSuffix = '_trigger';
  static const String emotionUpdatedSuffix = '_updated';
  static const String pendingReplyPrefix = 'pending_reply_';
  static const String messageIdsPrefix = 'message_ids_';
  static const String momentPrefix = 'moment_';
  static const String stickerPackPrefix = 'sticker_pack_';
  static const String forbiddenPhrases = 'forbidden_phrases';
  static const String memoryRebuildCheckpoint = 'memory_rebuild_checkpoint';

  static const String ageDeclarationDone = 'age_declaration_done_v6';
  static const String loggedOut = 'logged_out';
  static String pwHash(String qq) => 'pw_hash_$qq';

  static String user(String id) => '$userPrefix$id';
  static String character(String id) => '$characterPrefix$id';
  static String config(String id) => '$configPrefix$id';
  static String session(String id) => '$sessionPrefix$id';
  static String message(String id) => '$messagePrefix$id';
  static String memory(String id) => '$memoryPrefix$id';
  static String pendingReply(String chatId) => '$pendingReplyPrefix$chatId';
  static String messageIds(String chatId) => '$messageIdsPrefix$chatId';
  static String moment(String id) => '$momentPrefix$id';
  static String stickerPack(String id) => '$stickerPackPrefix$id';
  static String emotionKey(String characterId, String userId) =>
      '${emotionPrefix}${characterId}_$userId';
  static String emotionType(String characterId, String userId) =>
      '${emotionKey(characterId, userId)}$emotionTypeSuffix';
  static String emotionIntensity(String characterId, String userId) =>
      '${emotionKey(characterId, userId)}$emotionIntensitySuffix';
  static String emotionTrigger(String characterId, String userId) =>
      '${emotionKey(characterId, userId)}$emotionTriggerSuffix';
  static String emotionUpdated(String characterId, String userId) =>
      '${emotionKey(characterId, userId)}$emotionUpdatedSuffix';
}

class Limit {
  Limit._();

  static const int memoryFetch = 40;
  static const int profileMemory = 50;
  static const int similarMemory = 30;
  /// 发给模型的最近对话条数（过小会表现为“失忆”）
  static const int chatHistoryContext = 60;
  /// 精简模型的历史条数（小模型也需足够连贯）
  static const int chatHistoryContextCompact = 28;
  /// 读库时为 AI 准备的消息上限（应 ≥ chatHistoryContext）
  static const int chatHistoryLoadForAI = 120;
  static const int relevantMemoriesPrompt = 12;
  static const int memoriesFallback = 12;
  static const int preferencesMax = 8;
  static const int eventsMax = 5;
  static const int emotionsMax = 5;
  static const int extractMessages = 5;
  static const int topKeywords = 3;
  static const int momentRecentMessages = 10;
  static const int momentContextMessages = 6;
  static const int momentMemoriesPrompt = 5;
  static const int momentDialogueExamples = 3;
  static const int homeTopSessions = 3;
  static const int topClassificationResults = 5;
  static const int topDominantColors = 3;

  /// buildConsolidatedMemoryPrompt 等实时路径加载记忆上限
  static const int memoryPromptCap = 200;

  /// 后台维护任务（裁出/清理/合并/统计）加载记忆上限
  static const int memoryMaintenanceCap = 500;

  static const double blockSadnessThreshold = 0.9;
  static const double blockAngerThreshold = 0.9;
  static const Duration emotionBlockCooldown = Duration(minutes: 30);
}

class DbDefaults {
  DbDefaults._();

  static const String dbName = 'solace.db';
  static const int dbVersion = 66;
  static const int newUserCoins = 100;
  static const int newUserTotalEarned = 100;
  static const int newUserTotalSpent = 0;
  static const int defaultMinSdk = 23;

  static const List<String> backupTables = [
    'users',
    'ai_characters',
    'ai_configs',
    'chat_sessions',
    'chat_messages',
    'intimacy_events',
    'memories',
    'moments',
    'sticker_packs',
    'shop_items',
    'shop_orders',
    'social_memories',
    'story_books',
    'story_segments',
    'story_scenes',
    'story_saves',
    // v26+ 模块
    'ai_wallets',
    'pure_ai_sessions',
    'pure_ai_messages',
    'inner_thoughts',
    'forum_posts',
    'forum_comments',
    'shared_album_entries',
    'virtual_locations',
    'persona_snapshots',
    'growth_events',
    'bt_agent_actions',
    'ai_letters',
    // X 推特风格
    'moment_bookmarks',
    'moment_notifications',
    'trending_tags',
    // 虚拟手机模块
    'virtual_phones',
    'vp_contacts',
    'vp_chats',
    'vp_chat_messages',
    'vp_notes',
    'vp_moments',
  ];
}

class MethodChannels {
  MethodChannels._();

  static const String background = 'com.solace.background';
  static const String settings = 'com.solace.solace/settings';
  static const String notification = 'com.solace.solace/notification';
  static const String accessibility = 'com.solace.solace/accessibility';
  static const String screenshot = 'com.solace.solace/screenshot';
}

class AppVersion {
  AppVersion._();

  static const String version = '17.7.0';
  static const int build = 290;
}

class NotificationChannels {
  NotificationChannels._();

  static const String messages = 'solace_messages';
  static const String backgroundChat = 'bg_chat';
  static const String scheduled = 'solace_scheduled';
  static const String daily = 'solace_daily';
  static const String moments = 'solace_moments';
}

class DbTables {
  DbTables._();

  static const String users = 'users';
  static const String aiCharacters = 'ai_characters';
  static const String aiConfigs = 'ai_configs';
  static const String chatSessions = 'chat_sessions';
  static const String chatMessages = 'chat_messages';
  static const String memories = 'memories';
  static const String moments = 'moments';
  static const String stickerPacks = 'sticker_packs';
  static const String socialMemories = 'social_memories';

  static List<String> get all => [
        users,
        aiCharacters,
        aiConfigs,
        chatSessions,
        chatMessages,
        memories,
        moments,
        stickerPacks,
        socialMemories,
      ];
}

/// 视觉风格包：原有主题（抖音风格）vs 现代主义聊天主题
enum VisualStyle { classic, modernist }
