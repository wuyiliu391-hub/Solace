// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcCore {
late final LocalStorageRepository _storage;
late final AIService _aiService;
late final MemoryEngine _memoryEngine;
final _uuid = const Uuid();
final _random = Random();

/// 单轮接话守卫：限制一次用户消息最多触发 2 个 AI 回复
int _followUpCount = 0;

/// 当前群聊的 AI 回复互斥（防止并发触发多个流）
final Map<String, bool> _replyingGroups = {};

/// 用户消息等待回应标记：AI 生成中被抢占时排队，生成结束后补回应
final Map<String, bool> _pendingUserReply = {};

/// 自动接话轮询
Timer? _autoModeTimer;
final Map<String, bool> _autoModeByGroup = {};
final Map<String, int> _groupDelays = {};

/// 各群上次自动接话触发时间（共享最短间隔定时器下按各自 delay 限频）
final Map<String, DateTime> _lastAutoRunAt = {};
final Map<String, DateTime> _lastAutoRunByCharacter = {};

/// 手动锁定发言人（内存态，群聊 UI 激活条写入）
final Map<String, List<String>> _forcedSpeakers = {};

/// 群聊记忆沉淀计数器：粗摘要降频（每5轮一条）+ LLM 事件提取每5轮一次
final Map<String, int> _groupMemoryCounter = {};

/// 消息分页状态（上滑加载更多，对齐单聊）：已加载条数 / 是否还有更早 / 加载中守卫
final Map<String, int> _loadedOffsets = {};
final Map<String, bool> _hasMoreByGroup = {};
final Set<String> _loadingMore = {};
late final GroupSummaryRefreshCoordinator _groupSummaryRefreshes;
late final GroupChatPromptPipeline _promptPipeline;
}
