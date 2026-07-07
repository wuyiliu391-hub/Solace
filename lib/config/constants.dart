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
}

class ApiDefaults {
  ApiDefaults._();

  // ─── API URLs ───
  static const String chatCompletionsPath = '/chat/completions';

  static const String adminStatsUrl = '/api/v1/admin/stats';
  static const String downloadApiUrl = '/api/v1/download';
  static const String versionCheckUrl = '/api/v1/version';
  static const String announcementsUrl = '/api/v1/announcements';

  // ─── Default Model Params ───
  static const double defaultTemperature = 0.7;
  static const int defaultMaxTokens = 2000;
  static const double reflectiveTemp = 0.7;
  static const int reflectiveMaxTokens = 200;
  static const double proactiveTemp = 0.8;
  static const int proactiveMaxTokens = 200;
  static const double momentTemp = 0.9;
  static const int momentMaxTokens = 150;
  static const double momentCommentTemp = 0.85;
  static const int momentCommentMaxTokens = 80;
  static const double backgroundTemp = 0.9;
  static const int backgroundMaxTokens = 80;
  static const double moodDiaryTemp = 0.9;
  static const int moodDiaryMaxTokens = 200;
}

class BuiltInAIProviders {
  BuiltInAIProviders._();

  static const String nvidiaStep37FlashId = 'builtin_nvidia_step37_flash';
  static const String nvidiaStep37FlashProvider = '内置最新 Step 模型';
  static const String nvidiaStep37FlashBaseUrl =
      'https://integrate.api.nvidia.com/v1';
  static const String nvidiaStep37FlashApiKey = ''; // 开源版本：请自行配置
  static const String nvidiaStep37FlashApiKeyBackup = ''; // 开源版本：请自行配置
  static const String nvidiaStep37FlashModel = 'stepfun-ai/step-3.7-flash';
  static const String nvidiaStep37FlashRemark = 'NVIDIA 官方 API，高并发触发限流，测试用';

  static const String siliconflowGlmZ19BId = 'builtin_siliconflow_glm_z1_9b';
  static const String siliconflowGlmZ19BProvider = '内置硅基 GLM-Z1-9B';
  static const String siliconflowGlmZ19BBaseUrl =
      'https://api.siliconflow.cn/v1';
  static const String siliconflowGlmZ19BApiKey = ''; // 开源版本：请自行配置
  static const String siliconflowGlmZ19BModel = 'THUDM/GLM-Z1-9B-0414';
  static const String siliconflowGlmZ19BRemark =
      '硅基流动社区模型，9B 推理模型，适合作为第二内置备用模型';

  /// 判断当前配置是否为内置 GLM-Z1-9B
  static bool isGlmZ19B(String configId, String modelName) {
    return configId == siliconflowGlmZ19BId ||
        modelName == siliconflowGlmZ19BModel;
  }
}

/// GLM-Z1-9B 各模式专属参数（仅对内置 GLM 模型生效）
class GlmModeParams {
  GlmModeParams._();

  // ─── 通用参数 ───
  static const double topP = 0.85;
  static const int topK = 40;

  // ─── 普通聊天模式 ───
  static const double chatTemperature = 0.82;
  static const int chatTopK = 35;
  static const double chatFrequencyPenalty = 1.2;
  static const int chatThinkingBudget = 512;
  static const int chatMaxTokens = 131072;

  // ─── 小说模式 ───
  static const double novelTemperature = 0.82;
  static const int novelTopK = 45;
  static const double novelFrequencyPenalty = 0.8;
  static const int novelThinkingBudget = 4096;
  static const int novelMaxTokens = 131072;

  // ─── 朋友圈模式 ───
  static const double momentTemperature = 0.88;
  static const int momentTopK = 40;
  static const double momentFrequencyPenalty = 1.0;
  static const int momentThinkingBudget = 256;
  static const int momentMaxTokens = 131072;

  // ─── 写信模式 ───
  static const double letterTemperature = 0.80;
  static const int letterTopK = 40;
  static const double letterFrequencyPenalty = 0.9;
  static const int letterThinkingBudget = 4096;
  static const int letterMaxTokens = 131072;

  // ─── 反思模式 ───
  static const double reflectionTemperature = 0.65;
  static const int reflectionTopK = 25;
  static const double reflectionFrequencyPenalty = 0.5;
  static const int reflectionThinkingBudget = 2048;
  static const int reflectionMaxTokens = 131072;

  // ─── 主动消息模式 ───
  static const double proactiveTemperature = 0.78;
  static const int proactiveTopK = 35;
  static const double proactiveFrequencyPenalty = 1.1;
  static const int proactiveThinkingBudget = 512;
  static const int proactiveMaxTokens = 131072;

  // ─── 语音通话模式 ───
  static const double voiceTemperature = 0.75;
  static const int voiceTopK = 35;
  static const double voiceFrequencyPenalty = 1.0;
  static const int voiceThinkingBudget = 1024;
  static const int voiceMaxTokens = 131072;

  // ─── 纯AI模式 ───
  static const double pureAiTemperature = 0.60;
  static const int pureAiTopK = 20;
  static const double pureAiFrequencyPenalty = 0.5;
  static const int pureAiThinkingBudget = 2048;
  static const int pureAiMaxTokens = 131072;

  // ─── 记忆场景模式 ───
  static const double memoryTemperature = 0.80;
  static const int memoryTopK = 40;
  static const double memoryFrequencyPenalty = 0.9;
  static const int memoryThinkingBudget = 2048;
  static const int memoryMaxTokens = 131072;

  // ─── 论坛模式 ───
  static const double forumTemperature = 0.85;
  static const int forumTopK = 40;
  static const double forumFrequencyPenalty = 1.0;
  static const int forumThinkingBudget = 512;
  static const int forumMaxTokens = 131072;

  // ─── 关系描述 ───
  static const double relationshipTemperature = 0.75;
  static const int relationshipTopK = 35;
  static const double relationshipFrequencyPenalty = 0.8;
  static const int relationshipThinkingBudget = 1024;
  static const int relationshipMaxTokens = 131072;

  // ─── 人格进化 ───
  static const double personaTemperature = 0.50;
  static const int personaTopK = 20;
  static const double personaFrequencyPenalty = 0.5;
  static const int personaThinkingBudget = 2048;
  static const int personaMaxTokens = 131072;

  // ─── 原谅判断 ───
  static const double forgiveTemperature = 0.75;
  static const int forgiveTopK = 35;
  static const double forgiveFrequencyPenalty = 0.5;
  static const int forgiveThinkingBudget = 1024;
  static const int forgiveMaxTokens = 131072;

  /// 构建 GLM-Z1-9B 的额外请求参数（top_p, top_k, frequency_penalty, thinking_budget）
  static Map<String, dynamic> buildExtraParams({
    required double temperature,
    required int topK,
    required double frequencyPenalty,
    required int thinkingBudget,
  }) {
    return {
      'top_p': topP,
      'top_k': topK,
      'frequency_penalty': frequencyPenalty,
      'thinking_budget': thinkingBudget,
    };
  }
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
  static const String pureAiModeEnabled = 'pure_ai_mode_enabled';
  static const String idCardChangeCount = 'id_card_change_count';
  static const String lastCheckInDate = 'last_check_in_date';
  static const String latestAvailableBuild = 'latest_available_build';
  static const String pendingBackgroundMessages = 'pending_background_messages';
  static const String momentsBackgroundImage = 'moments_background_image';
  static const String lastMomentsViewTime = 'last_moments_view_time';
  static const String diaryEntriesV2 = 'diary_entries_v2';
  static const String diaryEntries = 'diary_entries';
  static const String lastSeenAnnouncementId = 'last_seen_announcement_id';
  static const String themeMode = 'app_theme_mode';
  static const String lockTextColor = 'lock_screen_text_color';
  static const String globalResponseStyle = 'global_response_style';
  static const String globalMemoryMode = 'global_memory_mode';
  static const String btModeNoticeV1310Shown = 'bt_mode_notice_v1310_shown';
  static const String forceModeConfirmV14 = 'force_mode_confirm_v14';
  static const String versionFeatureAck275 = 'version_feature_ack_v275';
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

  // ─── 设备操控 ───
  static const String btPermissionDeviceMaster = 'bt_permission_device_master';
  static const String btPermissionDeviceTap = 'bt_permission_device_tap';
  static const String btPermissionDeviceSwipe = 'bt_permission_device_swipe';
  static const String btPermissionDeviceLongPress =
      'bt_permission_device_long_press';
  static const String btPermissionDeviceNavigate =
      'bt_permission_device_navigate';
  static const String btPermissionDeviceTypeText =
      'bt_permission_device_type_text';
  static const String btPermissionDeviceClickText =
      'bt_permission_device_click_text';
  static const String btPermissionDeviceOpenApp =
      'bt_permission_device_open_app';
  static const String btPermissionDeviceScreenRead =
      'bt_permission_device_screen_read';
  static const String btPermissionDeviceNotifications =
      'bt_permission_device_notifications';
  static const String btPermissionDeviceScreenshot =
      'bt_permission_device_screenshot';
  static const String btPermissionDeviceSystemSettings =
      'bt_permission_device_system_settings';
  static const String btPermissionDeviceShell = 'bt_permission_device_shell';
  static const String btPermissionDeviceAppManagement =
      'bt_permission_device_app_management';

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

    // 设备操控
    btPermissionDeviceTap,
    btPermissionDeviceSwipe,
    btPermissionDeviceLongPress,
    btPermissionDeviceNavigate,
    btPermissionDeviceTypeText,
    btPermissionDeviceClickText,
    btPermissionDeviceOpenApp,
    btPermissionDeviceScreenRead,
    btPermissionDeviceNotifications,
    btPermissionDeviceScreenshot,
    btPermissionDeviceSystemSettings,
    btPermissionDeviceShell,
    btPermissionDeviceAppManagement,
  ];

  // ─── Core Hub 中层 ───
  static const String coreHubNewWorldEnabled = 'core_hub_new_world_enabled';
  static const String coreHubNewWorldActivatedAt =
      'core_hub_new_world_activated_at';
  static const String coreHubNewWorldTokenConsumed =
      'core_hub_new_world_token_consumed';
  static const String coreHubNewWorldTokenResetAt =
      'core_hub_new_world_token_reset_at';
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

  static const int memoryFetch = 20;
  static const int profileMemory = 50;
  static const int similarMemory = 30;
  static const int chatHistoryContext = 30;
  static const int relevantMemoriesPrompt = 8;
  static const int memoriesFallback = 8;
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
  static const int topTopicSuggestions = 3;
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
  static const int dbVersion = 50;
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
  ];
}

class MethodChannels {
  MethodChannels._();

  static const String background = 'com.solace.background';
  static const String settings = 'com.solace.solace/settings';
}

class AppVersion {
  AppVersion._();

  static const String version = '16.3.0';
  static const int build = 276;
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
