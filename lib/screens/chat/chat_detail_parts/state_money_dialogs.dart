// 红包转账（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateMoney on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput {
  /// 转账/红包气泡点击：AI 发来的待收/待拆钱款 → 发起领取（幂等由 ChatBloc 保证）。
  VoidCallback? _moneyTapHandler(ChatMessage message) {
    if (message.type != MessageType.transfer &&
        message.type != MessageType.redPacket) {
      return null;
    }
    final meta = MoneyTransaction.fromMessageMetadata(
        message.metadata?['money'] as Map<String, dynamic>?);
    if (meta == null || meta.txId == null) return null;
    if (meta.status != MoneyStatus.pending) return null;
    if (message.isFromAI) {
      // 用户是收款方/拆包方
      return () {
        if (_isWeChatStyle && message.type == MessageType.redPacket) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RedPacketOpenScreen(
                amount: meta.amount,
                note: meta.note,
                senderName: message.senderName,
              ),
            ),
          ).then((_) {
            if (mounted) {
              context.read<ChatBloc>().add(ChatClaimMoney(
                    chatId: widget.session.id,
                    messageId: message.id,
                  ));
            }
          });
        } else {
          context.read<ChatBloc>().add(ChatClaimMoney(
                chatId: widget.session.id,
                messageId: message.id,
              ));
        }
      };
    }
    return null;
  }


  void _showRedPacketDialog() {
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    final balance = user?.coins ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => MoneySendDialog(
        chatId: widget.session.id,
        characterId: widget.session.aiCharacterId,
        isRedPacket: true,
        balance: balance,
      ),
    );
  }


  void _showTransferDialog() {
    // 微信模式：走新版钱系统（真实扣款 + money_transactions 流水 + 新气泡卡片）
    if (_isWeChatStyle) {
      final user = context.read<AuthBloc>().state is AuthAuthenticated
          ? (context.read<AuthBloc>().state as AuthAuthenticated).user
          : null;
      final balance = user?.coins ?? 0;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
        builder: (ctx) => MoneySendDialog(
          chatId: widget.session.id,
          characterId: widget.session.aiCharacterId,
          isRedPacket: false,
          balance: balance,
        ),
      );
      return;
    }
    final amountController = TextEditingController();
    final msgController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.session.aiCharacterName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      '¥',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          hintStyle:
                              TextStyle(fontSize: 32, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: msgController,
                  decoration: const InputDecoration(
                    hintText: '添加备注（选填）',
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final amountText = amountController.text.trim();
                    if (amountText.isEmpty) return;
                    final amount = double.tryParse(amountText);
                    if (amount == null || amount <= 0) return;
                    if (amount > 200000) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('单次转账上限200000')),
                      );
                      return;
                    }
                    final user = context.read<AuthBloc>().state
                            is AuthAuthenticated
                        ? (context.read<AuthBloc>().state as AuthAuthenticated)
                            .user
                        : null;
                    if (user == null) return;
                    Navigator.pop(ctx);
                    _resetSilenceTimer();
                    _chatBloc.add(ChatSendRedPacket(
                      chatId: widget.session.id,
                      userId: user.id,
                      amount: amount,
                      message: msgController.text.trim().isNotEmpty
                          ? msgController.text.trim()
                          : null,
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('转账',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

}
