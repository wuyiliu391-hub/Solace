import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_branch.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../models/group_chat_summary.dart';
import '../../models/group_chat_lorebook_entry.dart';
import '../../models/group_public_event_memory.dart';
import '../../models/ai_character.dart';
import '../../models/ai_config.dart';
import '../../models/ai_stream_chunk.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';
import '../../services/memory_engine.dart';
import '../../services/moment_context_service.dart';
import '../../utils/message_sanitizer.dart';
import '../../utils/content_filter.dart';
import '../../utils/identity_label.dart' as identity;
import 'group_chat_speaker.dart';
import 'group_chat_prompts.dart';
import '../../services/group_chat_rolling_summary.dart';
import '../../services/group_chat_prompt_pipeline.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';
part 'group_chat_bloc_parts/bloc_core.dart';
part 'group_chat_bloc_parts/gc_sessions.dart';
part 'group_chat_bloc_parts/gc_helpers.dart';
part 'group_chat_bloc_parts/gc_chat_flow.dart';
part 'group_chat_bloc_parts/gc_config_memory.dart';
part 'group_chat_bloc_parts/gc_session_config.dart';

/// AI 群聊 BLoC
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState>
    with
        _GcCore,
        _GcSessions,
        _GcHelpers,
        _GcChatFlow,
        _GcConfigMemory,
        _GcSessionConfig {
  GroupChatBloc(LocalStorageRepository storage, AIService aiService,
      {MemoryEngine? memoryEngine})
      : super(GroupChatInitial()) {
    _storage = storage;
    _aiService = aiService;
    _memoryEngine = memoryEngine ?? MemoryEngine(storage);
    _groupSummaryRefreshes = GroupSummaryRefreshCoordinator();
    _promptPipeline = const GroupChatPromptPipeline();

    on<GroupChatLoadSessions>(_onLoadSessions);
    on<GroupChatCreate>(_onCreate);
    on<GroupChatDelete>(_onDelete);
    on<GroupChatLoadMessages>(_onLoadMessages);
    on<GroupChatLoadMoreMessages>(_onLoadMoreMessages);
    on<GroupChatSendMessage>(_onSendMessage);
    on<GroupChatUpdateSession>(_onUpdateSession);
    on<GroupChatAddMember>(_onAddMember);
    on<GroupChatRemoveMember>(_onRemoveMember);
    on<GroupChatMarkRead>(_onMarkRead);
    on<GroupChatSetSpeakers>(_onSetSpeakers);
    on<GroupChatAIMessageSaved>(_onAIMessageSaved);
    on<GroupChatUpdateConfig>(_onUpdateConfig);
    on<GroupChatCreateBranch>(_onCreateBranch);
    on<GroupChatSwitchBranch>(_onSwitchBranch);
    on<GroupChatDeleteBranch>(_onDeleteBranch);
    on<GroupChatDeleteMessage>(_onDeleteMessage);
    on<GroupChatToggleBookmark>(_onToggleBookmark);
    on<GroupChatEditAIReply>(_onEditAIReply);
    on<GroupChatRegenerateMessage>(_onRegenerateMessage);
    on<GroupChatSelectSwipe>(_onSelectSwipe);
    on<GroupChatSaveLorebookEntry>(_onSaveLorebookEntry);
    on<GroupChatDeleteLorebookEntry>(_onDeleteLorebookEntry);
    on<GroupChatRecallMessage>(_onRecallMessage);
  }

  @override
  Future<void> close() {
    _autoModeTimer?.cancel();
    return super.close();
  }
}
