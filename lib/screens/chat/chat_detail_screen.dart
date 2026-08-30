// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../models/chat_session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/chat_message.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/ai_status_service.dart';
import '../virtual_phone/virtual_phone_screen.dart';
import '../voice/voice_call_screen.dart';
import '../../services/voice/mimo_tts_service.dart';
import '../../services/voice/mimo_director.dart';
import '../../models/virtual_phone/virtual_phone.dart';
import '../../services/virtual_phone_generator.dart';
import '../../utils/message_sanitizer.dart';
import '../../utils/vision_image_encoder.dart';
import '../../utils/character_color.dart';
import '../../config/app_colors.dart';

import '../../services/builtin_sticker_service.dart';
import '../../services/sticker_pack_service.dart';
import '../../models/sticker_pack.dart';
import '../../widgets/red_packet_card.dart';
import '../../widgets/order_card.dart';
import '../../screens/shop/shop_screen.dart';
import '../../screens/shop/order_tracking_screen.dart';
import '../../models/shop_order.dart';
import '../../blocs/shop/shop_bloc.dart';

import '../../widgets/animated_list_item.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/message_status_indicator.dart';
import '../../widgets/message_actions_sheet.dart';
import '../../widgets/wechat_avatar.dart';
import '../../widgets/wechat_message_menu.dart';
import '../../widgets/money_message_card.dart';
import '../../models/money_transaction.dart';
import '../money/money_send_dialog.dart';
import '../money/red_packet_open_screen.dart';
import '../../utils/ui_utils.dart';
import '../../utils/avatar_resolver.dart';
import '../../config/constants.dart';
import '../../config/business_rules.dart';
import '../../services/log_service.dart';

import '../../services/emotion_engine.dart';
import '../../models/character_emotion.dart';
import '../moments/moments_screen.dart';
import 'chat_settings_screen.dart';

import '../../services/voice/voice_model_manager.dart';
import '../../services/voice/local_tts_service.dart';
import '../../services/voice/local_stt_service.dart';
import '../../services/voice/voice_recorder_service.dart';
import '../../services/voice/voice_player_service.dart';
import '../../services/voice/voice_profile_store.dart';
import '../../services/permission_service.dart';
import '../voice/voice_clone_screen.dart';
import '../character/v2/character_editor_screen.dart';
import '../memory/memory_screen.dart';
part 'chat_detail_parts/state_shared_statics.dart';
part 'chat_detail_parts/state_core.dart';
part 'chat_detail_parts/state_load_core.dart';
part 'chat_detail_parts/state_selection.dart';
part 'chat_detail_parts/state_side_story.dart';
part 'chat_detail_parts/state_voice.dart';
part 'chat_detail_parts/state_send_input.dart';
part 'chat_detail_parts/state_money_dialogs.dart';
part 'chat_detail_parts/state_search.dart';
part 'chat_detail_parts/state_msg_actions.dart';
part 'chat_detail_parts/state_nav_dialogs.dart';
part 'chat_detail_parts/state_appbar_builders.dart';
part 'chat_detail_parts/state_list_input_builders.dart';
part 'chat_detail_parts/state_body_builders.dart';
part 'chat_detail_parts/widgets_overlay.dart';
part 'chat_detail_parts/widgets_bubble.dart';
part 'chat_detail_parts/widgets_sticker_sheet.dart';
part 'chat_detail_parts/widgets_streaming.dart';
part 'chat_detail_parts/widgets_reasoning.dart';
part 'chat_detail_parts/widgets_sidestory_sheet.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatSession session;
  final String? initialMessage; // 从塔罗牌等活动预填的消息
  final ChatMessage? initialJumpToMessage; // 打开后自动定位并高亮的目标消息（收藏/搜索跳转）

  const ChatDetailScreen(
      {super.key,
      required this.session,
      this.initialMessage,
      this.initialJumpToMessage});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch, _StateMessageActions, _StateNavDialogs, _StateAppBarBuilders, _StateListInputBuilders, _StateBodyBuilders {

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isJumpedToMessage && !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isJumpedToMessage) {
            _returnToSearchResults();
          } else if (_isSearching) {
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchResults = [];
              _searchController.clear();
            });
          } else {
            Navigator.pop(context, _hasSettingsChanged);
          }
        }
      },
      child: BlocProvider.value(
        value: _chatBloc,
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? (_isWeChatStyle
                  ? WeChatColors.darkPageBackground
                  : ImmersiveColors.background)
              : (_isWeChatStyle
                  ? WeChatColors.chatBackground
                  : const Color(0xFFF1EFEB)),
          appBar: _selectionMode
              ? _buildSelectionAppBar(colorScheme)
              : _isSearching
                  ? _buildSearchAppBar(colorScheme)
                  : _isJumpedToMessage
                      ? _buildJumpedAppBar(colorScheme)
                      : _buildModernAppBar(colorScheme),
          body: _buildBody(colorScheme),
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    _isBlockedByAI =
        widget.session.isBlocked && widget.session.blockedBy == BlockedBy.ai;
    _isBlockedByUser =
        widget.session.isBlocked && widget.session.blockedBy == BlockedBy.user;
    // 回复生成使用应用级 ChatBloc，不绑定聊天详情页生命周期。
    // 页面切换后任务继续执行并落库，回来时由 ChatLoadMessages 恢复结果。
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    _chatBloc =
        ChatBloc.forChat(widget.session.id, storage, AIService(storage));
    _loadTurnState();
    _scrollController.addListener(_onScroll);
    _initialize();
    unawaited(BuiltinStickerService.loadDefaultPack().catchError((_) {}));
    _startUsageReminderTimer();

    // 监听模式切换（小说模式等），切换后立即重建所有气泡
    _modeSettingsStorage =
        RepositoryProvider.of<LocalStorageRepository>(context);
    _onModeSettingsChanged = () {
      if (mounted) setState(() {});
    };
    _modeSettingsStorage!.modeSettingsNotifier
        .addListener(_onModeSettingsChanged!);
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 同一页面从其它页面返回时，读取持久化的最终回复；生成任务不依赖本页面。
    _chatBloc.add(ChatLoadMessages(widget.session.id));
  }


  @override
  void dispose() {
    _silenceTimer?.cancel();
    _cancelLoadingFallbackTimer();
    _usageReminderTimer?.cancel();
    _highlightTimer?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _isAiTypingNotifier.dispose();
    _canSendNotifier.dispose();
    _showNewMessageBannerNotifier.dispose();

    // 本地语音资源释放
    _voiceRecorder.dispose();
    _voicePlayer.dispose();

    // 移除模式切换监听
    if (_onModeSettingsChanged != null && _modeSettingsStorage != null) {
      _modeSettingsStorage!.modeSettingsNotifier
          .removeListener(_onModeSettingsChanged!);
    }

    super.dispose();
  }


}
