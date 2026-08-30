// 红包转账金币（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocSendMoney on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive, _BlocMessageOps {
  Future<void> _onSendRedPacket(
    ChatSendRedPacket event,
    Emitter<ChatState> emit,
  ) async {
    final now = DateTime.now();

    try {
      // 保存转账消息，状态为待处理
      final transferMessage = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: event.userId,
        content: '${event.amount}',
        type: MessageType.system,
        status: MessageStatus.sent,
        createdAt: now,
        isUser: true,
        metadata: {
          'type': 'red_packet',
          'amount': event.amount,
          'message': event.message ?? '',
          'transferStatus': 'pending',
        },
      );
      await _storage.saveChatMessage(transferMessage);

      LogService.instance.i(
          'Transfer', '转账消息已保存 ${event.amount}元 status=pending',
          chatId: event.chatId);

      var messages = await _storage.getChatMessages(event.chatId);
      LogService.instance.i(
          'Transfer', '首轮 emit ChatMessagesLoaded (${messages.length} msgs)',
          chatId: event.chatId);
      emit(ChatMessagesLoaded(messages));

      final session = await _storage.getChatSession(event.chatId);
      if (session == null) {
        LogService.instance.e('Bloc', '_onSendRedPacket: session is null',
            chatId: event.chatId);
        return;
      }
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) {
        LogService.instance.e('Bloc', '_onSendRedPacket: character is null',
            chatId: event.chatId);
        return;
      }

      if (character?.interactionConfig?.replyMode == ReplyMode.manual) {
        LogService.instance.e(
            'Bloc', '_onSendRedPacket: replyMode is manual, skip AI reply',
            chatId: event.chatId);
        return;
      }

      emit(ChatAITyping(messages, character.name));

      // 根据性格决定打字延迟
      int typingDelay = _getTypingDelay(character?.personality ?? '');
      await Future.delayed(Duration(seconds: typingDelay));

      // 获取记忆
      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: event.userId,
        limit: Limit.memoryFetch,
      );

      // 简化为普通消息回复
      final transferContext = '对方给你转了 ${event.amount} 元' +
          (event.message != null && event.message!.isNotEmpty
              ? '，备注：${event.message}'
              : '') +
          '。请做出真实自然的回应。';

      final aiResponse = await _bridgeSendMessage(
        character: character,
        userId: event.userId,
        userMessage: transferContext,
        chatHistory: messages,
        memories: memories,
        intimacyLevel: session.intimacyLevel,
      );

      final responseText = aiResponse.trim().isNotEmpty
          ? MessageSanitizer.filterForbiddenPhrases(
              MessageSanitizer.sanitizeFinal(_stripAIStickerOutput(aiResponse)),
              _storage.getForbiddenPhrases(),
            )
          : '收到啦，谢谢';

      await _storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: responseText,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      ));

      // 更新转账状态为已收款
      final updatedMetadata =
          Map<String, dynamic>.from(transferMessage.metadata ?? {});
      updatedMetadata['transferStatus'] = 'accepted';
      await _storage.updateMessageMetadata(transferMessage.id, updatedMetadata);

      LogService.instance
          .i('Transfer', '转账状态已更新为 accepted', chatId: event.chatId);

      messages = await _storage.getChatMessages(event.chatId);
      emit(ChatTransferStatusUpdated(
        messageId: transferMessage.id,
        transferStatus: 'accepted',
        messages: messages,
      ));
      emit(ChatMessagesLoaded(messages));
    } catch (e) {
      LogService.instance.e('Transfer', '转账流程异常: $e', chatId: event.chatId);
      emit(ChatError('转账发送失败'));
    }
  }


  Future<void> _onSendGift(
    ChatSendGift event,
    Emitter<ChatState> emit,
  ) async {
    try {
      var messages = await _storage.getChatMessages(event.chatId);

      final session = await _storage.getChatSession(event.chatId);
      if (session == null) return;
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) return;

      if (character.interactionConfig?.replyMode == ReplyMode.manual) return;

      emit(ChatAITyping(messages, character.name));

      int typingDelay = _getTypingDelay(character.personality);
      await Future.delayed(Duration(seconds: typingDelay));

      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: event.userId,
        limit: Limit.memoryFetch,
      );

      final catLabel = switch (event.itemCategory) {
        'food' => '外卖/食物',
        'express' => '快递/物件',
        'gift' => '礼物',
        _ => '心意礼物',
      };
      final desc = event.itemDescription?.trim() ?? '';
      final customHint = event.isCustomItem
          ? '这是用户专门为你挑选/自制的自定义商品，请认真理解商品说明并回应。'
          : '请根据商品本身的含义做出自然回应。';
      final giftContext = StringBuffer()
        ..writeln('【用户送礼场景 · 请识别并回应】')
        ..writeln('对方送给你：${event.itemEmoji} ${event.itemName}')
        ..writeln('类型：$catLabel')
        ..writeln('价值：${event.price} 金币')
        ..writeln(customHint);
      if (desc.isNotEmpty) {
        giftContext.writeln('商品说明（务必理解）：$desc');
      }
      if (event.message != null && event.message!.trim().isNotEmpty) {
        giftContext.writeln('用户附言：${event.message!.trim()}');
      }
      giftContext.writeln('请用角色身份真实自然地回应：可以感动、吐槽、开心或接住附言；'
          '要体现你「看懂了」这件东西是什么，不要只说谢谢。');

      final aiResponse = await _bridgeSendMessage(
        character: character,
        userId: event.userId,
        userMessage: giftContext.toString(),
        chatHistory: messages,
        memories: memories,
        intimacyLevel: session.intimacyLevel,
      );

      final responseText = aiResponse.trim().isNotEmpty
          ? MessageSanitizer.filterForbiddenPhrases(
              MessageSanitizer.sanitizeFinal(_stripAIStickerOutput(aiResponse)),
              _storage.getForbiddenPhrases(),
            )
          : '收到啦，谢谢';

      // 2. 保存AI回复消息
      await _storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: responseText,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      ));

      messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(messages));
    } catch (e) {
      LogService.instance.e('ChatBloc', '礼物回复失败: $e');
    }
  }


  Future<void> _onAISendCoins(
    ChatAISendCoins event,
    Emitter<ChatState> emit,
  ) async {
    final now = DateTime.now();

    try {
      final intAmount = event.amount.toInt();
      // 检查 AI 余额
      final wallet = await _storage.getAIWallet(event.characterId);
      if (wallet == null || wallet.balance < intAmount) {
        LogService.instance.e('Money', 'AI余额不足', chatId: event.chatId);
        return;
      }

      // 扣除 AI 金币（先扣后挂账，收款时入账用户；过期退回见 _onClaimMoney）
      final deducted = await _storage.deductAICoins(event.characterId, intAmount);
      if (!deducted) {
        LogService.instance.e('Money', 'AI金币扣除失败', chatId: event.chatId);
        return;
      }

      final session = await _storage.getChatSession(event.chatId);
      if (session == null) return;
      final character =
          await _storage.getAICharacter(session.aiCharacterId);

      // 流水（pending，等用户点击收款/拆开）
      final messageId = _uuid.v4();
      final tx = MoneyTransaction(
        id: _uuid.v4(),
        kind: event.isRedPacket ? MoneyKind.redPacket : MoneyKind.transfer,
        userToCharacter: false,
        chatId: event.chatId,
        messageId: messageId,
        characterId: event.characterId,
        userId: session.userId,
        amount: intAmount,
        note: event.message,
        status: MoneyStatus.pending,
        receiverName: character?.name,
        createdAt: now,
        expireAt: now.add(const Duration(hours: 24)),
      );
      await _storage.saveMoneyTransaction(tx);

      // 新钱系统气泡
      await _storage.saveChatMessage(ChatMessage(
        id: messageId,
        chatId: event.chatId,
        senderId: 'ai_${event.characterId}',
        senderName: character?.name ?? '',
        content: '$intAmount',
        type: event.isRedPacket ? MessageType.redPacket : MessageType.transfer,
        status: MessageStatus.sent,
        createdAt: now,
        metadata: {'money': tx.toMessageMetadata()},
      ));

      await _storage.updateChatSessionLastMessage(
        event.chatId,
        event.isRedPacket ? '[红包]' : '[转账]',
        now,
      );

      LogService.instance.i('Money',
          'AI发出${event.isRedPacket ? '红包' : '转账'}: ${intAmount}金币 status=pending',
          chatId: event.chatId);

      final messages = await _storage.getChatMessages(event.chatId);
      emit(ChatAICoinsSent(
        characterId: event.characterId,
        amount: event.amount,
        messages: messages,
      ));
      emit(ChatMessagesLoaded(messages));
    } catch (e) {
      LogService.instance.e('Money', 'AI转账异常: $e', chatId: event.chatId);
      emit(ChatError('AI转账失败'));
    }
  }


  /// 新版钱系统：用户 → 角色 转账/红包。
  /// 真实扣款（spendCoins 内部处理免费模式）+ money_transactions 流水 +
  /// 新气泡（MessageType.transfer/redPacket）+ 角色回应后确认收款入账角色钱包。
  Future<void> _onSendMoneyMessage(
    ChatSendMoneyMessage event,
    Emitter<ChatState> emit,
  ) async {
    final now = DateTime.now();
    try {
      if (event.amount < 1 || event.amount > 2000) {
        emit(ChatError('金额需在 1-2000 之间'));
        return;
      }
      final session = await _storage.getChatSession(event.chatId);
      if (session == null) {
        LogService.instance
            .e('Money', '_onSendMoneyMessage: session null', chatId: event.chatId);
        return;
      }
      final character = await _storage.getAICharacter(event.characterId);
      if (character == null) {
        LogService.instance
            .e('Money', '_onSendMoneyMessage: character null', chatId: event.chatId);
        return;
      }
      final userId = session.userId;

      // 1) 扣款（免费模式恒成功）；失败即余额不足，不落任何消息
      final spent = await _storage.spendCoins(userId, event.amount);
      if (!spent) {
        emit(ChatError('余额不足'));
        return;
      }

      // 2) 落流水（pending）
      final messageId = _uuid.v4();
      final tx = MoneyTransaction(
        id: _uuid.v4(),
        kind: event.isRedPacket ? MoneyKind.redPacket : MoneyKind.transfer,
        userToCharacter: true,
        chatId: event.chatId,
        messageId: messageId,
        characterId: event.characterId,
        userId: userId,
        amount: event.amount,
        note: event.note,
        status: MoneyStatus.pending,
        receiverName: character.name,
        createdAt: now,
        expireAt: now.add(const Duration(hours: 24)),
      );
      await _storage.saveMoneyTransaction(tx);

      // 3) 气泡消息
      await _storage.saveChatMessage(ChatMessage(
        id: messageId,
        chatId: event.chatId,
        senderId: userId,
        content: '${event.amount}',
        type: event.isRedPacket ? MessageType.redPacket : MessageType.transfer,
        status: MessageStatus.sent,
        createdAt: now,
        isUser: true,
        metadata: {'money': tx.toMessageMetadata()},
      ));

      await _storage.updateChatSessionLastMessage(
        event.chatId,
        event.isRedPacket ? '[红包]' : '[转账]',
        now,
      );

      var messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(messages));

      // 4) 角色回应（manual 模式不回）
      if (character.interactionConfig?.replyMode == ReplyMode.manual) return;
      emit(ChatAITyping(messages, character.name));
      await Future.delayed(Duration(seconds: _getTypingDelay(character.personality)));

      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: userId,
        limit: Limit.memoryFetch,
      );
      final kindLabel = event.isRedPacket ? '红包' : '转账';
      final buf = StringBuffer()
        ..write(event.isRedPacket
            ? '对方给你发了一个红包'
            : '对方给你转了一笔账')
        ..write('，金额：${event.amount} 金币');
      if (event.note != null && event.note!.isNotEmpty) {
        buf.write('，备注：${event.note}');
      }
      buf.write('。请根据角色性格做出真实自然的回应。');

      final aiResponse = await _bridgeSendMessage(
        character: character,
        userId: userId,
        userMessage: buf.toString(),
        chatHistory: messages,
        memories: memories,
        intimacyLevel: session.intimacyLevel,
      );
      final responseText = aiResponse.trim().isNotEmpty
          ? MessageSanitizer.filterForbiddenPhrases(
              MessageSanitizer.sanitizeFinal(_stripAIStickerOutput(aiResponse)),
              _storage.getForbiddenPhrases(),
            )
          : (event.isRedPacket ? '谢谢老板的红包！' : '收到啦，谢谢！');
      await _storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: responseText,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      ));

      // 5) 角色确认收款：入账角色钱包 + 流水状态机推进 + 刷新气泡快照
      final acceptedStatus =
          event.isRedPacket ? MoneyStatus.opened : MoneyStatus.accepted;
      await _storage.addAICoins(event.characterId, event.amount);
      await _storage.updateMoneyTransactionStatus(tx.id, acceptedStatus,
          actedAt: DateTime.now());
      final moneyMeta = tx.toMessageMetadata()..update('status', (_) => acceptedStatus.name);
      await _storage.updateMessageMetadata(messageId, {'money': moneyMeta});
      LogService.instance.i('Money',
          '用户$kindLabel ${event.amount}金币 已被角色接收 status=${acceptedStatus.name}',
          chatId: event.chatId);

      messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMoneyStatusUpdated(
        messageId: messageId,
        status: acceptedStatus,
        messages: messages,
      ));
      emit(ChatMessagesLoaded(messages));
    } catch (e) {
      LogService.instance
          .e('Money', '_onSendMoneyMessage 异常: $e', chatId: event.chatId);
      emit(ChatError('发送失败'));
    }
  }


  /// 用户收款（AI→用户）/拆红包。幂等：终态流水不再处理；
  /// 超时则标记 expired 并原路退回角色钱包。
  Future<void> _onClaimMoney(
    ChatClaimMoney event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final tx = await _storage.getMoneyTransactionByMessage(event.messageId);
      if (tx == null) {
        LogService.instance
            .e('Money', '_onClaimMoney: 流水不存在 messageId=${event.messageId}',
                chatId: event.chatId);
        return;
      }
      if (tx.isTerminal) return;
      if (tx.userToCharacter) return; // 用户发出方无可领取动作

      final now = DateTime.now();
      final expired = now.isAfter(tx.expireAt);
      final finalStatus =
          expired ? MoneyStatus.expired : MoneyStatus.accepted;

      if (!expired) {
        await _storage.addCoins(tx.userId, tx.amount);
      } else {
        // 过期：原路退回角色钱包
        await _storage.addAICoins(tx.characterId, tx.amount);
      }
      await _storage.updateMoneyTransactionStatus(tx.id, finalStatus,
          actedAt: now);
      final moneyMeta = tx.toMessageMetadata()..update('status', (_) => finalStatus.name);
      await _storage.updateMessageMetadata(tx.messageId, {'money': moneyMeta});

      final messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMoneyStatusUpdated(
        messageId: tx.messageId,
        status: finalStatus,
        messages: messages,
      ));
      emit(ChatMessagesLoaded(messages));
    } catch (e) {
      LogService.instance
          .e('Money', '_onClaimMoney 异常: $e', chatId: event.chatId);
      emit(ChatError('收款失败'));
    }
  }

}
