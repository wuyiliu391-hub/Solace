import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/pet/pet_character_config.dart';
import 'repositories/pet_character_repository.dart';
import 'utils/avatar_resolver.dart';

/// Live2D 崽崽悬浮窗 Dart 入口（头像即崽崽版本）
///
/// 这个 entrypoint 被 Android 悬浮窗服务加载，运行在独立的 FlutterEngine 中。
/// 核心变革：不再渲染 13 层 PNG 部位，而是把用户选择的 AI 角色头像作为崽崽形象，
/// 叠加气泡对话、头像框、类人动画，让头像活起来。
///
/// 动态行为系统：
/// - 呼吸缩放（头像轻微起伏）
/// - 待机小动作（歪头、轻轻摇晃）
/// - 点击互动（弹跳 + 气泡台词 + 情绪反馈）
/// - 主动气泡（按配置间隔随机弹出角色台词）
/// - 情绪光晕（头像框颜色随情绪变化）
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Live2DPetApp());
}

class Live2DPetApp extends StatefulWidget {
  const Live2DPetApp({super.key});

  @override
  State<Live2DPetApp> createState() => _Live2DPetAppState();
}

class _Live2DPetAppState extends State<Live2DPetApp>
    with TickerProviderStateMixin {
  static const EventChannel _eventChannel =
      EventChannel('com.solace.solace/live2d_events');

  PetCharacterConfig _config = PetCharacterConfig.empty();

  // ── 动画控制器 ──
  late AnimationController _breathController;
  late Animation<double> _breathAnimation;
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;

  // ── 点击弹跳 ──
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  // ── 气泡系统 ──
  String? _bubbleText;
  Timer? _bubbleTimer;
  Timer? _idleBubbleTimer;
  bool _showBubble = false;

  // ── 当前情绪 ──
  String _emotion = 'calm';

  // ── 随机数 ──
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // 呼吸动画：2 秒循环，头像轻微缩放 1.0 ~ 1.04
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _breathAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    // 待机小动作：6 秒循环，轻微旋转 -3° ~ 3°
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat(reverse: true);
    _idleAnimation = Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _idleController, curve: Curves.easeInOutSine),
    );

    // 点击弹跳：快速上下弹一下
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: -18.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: -18.0, end: 0.0)
              .chain(CurveTween(curve: Curves.bounceOut)),
          weight: 60),
    ]).animate(_bounceController);

    _eventChannel.receiveBroadcastStream().listen(_handleEvent);
    _loadInitialConfig();
  }

  /// 启动时从 SharedPreferences 读取当前崽崽配置
  Future<void> _loadInitialConfig() async {
    try {
      final config = await PetCharacterRepository.instance.getCurrentPet();
      debugPrint('[Live2DPet] initial config loaded: id=${config.characterId}, name=${config.name}, avatar=${config.avatarUrl.isEmpty ? "(empty)" : config.avatarUrl.substring(0, config.avatarUrl.length.clamp(0, 60))}');
      if (mounted) {
        setState(() {
          _config = config;
        });
        _scheduleNextIdleBubble();
      }
    } catch (e) {
      debugPrint('[Live2DPet] load initial config failed: $e');
    }
  }

  void _handleEvent(dynamic event) {
    debugPrint('[Live2DPet] event: $event');
    if (event is Map) {
      final type = event['type'] as String?;
      if (type == 'config_changed') {
        // 旧 AvatarConfig 同步事件：不再驱动头像崽崽，但保留监听避免异常
        return;
      } else if (type == 'pet_character_changed') {
        final json = event['config'];
        if (json is Map) {
          final casted = _deepCastMap(json);
          if (casted != null) {
            final newConfig = PetCharacterConfig.fromJson(casted);
            debugPrint('[Live2DPet] pet_character_changed: id=${newConfig.characterId}, avatar=${newConfig.avatarUrl.isEmpty ? "(empty)" : "set"}');
            setState(() {
              _config = newConfig;
            });
            _showBubbleWith(_config.randomLine() ?? '换好啦～');
            _scheduleNextIdleBubble();
          } else {
            debugPrint('[Live2DPet] pet_character_changed cast failed');
          }
        } else {
          debugPrint('[Live2DPet] pet_character_changed config is not Map: $json');
        }
      } else if (type == 'tap') {
        final x = (event['x'] as num?)?.toDouble() ?? 0;
        final y = (event['y'] as num?)?.toDouble() ?? 0;
        _handleTap(x, y);
      }
    }
  }

  Map<String, dynamic>? _deepCastMap(Map map) {
    try {
      final result = <String, dynamic>{};
      map.forEach((k, v) {
        final key = k.toString();
        if (v is Map) {
          result[key] = _deepCastMap(v);
        } else if (v is List) {
          result[key] = _deepCastList(v);
        } else {
          result[key] = v;
        }
      });
      return result;
    } catch (e) {
      debugPrint('Pet deep cast map failed: $e');
      return null;
    }
  }

  List<dynamic> _deepCastList(List list) {
    return list.map((v) {
      if (v is Map) {
        return _deepCastMap(v);
      } else if (v is List) {
        return _deepCastList(v);
      } else {
        return v;
      }
    }).toList();
  }

  /// 处理来自 Kotlin 的点击事件
  void _handleTap(double x, double y) {
    _bounceController.forward(from: 0);

    // 按纵向区域切换情绪
    const height = 250.0;
    String emotion;
    String line;
    if (y < height / 3) {
      emotion = 'shy';
      line = '呀，被你发现了～';
    } else if (y < height * 2 / 3) {
      emotion = 'happy';
      line = _config.randomLine() ?? '嘿嘿，怎么啦？';
    } else {
      emotion = 'surprised';
      line = '呜哇！';
    }

    setState(() {
      _emotion = emotion;
    });
    _showBubbleWith(line);

    // 2 秒后恢复平静
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _emotion = 'calm';
        });
      }
    });
  }

  /// 显示气泡文字，3 秒后消失
  void _showBubbleWith(String text) {
    _bubbleTimer?.cancel();
    setState(() {
      _bubbleText = text;
      _showBubble = true;
    });
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showBubble = false;
        });
      }
    });
  }

  /// 安排下一次主动气泡
  void _scheduleNextIdleBubble() {
    _idleBubbleTimer?.cancel();
    if (!_config.enableIdleBubble || _config.bubbleLines.isEmpty) return;

    final interval = _config.idleBubbleIntervalSeconds;
    final delaySec = (interval ~/ 2) + _random.nextInt(interval);
    _idleBubbleTimer = Timer(Duration(seconds: delaySec), () {
      if (!mounted) return;
      final line = _config.randomLine();
      if (line != null) _showBubbleWith(line);
      _scheduleNextIdleBubble();
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    _idleController.dispose();
    _bounceController.dispose();
    _bubbleTimer?.cancel();
    _idleBubbleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Live2DPet] build: id=${_config.characterId}, avatarEmpty=${_config.avatarUrl.isEmpty}, frame=${_config.frameStyle}');
    final avatarWidget = AvatarResolver.imageWidget(
      _config.avatarUrl,
      width: 110,
      height: 110,
      fit: BoxFit.cover,
      onError: () => _buildPlaceholderAvatar(),
    ) ?? _buildPlaceholderAvatar();

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 200,
        height: 250,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 头像框光晕
            _buildFrameGlow(),

            // 头像主体 + 呼吸 + 待机 + 弹跳动画
            AnimatedBuilder(
              animation: Listenable.merge(
                  [_breathController, _idleController, _bounceController]),
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _bounceAnimation.value),
                  child: Transform.scale(
                    scale: _breathAnimation.value,
                    child: Transform.rotate(
                      angle: _idleAnimation.value,
                      child: _buildAvatar(avatarWidget),
                    ),
                  ),
                );
              },
            ),

            // 气泡
            if (_showBubble && _bubbleText != null)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _buildBubble(_bubbleText!),
              ),
          ],
        ),
      ),
    );
  }

  String? _frameImagePath() {
    switch (_config.frameStyle) {
      case 'pink_floral':
        return 'assets/live2d/_frame_previews_doubao/frame_11_pink_floral.png';
      case 'ink_floral':
        return 'assets/live2d/_frame_previews_doubao/frame_12_ink_floral.png';
      default:
        return null;
    }
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade300,
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
      ),
      child: const Icon(Icons.person, size: 48, color: Colors.white),
    );
  }

  Widget _buildAvatar(Widget? image) {
    final framePath = _frameImagePath();
    final avatar = Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: framePath == null
            ? Border.all(
                color: _frameColor().withOpacity(0.9),
                width: 4,
              )
            : null,
        boxShadow: framePath == null
            ? [
                BoxShadow(
                  color: _frameColor().withOpacity(0.35),
                  blurRadius: 16,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: image ??
            Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.person, size: 48, color: Colors.white),
            ),
      ),
    );

    if (framePath == null) return avatar;

    return SizedBox(
      width: 186,
      height: 186,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            framePath,
            width: 186,
            height: 186,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          avatar,
        ],
      ),
    );
  }

  Widget _buildFrameGlow() {
    final color = _frameColor();
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.25),
            color.withOpacity(0.0),
          ],
          radius: 0.75,
        ),
      ),
    );
  }

  Widget _buildBubble(String text) {
    final bgColor = Colors.white.withOpacity(0.95);
    return AnimatedOpacity(
      opacity: _showBubble ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            height: 1.3,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Color _frameColor() {
    switch (_emotion) {
      case 'happy':
        return Colors.amber;
      case 'shy':
        return Colors.pink.shade300;
      case 'angry':
        return Colors.red.shade400;
      case 'surprised':
        return Colors.cyan.shade400;
      case 'sleepy':
        return Colors.indigo.shade300;
      case 'calm':
      default:
        return _config.frameStyle == 'pink'
            ? Colors.pink.shade200
            : _config.frameStyle == 'blue'
                ? Colors.blue.shade300
                : _config.frameStyle == 'purple'
                    ? Colors.purple.shade300
                    : _config.frameStyle == 'neon'
                        ? Colors.tealAccent
                        : Colors.amber.shade400;
    }
  }
}
