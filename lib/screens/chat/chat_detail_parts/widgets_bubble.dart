// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? aiAvatarUrl;
  final String? userAvatarUrl;
  final String aiName;
  final VoidCallback? onImageTap;
  final bool hasBackgroundImage;
  final IconData? weatherIcon;

  /// 小说模式下，把 AI 文本里的对白（引号包裹）着蓝色，旁白保持默认色。
  final bool novelMode;

  /// 小说模式对白颜色（亮色主题）。null 时使用默认蓝色。
  final Color? dialogueColorLight;

  /// 小说模式对白颜色（暗色主题）。null 时使用默认蓝色。
  final Color? dialogueColorDark;

  /// AI 文本消息的「播放语音」回调（null 则不显示按钮）。
  final VoidCallback? onPlayVoice;

  /// 该消息是否正在合成/播放语音（用于按钮态）。
  final bool voiceBusy;

  /// 微信风格：绿/白气泡、无描边、小圆角。
  final bool wechatStyle;

  /// 转账/红包卡片点击回调（领取/拆包由上层 ChatBloc 处理）。
  final VoidCallback? onMoneyTap;

  const _MessageBubble({
    required this.message,
    this.aiAvatarUrl,
    this.userAvatarUrl,
    this.aiName = 'AI',
    this.onImageTap,
    this.hasBackgroundImage = false,
    this.weatherIcon,
    this.novelMode = false,
    this.dialogueColorLight,
    this.dialogueColorDark,
    this.onPlayVoice,
    this.voiceBusy = false,
    this.wechatStyle = false,
    this.onMoneyTap,
  });

  // 暗色叙事界面：暖灰正文 + 克制酒红强调，不使用高饱和即时通讯蓝。
  // 18.3.0 沉浸式：深色气泡半透明化，融入角色氛围渐变背景。
  static const Color _douyinBlue = Color(0xFFB86F76);
  static const Color _douyinBlueDark = Color(0xD9C88383); // 酒粉 85%
  static const Color _bubbleLight = Color(0xFFFFFFFF);
  static const Color _bubbleDark = Color(0x14FFFFFF); // 白 8% 半透明
  static const Color _bubbleDarkBorder = Color(0x1AFFFFFF); // 白 10% 描边
  static const Color _textOnBlue = Color(0xFFFFF8F3);
  static const Color _textOnWhite = Color(0xFF302B29);
  static const Color _textOnDark = Color(0xFFEDE7DF);
  static const double _avatarSize = 32.0;
  static const double _bubbleRadius = 14.0;
  static const double _hPad = 16.0;

  /// 匹配对白：中文弯引号「”…”」、直角引号「」/『』。
  /// 故意不匹配英文直双引号 “...”——AI 日常回复中引用/强调也会用它，误判率高。
  static final RegExp _dialogueRe = RegExp(r'”[^”]*”|「[^」]*」|『[^』]*』');

  /// 匹配动作/神态描写括号：（...）或 (...)
  static final RegExp _actionBracketRe = RegExp(r'[（(]([^（)()]+)[）)]');

  /// 将文本按动作括号拆分为富文本片段，括号内文字用斜体+灰色渲染
  static List<InlineSpan>? _buildActionBracketSpans(
      String text, TextStyle baseStyle) {
    final matches = _actionBracketRe.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final spans = <InlineSpan>[];
    var cursor = 0;
    final bracketStyle = baseStyle.copyWith(
      fontStyle: FontStyle.italic,
      color: baseStyle.color?.withOpacity(0.55),
      fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 0.9 : 13.5,
      height: 1.3,
    );
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
            TextSpan(text: text.substring(cursor, m.start), style: baseStyle));
      }
      // 保留括号符号 + 内部文字，整体用斜体灰色
      spans.add(TextSpan(text: m.group(0), style: bracketStyle));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  /// 把一段文本按「引号内=对白（蓝色）/引号外=旁白（默认色）」拆成富文本片段。
  /// 若文本里没有任何对白引号，返回 null（外层回退到普通 Text）。
  /// 单个引号对内字符超过此长度时，视为旁白被误包，跳过对白着色。
  static const int _maxDialogueLen = 30;

  /// 身体感受/内心体感关键词，命中表示引号内内容大概率是内心感受而非口头台词
  static final RegExp _bodySensationRe =
      RegExp(r'身体|体内|脊椎|神经|四肢|胸口|腹部|皮肤|肌肉|骨骼|喉咙|眼眶|鼻腔|舌尖|指尖|掌心|脚底|'
          r'异物感|发麻|酸麻|酸痛|酥麻|刺痒|痉挛|颤抖|发烫|发热|发冷|冷汗|燥热|'
          r'生理|私密|深处|内部|器官|分泌|'
          r'心跳|呼吸急促|呼吸紊乱|呼吸困难|窒息|眩晕|发软|乏力|瘫软|'
          r'感觉.*蠕动|感觉.*触感|感觉.*电流|感觉.*划过|感觉.*侵入|感觉.*进入|感觉.*涌入|'
          r'蔓延|肿胀|抽搐|收缩|扩张|紧绷|松弛|湿润|干燥|黏腻|'
          r'脑子|大脑|意识|神经末梢|敏感|滚烫|冰凉');

  /// 典型对话标记：短句 + 口语语气词，大概率是口头台词
  static final RegExp _dialogueMarkerRe =
      RegExp(r'[？！?！～~]|[啦吧呢吗啊呀哦嗯嘿哈呵哎哟]|^.{1,8}$');

  static List<InlineSpan>? _buildDialogueSpans(
      String text, TextStyle baseStyle, Color dialogueColor) {
    final matches = _dialogueRe.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
            TextSpan(text: text.substring(cursor, m.start), style: baseStyle));
      }
      final inner = text.substring(m.start, m.end);
      final isDialogue = _isSpokenDialogue(inner);
      spans.add(TextSpan(
        text: inner,
        style: isDialogue
            ? baseStyle.copyWith(
                color: dialogueColor, fontWeight: FontWeight.w600)
            : baseStyle,
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  /// 判断引号内文本是否为真正的口头台词（说出口的话）
  /// 返回 false 表示大概率是内心感受/旁白，应降级为旁白颜色
  static bool _isSpokenDialogue(String inner) {
    // 去掉引号符号本身
    final content = inner.replaceAll(RegExp(r'[""「」『』]'), '').trim();
    if (content.isEmpty) return false;

    // 规则1：超过长度阈值，大概率是旁白
    if (content.length > _maxDialogueLen) return false;

    // 规则2：有对话标记（？、！、口语语气词）且很短，大概率是台词
    final hasDialogueMarker = _dialogueMarkerRe.hasMatch(content);
    if (hasDialogueMarker && content.length <= 12) return true;

    // 规则3：命中身体感受关键词，且没有对话标记 → 内心体感
    if (_bodySensationRe.hasMatch(content) && !hasDialogueMarker) return false;

    // 规则4：命中身体感受关键词，但有对话标记 → 仍需判断
    // 如果身体感受关键词占比高（连续身体描述），仍视为旁白
    if (_bodySensationRe.hasMatch(content) && hasDialogueMarker) {
      final sensationMatches = _bodySensationRe.allMatches(content).length;
      if (sensationMatches >= 2 && content.length > 12) return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAI = message.isFromAI;
    final isRecalled =
        message.metadata?['recalled'] == true || message.content == '已撤回';
    final isTransfer = message.type == MessageType.system &&
        message.metadata?['type'] == 'red_packet';
    final isShopOrder = message.type == MessageType.system &&
        message.metadata?['type'] == 'shop_order';
    final isMoneyMsg = message.type == MessageType.transfer ||
        message.type == MessageType.redPacket;
    final brightness = Theme.of(context).brightness;
    // 微信风格：自己=官方绿 #95EC69，对方=白/#2C2C2C，黑字/深字
    final userBubbleColor = wechatStyle
        ? WeChatColors.bubbleMine
        : brightness == Brightness.dark
            ? _douyinBlueDark
            : _douyinBlue;
    final aiBubbleColor = wechatStyle
        ? (brightness == Brightness.dark
            ? WeChatColors.darkBubbleOther
            : WeChatColors.bubbleOther)
        : brightness == Brightness.dark
            ? _bubbleDark
            : _bubbleLight;
    final userTextColor = wechatStyle
        ? (brightness == Brightness.dark
            ? WeChatColors.darkBubbleMineText
            : WeChatColors.bubbleMineText)
        : _textOnBlue;
    final aiTextColor = wechatStyle
        ? (brightness == Brightness.dark
            ? WeChatColors.darkBubbleOtherText
            : WeChatColors.bubbleOtherText)
        : brightness == Brightness.dark
            ? _textOnDark
            : _textOnWhite;
    final displayText = MessageSanitizer.removeRepeatedContent(message.content);
    final webSearchTrace = message.metadata?['webSearchTrace'];

    // 系统消息居中显示（如通话记录）
    if (message.isSystem) {
      // 通话记录消息：专用卡片（时长 + 发起人）
      if (message.metadata?['type'] == 'voice_call') {
        return _buildVoiceCallRecord(message);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: _hPad),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (isTransfer) {
      debugPrint(
          '[SYNC] _MessageBubble.build: transferStatus=${message.metadata?['transferStatus'] ?? 'pending'}, msgId=${message.id.substring(0, 8)}...');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isAI ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        // ═══════════════════════════════════════════════════
        // 图片消息 - 像微信那样独立显示，不包裹在气泡里
        // ═══════════════════════════════════════════════════
        if (message.type == MessageType.image)
          Padding(
            padding: EdgeInsets.only(
              left: isAI ? _hPad : _hPad + _avatarSize + 8.0,
              right: isAI ? _hPad + _avatarSize + 8.0 : _hPad,
              top: 4,
              bottom: 2,
            ),
            child: Column(
              crossAxisAlignment:
                  isAI ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // AI图片：头像在上方左侧，图片在下方
                // 用户图片：头像在右侧，图片在左侧
                if (isAI) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildAvatar(isAI: true),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ],
                GestureDetector(
                  onTap: onImageTap,
                  child: Hero(
                    tag: 'chat_image_${message.id}',
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.55,
                        maxHeight: 320,
                        minWidth: 120,
                        minHeight: 120,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(message.content),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 200,
                            height: 200,
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(Icons.broken_image,
                                  size: 48, color: colorScheme.outline),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 用户图片：头像在图片右下角
                if (!isAI) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const SizedBox(width: 8),
                        _buildAvatar(isAI: false),
                      ],
                    ),
                  ),
                ],
                // 图片描述/配文
                if (((message.metadata?['caption'] ?? message.metadata?['text'])
                        ?.toString()
                        .isNotEmpty ??
                    false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      (message.metadata?['caption'] ??
                              message.metadata?['text'])
                          .toString(),
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _hPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment:
                  isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (isAI) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAvatar(isAI: true),
                      if (weatherIcon != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(weatherIcon,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withOpacity(0.5)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                if (!isAI && message.status == MessageStatus.failed) ...[
                  Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
                  const SizedBox(width: 4),
                ],
                if (isMoneyMsg) ...[
                  MoneyMessageCard(
                    message: message,
                    isDark: brightness == Brightness.dark,
                    onTap: onMoneyTap,
                  ),
                ] else if (isTransfer) ...[
                  TransferCard(
                    amount: double.tryParse(message.content) ?? 0.0,
                    message: message.metadata?['message'] as String?,
                    isFromUser: !isAI,
                    transferStatus:
                        message.metadata?['transferStatus'] as String? ??
                            'pending',
                    direction: message.metadata?['direction'] as String?,
                  ),
                ] else if (isShopOrder) ...[
                  OrderCard(
                    order: ShopOrder.fromMetadata(message.metadata!),
                    isFromUser: !isAI,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<ShopBloc>(),
                            child: const OrderTrackingScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ] else
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: wechatStyle
                            ? MediaQuery.of(context).size.width *
                                WeChatDimens.bubbleMaxWidthRatio
                            : double.infinity,
                      ),
                      child: Container(
                      padding: wechatStyle
                          ? const EdgeInsets.symmetric(
                              horizontal: WeChatDimens.bubblePadH,
                              vertical: WeChatDimens.bubblePadV)
                          : const EdgeInsets.symmetric(
                              horizontal: 17, vertical: 15),
                      decoration: BoxDecoration(
                        color: isRecalled
                            ? (brightness == Brightness.dark
                                ? _bubbleDark
                                : const Color(0xFFF0F0F0))
                            : (isAI ? aiBubbleColor : userBubbleColor),
                        borderRadius: BorderRadius.circular(
                            wechatStyle ? 6.0 : _bubbleRadius),
                        border: isAI && !isRecalled && !wechatStyle
                            ? Border.all(
                                color: brightness == Brightness.dark
                                    ? _bubbleDarkBorder
                                    : Colors.black.withOpacity(0.07),
                              )
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.metadata?['replyTo'] != null)
                            _buildReplyPreview(
                                context,
                                colorScheme,
                                message.metadata!['replyTo']
                                    as Map<String, dynamic>),
                          if (message.type == MessageType.sticker)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: message.metadata?['isBuiltinSticker'] ==
                                      true
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        BuiltinStickerService
                                            .getStickerAssetPath(
                                          message.metadata?['stickerFile']
                                                  as String? ??
                                              BuiltinStickerService
                                                      .findStickerById(
                                                          message.content)
                                                  ?.file ??
                                              '',
                                        ),
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          width: 120,
                                          height: 120,
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          child: Center(
                                            child: Icon(Icons.broken_image,
                                                size: 32,
                                                color: colorScheme.outline),
                                          ),
                                        ),
                                      ),
                                    )
                                  : message.metadata?['isImageSticker'] == true
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            File(message.content),
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              width: 120,
                                              height: 120,
                                              color: colorScheme
                                                  .surfaceContainerHighest,
                                              child: Center(
                                                child: Icon(Icons.broken_image,
                                                    size: 32,
                                                    color: colorScheme.outline),
                                              ),
                                            ),
                                          ),
                                        )
                                      : Text(
                                          message.content,
                                          style: const TextStyle(fontSize: 32),
                                        ),
                            )
                          else ...[
                            if (isAI && webSearchTrace is Map<String, dynamic>)
                              _WebSearchSection(trace: webSearchTrace),
                            if (isAI &&
                                !isRecalled &&
                                message.reasoning != null &&
                                message.reasoning!.isNotEmpty)
                              _ReasoningSection(reasoning: message.reasoning!),
                            if (isAI &&
                                !isRecalled &&
                                message.metadata?['aiEmotion'] != null)
                              _buildEmotionChip(context,
                                  message.metadata!['aiEmotion'] as String),
                            Builder(builder: (_) {
                              final baseColor = isRecalled
                                  ? (isAI
                                      ? aiTextColor.withOpacity(0.5)
                                      : userTextColor.withOpacity(0.5))
                                  : (isAI ? aiTextColor : userTextColor);
                              final baseStyle = TextStyle(
                                color: baseColor,
                                fontSize:
                                    wechatStyle ? WeChatDimens.bubbleTextSize : 15,
                                height: wechatStyle ? 1.32 : 1.4,
                                fontStyle: isRecalled
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              );
                              // 小说模式：AI 的对白（引号内）着蓝色，旁白保持默认。
                              if (!isRecalled && isAI && novelMode) {
                                final dialogueColor =
                                    brightness == Brightness.dark
                                        ? (dialogueColorDark ?? _douyinBlueDark)
                                        : (dialogueColorLight ?? _douyinBlue);
                                final spans = _buildDialogueSpans(
                                    displayText, baseStyle, dialogueColor);
                                if (spans != null) {
                                  return Text.rich(TextSpan(children: spans));
                                }
                              }
                              // 动作括号渲染：用户消息或 AI 消息中包含（...）时，
                              // 用斜体+灰色区分动作/神态描写与普通文本
                              if (!isRecalled &&
                                  message.metadata?['hasActionBracket'] ==
                                      true) {
                                final bracketSpans = _buildActionBracketSpans(
                                    displayText, baseStyle);
                                if (bracketSpans != null) {
                                  return Text.rich(
                                      TextSpan(children: bracketSpans));
                                }
                              }
                              // 非小说模式：统一使用 SelectableText，
                              // 解决中文双引号异常换行的问题。
                              // Text widget 会把引号当作断点，SelectableText
                              // 配合 textWidthBasis 让中文排版更自然。
                              return SelectableText(
                                isRecalled ? '已撤回' : displayText,
                                style: baseStyle,
                                textWidthBasis: TextWidthBasis.parent,
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ),
                if (!isAI) ...[
                  const SizedBox(width: 8),
                  _buildAvatar(isAI: false),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isAI ? _hPad + _avatarSize + 8.0 : 0,
              right: isAI ? 0 : _hPad + _avatarSize + 8.0,
              top: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(
                    fontSize: wechatStyle ? WeChatDimens.timestampSize : 11,
                    color: isRecalled
                        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                        : colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                if (isAI &&
                    onPlayVoice != null &&
                    !isRecalled &&
                    message.type != MessageType.image &&
                    message.type != MessageType.sticker &&
                    displayText.trim().isNotEmpty) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: voiceBusy ? null : onPlayVoice,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: voiceBusy
                          ? CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            )
                          : Icon(
                              Icons.volume_up_outlined,
                              size: 15,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                    ),
                  ),
                ],
                if (!isAI) ...[
                  const SizedBox(width: 4),
                  MessageStatusIndicator(
                    state: _deliveryState(message.status),
                    onRetry: message.status == MessageStatus.failed
                        ? () =>
                            context.read<ChatBloc>().add(ChatRegenerateAIReply(
                                  chatId: message.chatId,
                                  messageId: message.id,
                                ))
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ], // else end
      ],
    );
  }

  Widget _buildStatusIcon(MessageStatus status, ColorScheme colorScheme) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colorScheme.onSurface.withOpacity(0.3)));
      case MessageStatus.sent:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.delivered:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.failed:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.read:
        return Text('已读',
            style: TextStyle(
                fontSize: 10,
                color: Colors.blue[400],
                fontWeight: FontWeight.w500));
      case MessageStatus.error:
      case MessageStatus.cancelled:
        return Text('失败',
            style: TextStyle(
                fontSize: 10, color: colorScheme.error.withOpacity(0.6)));
    }
  }

  MessageDeliveryState _deliveryState(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return MessageDeliveryState.sending;
      case MessageStatus.read:
        return MessageDeliveryState.read;
      case MessageStatus.failed:
      case MessageStatus.error:
        return MessageDeliveryState.failed;
      case MessageStatus.cancelled:
        return MessageDeliveryState.cancelled;
      case MessageStatus.sent:
      case MessageStatus.delivered:
        return MessageDeliveryState.sent;
    }
  }

  /// AI 消息上的情绪小图标（从 metadata 读取持久化情绪）
  Widget _buildEmotionChip(BuildContext context, String emotionName) {
    final emotion =
        EmotionType.values.where((e) => e.name == emotionName).firstOrNull;
    if (emotion == null || emotion == EmotionType.calm) {
      return const SizedBox.shrink();
    }
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(emotion.icon, size: 13, color: emotion.color),
          const SizedBox(width: 3),
          Text(
            emotion.label,
            style: TextStyle(
              fontSize: 11,
              color: brightness == Brightness.dark
                  ? emotion.color.withValues(alpha: 0.8)
                  : emotion.color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context, ColorScheme colorScheme,
      Map<String, dynamic> replyTo) {
    final senderName = replyTo['senderName'] as String? ?? '';
    final contentPreview = replyTo['contentPreview'] as String? ?? '';
    final isAI = message.isFromAI;
    final brightness = Theme.of(context).brightness;
    final replyBg = isAI
        ? (brightness == Brightness.dark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05))
        : Colors.white.withOpacity(0.15);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: replyBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: isAI
                  ? colorScheme.primary.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isAI
                  ? colorScheme.primary.withOpacity(0.8)
                  : Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            contentPreview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isAI
                  ? colorScheme.onSurface.withOpacity(0.65)
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isAI}) {
    final avatarUrl = isAI ? aiAvatarUrl : userAvatarUrl;
    if (wechatStyle) {
      return WeChatAvatar(
        imageUrl: avatarUrl,
        size: WeChatDimens.chatAvatarSize,
        fallbackText: isAI ? aiName : '我',
      );
    }
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: _buildAvatarImage(avatarUrl, _avatarSize, isAI),
      ),
    );
  }

  Widget _buildAvatarImage(String? avatarUrl, double size, bool isAI) {
    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: size,
      height: size,
      onError: () => _buildDefaultAvatar(isAI: isAI, size: size),
    );
    if (image != null) return image;
    return _buildDefaultAvatar(isAI: isAI, size: size);
  }

  Widget _buildDefaultAvatar({required bool isAI, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isAI ? const Color(0xFFE8E4EC) : const Color(0xFFD2E3FC),
      ),
      child: Icon(
        isAI ? Icons.smart_toy_outlined : Icons.person_outline,
        size: size * 0.6,
        color: isAI ? const Color(0xFF9C27B0) : const Color(0xFF1A73E8),
      ),
    );
  }

  /// 通话记录卡片：居中展示时长 + 发起人 + 通话时间。
  Widget _buildVoiceCallRecord(ChatMessage message) {
    final meta = message.metadata ?? const {};
    final durationSec = (meta['callDurationSec'] as num?)?.toInt() ?? 0;
    final initiatedBy = meta['initiatedBy'] as String? ?? 'user';
    final recordAiName = meta['aiName'] as String? ?? aiName;
    final initiatorText =
        initiatedBy == 'ai' ? '$recordAiName 发起的通话' : '你发起的通话';
    final timeText = DateFormat('MM-dd HH:mm').format(message.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: _hPad),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.call_outlined,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '语音通话 ${_formatCallDuration(durationSec)}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$initiatorText · $timeText',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCallDuration(int sec) {
    if (sec < 60) return '$sec秒';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s > 0 ? '$m分$s秒' : '$m分钟';
  }
}
