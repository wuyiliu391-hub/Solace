# local_storage_repository.dart 拆分配置（split_class.py 输入）
CFG = {
    "file": "lib/repositories/local_storage_repository.dart",
    "class_line": 174,
    "class_name": "LocalStorageRepository",
    "core_name": "_LocalStorageRepositoryCore",
    "freshness_marker": "expectedColumns",
    "core_fields": ["_database", "_prefs", "pureAiModeNotifier",
                    "modeSettingsNotifier", "themeChangeNotifier",
                    "_isWeb", "_syncTimer"],
    "ctor_old": "LocalStorageRepository({bool? isWeb}) : _isWeb = isWeb ?? kIsWeb;",
    "ctor_new": "  LocalStorageRepository({bool? isWeb}) : super(isWeb: isWeb);",
    "core_text": """/// LocalStorageRepository 的字段基座：巨型仓库拆分为多个 mixin part 后，
/// 各 mixin 通过 `on _LocalStorageRepositoryCore` 共享这些实例字段。
abstract class _LocalStorageRepositoryCore {
  _LocalStorageRepositoryCore({bool? isWeb}) : _isWeb = isWeb ?? kIsWeb;

  Database? _database;
  SharedPreferences? _prefs;
  final ValueNotifier<bool> pureAiModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> modeSettingsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String?> themeChangeNotifier =
      ValueNotifier<String?>(null); // 'light'/'dark'/'system'/null
  bool _isWeb = false;
  Timer? _syncTimer;
}""",
    "cut_lines": [3000, 5410, 6871],
    "part_of": "../local_storage_repository.dart",
    "parts": [
        {"main": True},
        {"file": "lib/repositories/storage_parts/chat_messages.dart",
         "directive": "storage_parts/chat_messages.dart",
         "mixin": "LocalStorageRepositoryChatMessagesApi",
         "doc": "// LocalStorageRepository 消息与会话 CRUD：chat_messages / chat_sessions 及相关查询。"},
        {"file": "lib/repositories/storage_parts/export_moments_shop.dart",
         "directive": "storage_parts/export_moments_shop.dart",
         "mixin": "LocalStorageRepositoryMomentsShopApi",
         "doc": "// LocalStorageRepository 导入导出 / 朋友圈 / 贴纸 / 商店 / 纯AI / v10 扩展 CRUD。"},
        {"file": "lib/repositories/storage_parts/bt_virtual_phone.dart",
         "directive": "storage_parts/bt_virtual_phone.dart",
         "mixin": "LocalStorageRepositoryBtVPhoneApi",
         "doc": "// LocalStorageRepository BT Agent 封装 / 虚拟手机 / 小说 / 群聊等表 CRUD。"},
    ],
}
