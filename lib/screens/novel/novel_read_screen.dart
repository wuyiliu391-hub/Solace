import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/novel.dart';

/// 沉浸式阅读页（纯文本，深色背景，字体大小可调）
class NovelReadScreen extends StatefulWidget {
  final NovelChapter chapter;
  final String novelTitle;

  const NovelReadScreen({
    super.key,
    required this.chapter,
    required this.novelTitle,
  });

  @override
  State<NovelReadScreen> createState() => _NovelReadScreenState();
}

class _NovelReadScreenState extends State<NovelReadScreen> {
  double _fontSize = 17;
  bool _showControls = true;
  // 阅读主题: 0=深色 1=暖黄 2=浅色
  int _theme = 0;

  static const _themes = [
    {'bg': Color(0xFF1A1A1A), 'text': Color(0xFFDDDDDD)},
    {'bg': Color(0xFFF5E6C8), 'text': Color(0xFF3B2D1A)},
    {'bg': Color(0xFFF5F5F5), 'text': Color(0xFF1A1A1A)},
  ];

  Color get _bg => _themes[_theme]['bg']!;
  Color get _textColor => _themes[_theme]['text']!;

  @override
  void initState() {
    super.initState();
    // 隐藏状态栏，沉浸体验
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // ── 正文 ────────────────────────────────────────────────
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  _showControls ? 80 : 40,
                  24,
                  _showControls ? 100 : 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chapter.title,
                      style: TextStyle(
                        fontSize: _fontSize + 4,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.chapter.content.isEmpty
                          ? '（本章暂无内容）'
                          : widget.chapter.content,
                      style: TextStyle(
                        fontSize: _fontSize,
                        color: widget.chapter.content.isEmpty
                            ? _textColor.withOpacity(0.4)
                            : _textColor,
                        height: 1.9,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        '—— 本章完 ——',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textColor.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 顶部控制栏 ─────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _showControls ? 0 : -80,
              left: 0,
              right: 0,
              child: Container(
                color: _bg.withOpacity(0.95),
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 4, bottom: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new,
                          color: _textColor, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.novelTitle,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 底部控制栏 ─────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                color: _bg.withOpacity(0.95),
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 8,
                    top: 8,
                    left: 16,
                    right: 16),
                child: Row(
                  children: [
                    // 字号调小
                    IconButton(
                      icon: Icon(Icons.text_decrease,
                          color: _textColor.withOpacity(0.7)),
                      onPressed: () => setState(
                          () => _fontSize = (_fontSize - 1).clamp(12, 26)),
                    ),
                    Text('$_fontSize',
                        style: TextStyle(
                            color: _textColor.withOpacity(0.6), fontSize: 13)),
                    // 字号调大
                    IconButton(
                      icon: Icon(Icons.text_increase,
                          color: _textColor.withOpacity(0.7)),
                      onPressed: () => setState(
                          () => _fontSize = (_fontSize + 1).clamp(12, 26)),
                    ),
                    const Spacer(),
                    // 主题切换
                    ...List.generate(3, (i) {
                      final color = _themes[i]['bg']!;
                      return GestureDetector(
                        onTap: () => setState(() => _theme = i),
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _theme == i
                                  ? _textColor
                                  : _textColor.withOpacity(0.25),
                              width: _theme == i ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}