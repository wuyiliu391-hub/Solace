// 导航与更多面板（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateNavDialogs on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch, _StateMessageActions {
  Future<void> _openVirtualPhone(BuildContext context) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final character =
        await storage.getAICharacter(widget.session.aiCharacterId);
    if (!context.mounted) return;
    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到该角色的资料')),
      );
      return;
    }
    Navigator.of(context).push(VirtualPhoneScreen.route(context, character));
  }


  /// 从状态栏跳转到朋友圈
  void _openMoments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MomentsScreen(),
      ),
    );
  }


  /// 打开角色设定编辑
  void _openCharacterProfile(BuildContext context) {
    final session = _currentSession ?? widget.session;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditorScreen(
          characterId: session.aiCharacterId,
        ),
      ),
    );
  }


  /// 打开记忆回溯（按当前角色过滤）
  void _openMemoryRecall(BuildContext context) {
    final session = _currentSession ?? widget.session;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryScreen(),
      ),
    );
  }


  void _showPersonaEvolutionNotice(ChatPersonaEvolved state) {
    final isQualitative = state.mode == 'qualitative';
    final title = isQualitative ? '人格发生了质变' : '角色发生了成长';
    final iconData = isQualitative ? Icons.psychology : Icons.spa;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconData, size: 16),
                const SizedBox(width: 4),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(state.summary),
          ],
        ),
        action: SnackBarAction(
          label: '查看',
          onPressed: () => _openChatSettings(context),
        ),
      ),
    );
  }


  void _showMoreActions() {
    tapHaptic();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Text('更多功能',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  )),
            ),
            Row(
              children: [
                _MoreActionItem(
                  icon: Icons.card_giftcard,
                  label: '转账',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransferDialog();
                  },
                ),
                const SizedBox(width: 16),
                if (_isWeChatStyle) ...[
                  _MoreActionItem(
                    icon: Icons.monetization_on,
                    label: '红包',
                    color: const Color(0xFFE06A4E),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showRedPacketDialog();
                    },
                  ),
                  const SizedBox(width: 16),
                ],
                _MoreActionItem(
                  icon: Icons.storefront,
                  label: '商店',
                  color: const Color(0xFF667EEA),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider.value(
                          value: context.read<ShopBloc>(),
                          child: ShopScreen(
                            chatSessionId: widget.session.id,
                            receiverId: widget.session.aiCharacterId,
                            receiverName: widget.session.aiCharacterName,
                            onGiftSent: (order) {
                              final authState = context.read<AuthBloc>().state;
                              if (authState is AuthAuthenticated) {
                                context.read<ChatBloc>().add(ChatSendGift(
                                      chatId: widget.session.id,
                                      userId: authState.user.id,
                                      itemName: order.itemName,
                                      itemEmoji: order.itemEmoji,
                                      price: order.price,
                                      message: order.message,
                                      itemCategory: order.itemCategory,
                                      itemDescription: order.itemDescription,
                                      isCustomItem: order.isCustomItem,
                                    ));
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MoreActionItem(
              icon: Icons.photo_outlined,
              label: '图片',
              color: const Color(0xFF3B82F6),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndAttachImages();
              },
            ),
            const SizedBox(height: 16),
            _MoreActionItem(
              icon: Icons.record_voice_over_outlined,
              label: '音色克隆',
              color: const Color(0xFF10B981),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceCloneScreen(
                      characterId: widget.session.aiCharacterId,
                      characterName: widget.session.aiCharacterName,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 本地语音：模型下载 / 录音转文字 / AI 回复合成播放
  // ─────────────────────────────────────────────────────────────────────────

}
