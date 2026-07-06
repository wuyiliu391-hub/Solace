import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/tarot_card.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';
import '../../services/tarot_service.dart';
import '../chat/chat_detail_screen.dart';

/// 塔罗牌占卜页面 — 和AI角色一起玩塔罗
class TarotScreen extends StatefulWidget {
  final LocalStorageRepository? storage;

  const TarotScreen({super.key, this.storage});

  @override
  State<TarotScreen> createState() => _TarotScreenState();
}

class _TarotScreenState extends State<TarotScreen>
    with TickerProviderStateMixin {
  // 流程: pickCharacter → pickSpread → flipping → revealed
  String _step = 'pickCharacter';
  AICharacter? _selectedCharacter;
  ChatSession? _chatSession;

  SpreadType? _selectedSpread;
  List<TarotCard>? _drawnCards;
  List<bool> _revealed = [];
  List<bool> _cardUpright = [];
  bool _allRevealed = false;
  late AnimationController _bgController;

  final List<AnimationController> _flipControllers = [];
  final List<Animation<double>> _flipAnimations = [];

  List<AICharacter> _characters = [];
  bool _loadingCharacters = true;

  // 占卜前置提问
  String? _userQuestion;
  ThreeCardMode? _selectedThreeCardMode;
  final TextEditingController _questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);
    _loadCharacters();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _questionController.dispose();
    for (final c in _flipControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    if (widget.storage == null) return;
    final chars = await widget.storage!.getAllAICharacters();
    if (mounted) {
      setState(() {
        _characters = chars;
        _loadingCharacters = false;
      });
    }
  }

  void _selectCharacter(AICharacter character) async {
    // 查找或创建聊天会话
    final userId = widget.storage!.getString(PrefKeys.currentUserId) ?? '';
    final sessions = await widget.storage!.getChatSessions(userId);
    ChatSession? existing;
    for (final s in sessions) {
      if (s.aiCharacterId == character.id) {
        existing = s;
        break;
      }
    }

    if (existing == null) {
      // 创建新会话
      final now = DateTime.now();
      existing = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        aiCharacterId: character.id,
        aiCharacterName: character.name,
        aiCharacterAvatar: character.avatarUrl,
        createdAt: now,
        updatedAt: now,
      );
      await widget.storage!.saveChatSession(existing);
    }

    setState(() {
      _selectedCharacter = character;
      _chatSession = existing;
      _step = 'pickSpread';
    });
  }

  void _selectSpread(SpreadType spread) {
    setState(() {
      _selectedSpread = spread;
      // 三牌阵默认选时间流模式
      if (spread == SpreadType.threeCard) {
        _selectedThreeCardMode = ThreeCardMode.timeline;
      } else {
        _selectedThreeCardMode = null;
      }
      _step = 'askQuestion';
    });
  }

  /// 用户确认问题后，开始抽牌翻牌
  void _startReading() {
    final spread = _selectedSpread!;
    final random = Random();
    final cards = TarotDeck.drawRandom(spread.cardCount);
    final upright = List.generate(cards.length, (_) => random.nextBool());

    for (final c in _flipControllers) {
      c.dispose();
    }
    _flipControllers.clear();
    _flipAnimations.clear();

    for (int i = 0; i < cards.length; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      final animation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      _flipControllers.add(controller);
      _flipAnimations.add(animation);
    }

    setState(() {
      _userQuestion = _questionController.text.trim();
      _drawnCards = cards;
      _cardUpright = upright;
      _revealed = List.filled(cards.length, false);
      _allRevealed = false;
      _step = 'flipping';
    });
  }

  void _revealCard(int index) {
    if (_revealed[index]) return;
    HapticFeedback.lightImpact();
    _flipControllers[index].forward();
    setState(() {
      _revealed[index] = true;
    });
    if (_revealed.every((r) => r)) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _allRevealed = true);
      });
    }
  }

  void _goToChat() {
    if (_chatSession == null || _drawnCards == null || _selectedSpread == null) return;

    final message = TarotService.buildTarotMessage(
      userQuestion: _userQuestion,
      spread: _selectedSpread!,
      threeCardMode: _selectedThreeCardMode,
      cards: _drawnCards!,
      uprightFlags: _cardUpright,
      characterName: _selectedCharacter!.name,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          session: _chatSession!,
          initialMessage: message,
        ),
      ),
    );
  }

  void _reset() {
    for (final c in _flipControllers) {
      c.dispose();
    }
    _flipControllers.clear();
    _flipAnimations.clear();
    setState(() {
      _selectedSpread = null;
      _drawnCards = null;
      _revealed = [];
      _cardUpright = [];
      _allRevealed = false;
      _userQuestion = null;
      _selectedThreeCardMode = null;
      _questionController.clear();
      _step = 'pickSpread';
    });
  }

  void _backToCharacterSelect() {
    for (final c in _flipControllers) {
      c.dispose();
    }
    _flipControllers.clear();
    _flipAnimations.clear();
    setState(() {
      _selectedCharacter = null;
      _chatSession = null;
      _selectedSpread = null;
      _drawnCards = null;
      _revealed = [];
      _cardUpright = [];
      _allRevealed = false;
      _userQuestion = null;
      _selectedThreeCardMode = null;
      _questionController.clear();
      _step = 'pickCharacter';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1033), Color(0xFF2d1b69), Color(0xFF0f0c29)],
          ),
        ),
        child: SafeArea(
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 'pickCharacter':
        return _buildCharacterSelection();
      case 'pickSpread':
        return _buildSpreadSelection();
      case 'askQuestion':
        return _buildAskQuestion();
      case 'flipping':
        return _buildCardReading();
      default:
        return _buildCharacterSelection();
    }
  }

  // ─── 选择角色 ───
  Widget _buildCharacterSelection() {
    return Column(
      children: [
        _buildTopBar('选择玩伴', showBack: true),
        if (_loadingCharacters)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          )
        else if (_characters.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sentiment_very_dissatisfied, size: 48, color: Color(0xFFD4AF37)),
                  const SizedBox(height: 16),
                  Text('还没有角色呢',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      )),
                  const SizedBox(height: 8),
                  Text('先去创建一个角色吧～',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 13,
                      )),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: _characters.length,
              itemBuilder: (context, index) {
                final char = _characters[index];
                return _buildCharacterTile(char);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCharacterTile(AICharacter char) {
    return GestureDetector(
      onTap: () => _selectCharacter(char),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD4AF37).withOpacity(0.3),
                    const Color(0xFF8B5CF6).withOpacity(0.3),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  char.name.isNotEmpty ? char.name[0] : '?',
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(char.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    char.personality.length > 30
                        ? '${char.personality.substring(0, 30)}...'
                        : char.personality,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.auto_awesome, size: 24, color: Color(0xFFD4AF37)),
          ],
        ),
      ),
    );
  }

  // ─── 牌阵选择 ───
  Widget _buildSpreadSelection() {
    return Column(
      children: [
        _buildTopBar('和${_selectedCharacter!.name}玩塔罗'),
        Expanded(
          child: Stack(
            children: [
              ...List.generate(20, (i) {
                final random = Random(i);
                return AnimatedBuilder(
                  animation: _bgController,
                  builder: (_, __) {
                    final opacity =
                        (0.3 + 0.7 * (sin(_bgController.value * pi + i) * 0.5 + 0.5));
                    return Positioned(
                      left: random.nextDouble() * MediaQuery.of(context).size.width,
                      top: random.nextDouble() * MediaQuery.of(context).size.height * 0.5,
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: random.nextBool() ? 2 : 3,
                          height: random.nextBool() ? 2 : 3,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 64, color: Color(0xFFD4AF37)),
                    const SizedBox(height: 16),
                    Text(
                      '选一个牌阵',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 40),
                    ...SpreadType.values.map((s) => _buildSpreadOption(s)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpreadOption(SpreadType spread) {
    return GestureDetector(
      onTap: () => _selectSpread(spread),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(spread.icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spread.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Text(spread.description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      )),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  // ─── 输入问题 ───
  Widget _buildAskQuestion() {
    final spread = _selectedSpread!;
    final isThreeCard = spread == SpreadType.threeCard;

    return Column(
      children: [
        _buildTopBar('告诉我你的问题'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 提示文字
                Text(
                  '在抽牌之前，先在心里想好你的问题',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '问题越具体，解读越精准',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                // 问题输入框
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _questionController,
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '例如：最近的感情走向如何？',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 32),

                // 三牌阵解读模式选择
                if (isThreeCard) ...[
                  Text(
                    '选择解读方式',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '根据你的问题选择最合适的解读体系',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 智能推荐提示
                  if (_questionController.text.trim().isNotEmpty)
                    _buildRecommendationHint(),

                  // 模式选择卡片
                  ...ThreeCardMode.values.map((mode) =>
                    _buildThreeCardModeOption(mode),
                  ),
                  const SizedBox(height: 24),
                ],

                // 开始抽牌按钮
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _startReading(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF1a1033),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '开始抽牌',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 跳过提示
                Center(
                  child: GestureDetector(
                    onTap: () {
                      _questionController.clear();
                      _startReading();
                    },
                    child: Text(
                      '不想说也没关系，直接抽牌',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationHint() {
    final recommended = recommendThreeCardMode(_questionController.text.trim());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFD4AF37)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '根据你的问题，推荐「${recommended.name}」模式',
              style: TextStyle(
                color: const Color(0xFFD4AF37).withOpacity(0.8),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreeCardModeOption(ThreeCardMode mode) {
    final isSelected = _selectedThreeCardMode == mode;
    final isRecommended = _questionController.text.trim().isNotEmpty &&
        recommendThreeCardMode(_questionController.text.trim()) == mode;

    return GestureDetector(
      onTap: () => setState(() => _selectedThreeCardMode = mode),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4AF37).withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4AF37).withOpacity(0.5)
                : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(mode.icon, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode.name,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFFD4AF37)
                              : Colors.white.withOpacity(0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '推荐',
                            style: TextStyle(
                              color: const Color(0xFFD4AF37).withOpacity(0.9),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFD4AF37), size: 20),
          ],
        ),
      ),
    );
  }

  // ─── 翻牌 ───
  Widget _buildCardReading() {
    final spread = _selectedSpread!;
    final cards = _drawnCards!;

    return Column(
      children: [
        _buildTopBar('${_selectedCharacter!.name}的塔罗'),
        if (!_allRevealed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '点击牌面翻开，和${_selectedCharacter!.name}一起看',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
        Expanded(
          child: _allRevealed
              ? _buildResultView(cards, spread)
              : _buildCardGrid(cards, spread),
        ),
      ],
    );
  }

  Widget _buildCardGrid(List<TarotCard> cards, SpreadType spread) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: spread.cardCount <= 3
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(cards.length, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _buildTarotCard(i, cards[i], spread),
                      ),
                    );
                  }),
                )
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(cards.length, (i) {
                    return SizedBox(
                      width: 130,
                      child: _buildTarotCard(i, cards[i], spread),
                    );
                  }),
                ),
        ),
      ),
    );
  }

  Widget _buildTarotCard(int index, TarotCard card, SpreadType spread) {
    final isRevealed = _revealed[index];
    return GestureDetector(
      onTap: () => _revealCard(index),
      child: Column(
        children: [
          Text(spread.positionNames[index],
              style: TextStyle(
                color: const Color(0xFFD4AF37).withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              )),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _flipAnimations[index],
            builder: (context, child) {
              final angle = _flipAnimations[index].value * pi;
              final isFront = angle > pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                child: isFront ? _buildCardFront(card) : _buildCardBack(),
              );
            },
          ),
          const SizedBox(height: 8),
          if (isRevealed) ...[
            Text(card.nameCn,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 2),
            Text(
              _cardUpright[index] ? '正位 ↑' : '逆位 ↓',
              style: TextStyle(
                color: _cardUpright[index]
                    ? const Color(0xFFD4AF37)
                    : Colors.redAccent.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: 120,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2d1b69), Color(0xFF4a1a8a)],
        ),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 28, color: Color(0xFFD4AF37)),
            const SizedBox(height: 8),
            Text('SOLACE',
                style: TextStyle(
                  color: const Color(0xFFD4AF37).withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                )),
            const SizedBox(height: 8),
            const Icon(Icons.star, size: 28, color: Color(0xFFD4AF37)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardFront(TarotCard card) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: Container(
        width: 120,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1033), Color(0xFF0f0c29)],
          ),
          border: Border.all(color: const Color(0xFFD4AF37), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withOpacity(0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(card.icon, size: 40),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(card.nameCn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            if (card.arcana == 'minor') ...[
              const SizedBox(height: 4),
              Text(TarotDeck.suitName(card.suit),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 全部翻开后的结果 ───
  Widget _buildResultView(List<TarotCard> cards, SpreadType spread) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 牌面展示
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                return Column(
                  children: [
                    _buildCardFront(cards[i]),
                    const SizedBox(height: 8),
                    Text(spread.positionNames[i],
                        style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                    Text(
                      _cardUpright[i] ? '正位' : '逆位',
                      style: TextStyle(
                        color: _cardUpright[i]
                            ? const Color(0xFFD4AF37)
                            : Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // 牌面概览
          ...List.generate(cards.length, (i) {
            final card = cards[i];
            final isUpright = _cardUpright[i];
            final meaning = isUpright ? card.uprightMeaning : card.reversedMeaning;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(card.icon, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(spread.positionNames[i],
                                style: TextStyle(
                                  color: const Color(0xFFD4AF37).withOpacity(0.8),
                                  fontSize: 11,
                                )),
                            const SizedBox(width: 8),
                            Text('${card.nameCn} · ${isUpright ? "正位" : "逆位"}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(meaning,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                              height: 1.5,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 20),

          // 和TA一起讨论按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _goToChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('和${_selectedCharacter!.name}一起讨论',
                  style: const TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 重新占卜
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            label: const Text('重新抽牌',
                style: TextStyle(color: Colors.white54)),
          ),

          const SizedBox(height: 12),

          // 换个角色
          TextButton.icon(
            onPressed: _backToCharacterSelect,
            icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white38),
            label: const Text('换个玩伴',
                style: TextStyle(color: Colors.white38)),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ─── 通用顶栏 ───
  Widget _buildTopBar(String title, {bool showBack = false}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white70),
            )
          else
            IconButton(
              onPressed: () {
                if (_step == 'pickSpread') {
                  _backToCharacterSelect();
                } else if (_step == 'flipping') {
                  _reset();
                }
              },
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white70),
            ),
          const Spacer(),
          Text(title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
