import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../../models/chat_message.dart';
import '../../models/pure_ai_message.dart';
import '../../models/chat_session.dart';
import '../../models/ai_character.dart';
import '../../models/memory.dart';
import '../../models/intimacy_event.dart';
import '../../models/ai_stream_chunk.dart';
import '../../models/ai_turn_state.dart';
import '../../models/money_transaction.dart';
import '../../models/proactive_policy.dart';
import '../../repositories/local_storage_repository.dart';

import '../../services/ai_service.dart';
import '../../services/ai_status_service.dart';
import '../../services/bt_agent_execution_service.dart';
import '../../services/core_hub.dart';
import '../../services/agent/agent_tools.dart';
import '../../models/bt_agent_action.dart';
import '../../services/pure_ai_service.dart';
import '../../services/bridge/ai_service_adapter.dart';
import '../../services/builtin_sticker_service.dart';
import '../../services/memory_engine.dart';
import '../../services/emotion_engine.dart';
import '../../services/character_commitment_service.dart';
import '../../models/character_commitment.dart';
import '../../services/proactive_policy_service.dart';
import '../../services/relationship_context_service.dart';
import '../../models/relationship_context.dart';

import '../../models/character_emotion.dart';
import '../../utils/sentiment_analyzer.dart';
import '../../utils/behavior_risk_detector.dart';
import '../../utils/content_filter.dart';
import '../../config/constants.dart';
import '../../config/business_rules.dart';
import '../../services/log_service.dart';
import '../../utils/message_sanitizer.dart';
import '../../utils/prefs_helper.dart';
import '../../models/app_config_data.dart';
import '../../services/llm_service.dart';
import '../../services/wellbeing_service.dart';
import 'chat_bloc_utils.dart';
import 'chat_bloc_intimacy.dart';
import '../../services/story_state_service.dart';
import '../../services/proactive_decision_engine.dart';
import '../../services/proactive_action_executor.dart';

part 'chat_event.dart';
part 'chat_state.dart';
part 'chat_bloc_parts/bloc_shared_statics.dart';
part 'chat_bloc_parts/bloc_core.dart';
part 'chat_bloc_parts/bloc_calls_base.dart';
part 'chat_bloc_parts/bloc_ai_bridge.dart';
part 'chat_bloc_parts/bloc_memory_intimacy.dart';
part 'chat_bloc_parts/bloc_prompt_context.dart';
part 'chat_bloc_parts/bloc_turn_state.dart';
part 'chat_bloc_parts/bloc_bt_agent.dart';
part 'chat_bloc_parts/bloc_novel.dart';
part 'chat_bloc_parts/bloc_messages_load.dart';
part 'chat_bloc_parts/bloc_status_stats.dart';
part 'chat_bloc_parts/bloc_block_forgive.dart';
part 'chat_bloc_parts/bloc_message_ops.dart';
part 'chat_bloc_parts/bloc_send_money.dart';
part 'chat_bloc_parts/bloc_sticker_session.dart';
part 'chat_bloc_parts/bloc_send_main.dart';
part 'chat_bloc_parts/bloc_regen_context.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState>
    with ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive, _BlocMessageOps, _BlocSendMoney, _BlocStickerSession, _BlocSendMain, _BlocRegen {

  static final Map<String, ChatBloc> _chatInstances = {};


  static ChatBloc forChat(
    String chatId,
    LocalStorageRepository storage,
    AIService aiService, {
    AIServiceAdapter? aiAdapter,
  }) {
    return _chatInstances[chatId] ??= ChatBloc(
      storage,
      aiService,
      aiAdapter: aiAdapter,
    );
  }


  ChatBloc(LocalStorageRepository storage, AIService aiService,
      {AIServiceAdapter? aiAdapter})
      : super(ChatInitial()) {
    _storage = storage;
    _aiService = aiService;
    _aiAdapter = aiAdapter;
    _memoryEngine = MemoryEngine(storage);
    _emotionEngine = EmotionEngine(storage);
    _pureAIService = PureAIService(_storage);
    _btAgentExecutionService = BtAgentExecutionService(_storage);
    _commitmentService = CharacterCommitmentService(_storage);
    _relationshipService = RelationshipContextService(_storage);
    _storyStateService = StoryStateService(_storage);
    _proactiveDecisionEngine = ProactiveDecisionEngine();
    on<ChatLoadSessions>(_onLoadSessions);
    on<ChatLoadMessages>(_onLoadMessages);
    on<ChatLoadMoreMessages>(_onLoadMoreMessages);
    on<ChatLoadUntilMessage>(_onLoadUntilMessage);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatSendSticker>(_onSendSticker);
    on<ChatCreateSession>(_onCreateSession);
    on<ChatDeleteSession>(_onDeleteSession);
    on<ChatProactiveReply>(_onProactiveReply);
    on<ChatSendRedPacket>(_onSendRedPacket);
    on<ChatSendGift>(_onSendGift);
    on<ChatAISendCoins>(_onAISendCoins);
    on<ChatSendMoneyMessage>(_onSendMoneyMessage);
    on<ChatClaimMoney>(_onClaimMoney);
    on<ChatBlockByUser>(_onBlockByUser);
    on<ChatUnblockByUser>(_onUnblockByUser);
    on<ChatAIForgaveUser>(_onAIForgaveUser);
    on<ChatAIObservingNotify>(_onAIObservingNotify);
    // SillyTavern 对标事件处理器
    on<ChatSwipeRight>(_onSwipeRight);
    on<ChatSwipeLeft>(_onSwipeLeft);
    on<ChatHideMessage>(_onHideMessage);
    on<ChatUnhideMessage>(_onUnhideMessage);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<ChatDeleteMessages>(_onDeleteMessages);
    on<ChatRecallMessage>(_onRecallMessage);
    on<ChatBatchBookmark>(_onBatchBookmark);
    on<ChatToggleBookmark>(_onToggleBookmark);
    on<ChatCopyMessage>(_onCopyMessage);
    on<ChatMoveMessageUp>(_onMoveMessageUp);
    on<ChatMoveMessageDown>(_onMoveMessageDown);
    on<ChatCreateBranch>(_onCreateBranch);
    on<ChatClearContext>(_onClearContext);
    on<ChatEditAIReply>(_onEditAIReply);
    on<ChatRegenerateAIReply>(_onRegenerateAIReply);
  }


  @override
  Future<void> close() {
    _chatInstances.removeWhere((_, bloc) => identical(bloc, this));
    return super.close();
  }


}
