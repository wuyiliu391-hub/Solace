import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';
import '../../repositories/local_storage_repository.dart';

/// 运势转盘小游戏界面
class LuckyWheelScreen extends StatefulWidget {
  const LuckyWheelScreen({super.key});

  @override
  State<LuckyWheelScreen> createState() => _LuckyWheelScreenState();
}

class _LuckyWheelScreenState extends State<LuckyWheelScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  late Animation<double> _spinAnimation;
  final Random _random = Random();
  bool _isSpinning = false;
  int _selectedIndex = 0;
  String _fortuneResult = '';
  String _aiInterpretation = '';
  bool _showResult = false;
  List<Map<String, dynamic>> _history = [];

  // 八个运势分类
  final List<Map<String, String>> _fortunes = const [
    {'category': '爱运', 'message': '今天桃花运旺盛，有人在默默关注你'},
    {'category': '事业', 'message': '工作上会有新机会，抓住就对了'},
    {'category': '健康', 'message': '身体状况良好，记得按时吃饭'},
    {'category': '学业', 'message': '学习效率很高，适合攻克难题'},
    {'category': '财运', 'message': '小财运降临，可能有意外收获'},
    {'category': '人际', 'message': '人际关系和谐，适合社交活动'},
    {'category': '心情', 'message': '心情明朗，适合做喜欢的事'},
    {'category': '综合', 'message': '万事顺遂，今天是好日子'},
  ];

  // 颜色方案
  final List<Color> _wheelColors = const [
    Color(0xFFFF6B6B), // 爱运 - 珊瑚红
    Color(0xFFFF8A65), // 事业 - 橙色
    Color(0xFFFFAB91), // 健康 - 浅橙
    Color(0xFFF48FB1), // 学业 - 粉色
    Color(0xFFCE93D8), // 财运 - 紫色
    Color(0xFF90CAF9), // 人际 - 蓝色
    Color(0xFF80CBC4), // 心情 - 青色
    Color(0xFFFFCC80), // 综合 - 金色
  ];

  // AI 解读模板
  final Map<String, List<String>> _aiTemplates = const {
    '爱运': [
      '你今天的魅力值爆棚！如果遇到心动的人，大胆去接近吧~',
      '爱运极佳的一天，可能会收到意想不到的关心',
      '今天适合表达爱意，一句真诚的话可能改变一切',
    ],
    '事业': [
      '工作上会有贵人相助，记得把握机会',
      '今天适合推进重要项目，行动力很强',
      '事业运势上升期，付出的努力正在被看见',
    ],
    '健康': [
      '身体状态不错，但别忘了适当休息',
      '今天精力充沛，适合运动锻炼',
      '注意劳逸结合，保持好的作息习惯',
    ],
    '学业': [
      '今天头脑清晰，适合学习新知识',
      '学习运很好，可能会有新发现',
      '专注力在线，效率会比平时高很多',
    ],
    '财运': [
      '小财运不错，可能会有意外的收入',
      '今天适合理财规划，理性消费',
      '财运平稳，保持良好的消费习惯就好',
    ],
    '人际': [
      '社交运很好，适合参加聚会或活动',
      '今天容易交到新朋友，保持开放心态',
      '人际关系融洽，和朋友的互动会很开心',
    ],
    '心情': [
      '今天心情不错，适合做让自己开心的事',
      '心情明朗的一天，保持好心情很重要',
      '内心的平静是最大的财富，享受当下吧',
    ],
    '综合': [
      '整体运势不错，保持积极的心态就好',
      '今天一切顺利，适合按计划行事',
      '运势平稳，做自己就好',
    ],
  };

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _spinAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _spinController,
        curve: Curves.easeOutCubic,
      ),
    );

    _spinController.addStatusListener(_onSpinComplete);
    _loadHistory();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _onSpinComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _isSpinning = false;
        _fortuneResult = _fortunes[_selectedIndex]['message']!;
        _aiInterpretation = '正在让AI为你解读运势...';
        _showResult = true;
      });
      _getAIInterpretation();
      _saveToHistory();
    }
  }

  Future<void> _getAIInterpretation() async {
    try {
      final category = _fortunes[_selectedIndex]['category']!;
      final fortune = _fortunes[_selectedIndex]['message']!;
      final storage = LocalStorageRepository();
      await storage.initialize();
      final aiService = AIService(storage);
      final characters = await storage.getAllAICharacters();
      if (characters.isEmpty) {
        _fallbackToLocalTemplate();
        return;
      }
      final result = await aiService.sendMessage(
        character: characters.first,
        userId: 'user',
        userMessage: '帮我解读今天的$category运势："$fortune"。用温柔自然的语气，像朋友一样给我一两句贴心建议。不要太长，30字以内。',
        chatHistory: [],
        memories: [],
        intimacyLevel: 50,
      );
      if (result.trim().isNotEmpty && mounted) {
        setState(() {
          _aiInterpretation = result.trim();
        });
      }
    } catch (e) {
      _fallbackToLocalTemplate();
    }
  }

  void _fallbackToLocalTemplate() {
    if (mounted) {
      setState(() {
        _aiInterpretation =
            _aiTemplates[_fortunes[_selectedIndex]['category']]![
                _random.nextInt(3)];
      });
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('lucky_wheel_history');
    if (data != null) {
      final list = jsonDecode(data) as List<dynamic>;
      setState(() {
        _history = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    }
  }

  Future<void> _saveToHistory() async {
    final entry = {
      'category': _fortunes[_selectedIndex]['category'],
      'message': _fortuneResult,
      'interpretation': _aiInterpretation,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _history.insert(0, entry);
    if (_history.length > 10) {
      _history = _history.sublist(0, 10);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lucky_wheel_history', jsonEncode(_history));
  }

  void _spin() {
    if (_isSpinning) return;

    setState(() {
      _showResult = false;
      _isSpinning = true;
    });

    // 随机选择结果：3-5 圈 + 随机停在某一段
    final targetIndex = _random.nextInt(8);
    final extraSpins = 3 + _random.nextInt(3); // 3-5 圈
    const segmentAngle = 2 * pi / 8;
    final targetAngle =
        extraSpins * 2 * pi + (targetIndex * segmentAngle) + segmentAngle / 2;

    _selectedIndex = targetIndex;

    // 动画总旋转量
    final totalRotation = targetAngle;

    _spinController.reset();
    _spinAnimation = Tween<double>(begin: 0, end: totalRotation).animate(
      CurvedAnimation(
        parent: _spinController,
        curve: Curves.easeOutCubic,
      ),
    );
    _spinController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('每日运势'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // 转盘区域
          Expanded(
            flex: 3,
            child: Center(
              child: _buildWheel(),
            ),
          ),
          // 结果或提示
          Expanded(
            flex: 2,
            child: _showResult ? _buildResultCard() : _buildHintArea(),
          ),
          // 历史记录
          _buildHistorySection(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWheel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // P7: 深色模式下使用柔和边框色，避免纯白过亮
    final wheelBorderColor = isDark
        ? Colors.white.withOpacity(0.25)
        : Colors.white;
    return AnimatedBuilder(
      animation: _spinAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _spinAnimation.value,
          child: CustomPaint(
            size: const Size(280, 280),
            painter: WheelPainter(
              fortunes: _fortunes,
              colors: _wheelColors,
              borderColor: wheelBorderColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHintArea() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '转动转盘，看看今天的运势吧',
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _spin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B6B), Color(0xFFFF8A65)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B6B).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                '开始转运',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final cs = Theme.of(context).colorScheme;
    final category = _fortunes[_selectedIndex]['category']!;
    final color = _wheelColors[_selectedIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 分类标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              category,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 运势结果
          Text(
            _fortuneResult,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // AI 解读
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _aiInterpretation,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 再转一次按钮
          GestureDetector(
            onTap: _spin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                '再转一次',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_history.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '最近记录',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final entry = _history[index];
                final catIndex = _fortunes.indexWhere(
                    (f) => f['category'] == entry['category']);
                final color =
                    catIndex >= 0 ? _wheelColors[catIndex] : cs.onSurfaceVariant;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        entry['category'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatHistoryTime(entry['timestamp']),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatHistoryTime(String? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 转盘绘制器
class WheelPainter extends CustomPainter {
  final List<Map<String, String>> fortunes;
  final List<Color> colors;
  final Color borderColor;

  WheelPainter({required this.fortunes, required this.colors, this.borderColor = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final segmentAngle = 2 * pi / fortunes.length;

    final paint = Paint()..style = PaintingStyle.fill;

    // 绘制各段
    for (int i = 0; i < fortunes.length; i++) {
      final startAngle = i * segmentAngle - pi / 2;

      // 扇形
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          segmentAngle,
          false,
        )
        ..close();

      paint.color = colors[i];
      canvas.drawPath(path, paint);

      // 分隔线
      paint
        ..color = borderColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * cos(startAngle),
          center.dy + radius * sin(startAngle),
        ),
        paint,
      );

      // 文字
      final textPainter = TextPainter(
        text: TextSpan(
          text: fortunes[i]['category'],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final textAngle = startAngle + segmentAngle / 2;
      final textDist = radius * 0.65;
      final textX = center.dx + textDist * cos(textAngle) - textPainter.width / 2;
      final textY = center.dy + textDist * sin(textAngle) - textPainter.height / 2;

      canvas.save();
      canvas.translate(textX + textPainter.width / 2, textY + textPainter.height / 2);
      canvas.rotate(textAngle);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // 中心圆
    paint
      ..style = PaintingStyle.fill
      ..color = borderColor;
    canvas.drawCircle(center, 28, paint);

    // 中心文字
    final centerPainter = TextPainter(
      text: TextSpan(
        text: '转运',
        style: TextStyle(
          color: colors[0],
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    centerPainter.layout();
    centerPainter.paint(
      canvas,
      Offset(
        center.dx - centerPainter.width / 2,
        center.dy - centerPainter.height / 2,
      ),
    );

    // 外圈装饰点
    paint
      ..style = PaintingStyle.fill
      ..color = borderColor.withOpacity(0.6);
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * pi;
      final dotX = center.dx + (radius + 4) * cos(angle);
      final dotY = center.dy + (radius + 4) * sin(angle);
      canvas.drawCircle(Offset(dotX, dotY), 3, paint);
    }

    // 外圈边框
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = borderColor;
    canvas.drawCircle(center, radius + 1, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
