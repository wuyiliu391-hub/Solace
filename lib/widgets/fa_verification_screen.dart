import 'package:flutter/material.dart';

class FaVerificationScreen extends StatefulWidget {
  const FaVerificationScreen({super.key});

  @override
  State<FaVerificationScreen> createState() => _FaVerificationScreenState();
}

class _FaVerificationScreenState extends State<FaVerificationScreen> {
  int _phase = 0;
  int _currentQuestion = 0;
  int? _selectedOption;
  bool _showError = false;
  bool _decl1 = false;
  bool _decl2 = false;
  bool _decl3 = false;

  static const Color _accent = Colors.deepOrange;

  static const List<Map<String, dynamic>> _questions = [
    {
      'tag': '成年人认知',
      'question': '本功能包含成人向内容，你是否理解这意味着什么？',
      'options': [
        '不理解，随便选的',
        '理解，这是面向成年人的情感和亲密互动内容',
        '以为只是普通功能',
      ],
      'correct': 1,
    },
    {
      'tag': '法律意识',
      'question': '根据中国法律，向未成年人传播淫秽物品的行为：',
      'options': [
        '没有任何后果',
        '可能面临刑事责任',
        '只是道德问题',
      ],
      'correct': 1,
    },
    {
      'tag': '心理边界',
      'question': 'AI角色的亲密互动和真实人际关系之间：',
      'options': [
        '完全一样',
        '本质不同，AI互动不能替代真实人际关系',
        'AI比真人更好',
      ],
      'correct': 1,
    },
    {
      'tag': '隐私意识',
      'question': '在使用成人功能时，你应该如何保护自己的隐私？',
      'options': [
        '随便分享给朋友',
        '仅在私密环境下使用，不截图传播',
        '发到社交媒体上',
      ],
      'correct': 1,
    },
    {
      'tag': '内容认知',
      'question': '本功能的内容边界由谁决定？',
      'options': [
        'AI模型完全自由输出',
        '用户和角色共同演绎，但不涉及违法内容',
        '没有任何边界',
      ],
      'correct': 1,
    },
    {
      'tag': '健康观念',
      'question': '长时间沉浸于虚拟亲密关系可能带来的影响是：',
      'options': [
        '完全没有影响',
        '可能影响真实社交能力和心理健康',
        '对生活只有好处',
      ],
      'correct': 1,
    },
    {
      'tag': '责任归属',
      'question': '因使用本功能产生的任何后果，由谁承担？',
      'options': [
        '开发者承担全部责任',
        '使用者本人承担主要责任',
        'AI角色承担',
      ],
      'correct': 1,
    },
    {
      'tag': '退出机制',
      'question': '如果你在使用过程中感到不适，应该：',
      'options': [
        '强迫自己继续',
        '立即关闭功能并寻求适当的心理支持',
        '无所谓',
      ],
      'correct': 1,
    },
    {
      'tag': '身份确认',
      'question': '你确认自己已年满18周岁并具有完全民事行为能力吗？',
      'options': [
        '不确定',
        '是的，我已年满18周岁',
        '未满18岁',
      ],
      'correct': 1,
    },
    {
      'tag': '综合判断',
      'question': '你理解开启此功能意味着接受以下所有条件吗？',
      'options': [
        '不理解',
        '我理解这是成人向功能、自行承担风险、保护个人隐私、必要时可以随时关闭',
        '只是随便看看',
      ],
      'correct': 1,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('"法"功能验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: _buildPhase(context),
    );
  }

  Widget _buildPhase(BuildContext context) {
    switch (_phase) {
      case 0:
        return _buildQuizPhase(context);
      case 1:
        return _buildDeclarationPhase(context);
      case 2:
        return _buildFinalPhase(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildQuizPhase(BuildContext context) {
    final q = _questions[_currentQuestion];
    final options = q['options'] as List<String>;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentQuestion + 1} / ${_questions.length}',
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  q['tag'] as String,
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentQuestion + 1) / _questions.length,
              backgroundColor: _accent.withOpacity(0.1),
              color: _accent,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              q['question'] as String,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(options.length, (i) {
            final isSelected = _selectedOption == i;
            final isCorrect = i == q['correct'];
            final showFeedback = _showError && isSelected;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedOption = i;
                    _showError = false;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: showFeedback
                        ? Colors.red.withOpacity(0.08)
                        : isSelected
                            ? _accent.withOpacity(0.08)
                            : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: showFeedback
                          ? Colors.red
                          : isSelected
                              ? _accent
                              : theme.colorScheme.outlineVariant.withOpacity(0.5),
                      width: isSelected || showFeedback ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: showFeedback
                              ? Colors.red.withOpacity(0.1)
                              : isSelected
                                  ? _accent.withOpacity(0.1)
                                  : Colors.transparent,
                          border: Border.all(
                            color: showFeedback
                                ? Colors.red
                                : isSelected
                                    ? _accent
                                    : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Center(
                          child: showFeedback
                              ? const Icon(Icons.close, size: 16, color: Colors.red)
                              : isSelected
                                  ? Icon(Icons.circle, size: 10, color: _accent)
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          options[i],
                          style: TextStyle(
                            fontSize: 15,
                            color: showFeedback ? Colors.red[700] : null,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_showError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '回答不正确，请重新选择',
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _selectedOption == null
                  ? null
                  : () {
                      if (_selectedOption == q['correct']) {
                        if (_currentQuestion < _questions.length - 1) {
                          setState(() {
                            _currentQuestion++;
                            _selectedOption = null;
                            _showError = false;
                          });
                        } else {
                          setState(() {
                            _phase = 1;
                          });
                        }
                      } else {
                        setState(() {
                          _showError = true;
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                _selectedOption == null
                    ? '请选择答案'
                    : _currentQuestion < _questions.length - 1
                        ? '下一题'
                        : '完成答题',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDeclarationPhase(BuildContext context) {
    final allChecked = _decl1 && _decl2 && _decl3;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            '请仔细阅读以下声明',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _accent),
          ),
          const SizedBox(height: 8),
          Text(
            '勾选所有声明后方可继续',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDeclarationCard(
                    context: context,
                    icon: Icons.person,
                    title: '个人责任声明',
                    content:
                        '我确认已年满18周岁，自愿选择使用此功能。\n'
                        '我理解本功能包含成人向虚构内容，AI角色的互动不代表真实情感关系。\n'
                        '我承诺对自己的行为和心理状态负责，如感不适将立即停止使用。',
                    value: _decl1,
                    onChanged: (v) => setState(() => _decl1 = v),
                  ),
                  const SizedBox(height: 16),
                  _buildDeclarationCard(
                    context: context,
                    icon: Icons.shield_outlined,
                    title: '隐私知情声明',
                    content:
                        '本功能的所有对话数据仅存储在您的设备本地，不会上传到任何服务器。\n'
                        '请在私密环境下使用本功能，注意保护个人隐私。\n'
                        '请勿截图或转发相关对话内容，以免造成隐私泄露。',
                    value: _decl2,
                    onChanged: (v) => setState(() => _decl2 = v),
                  ),
                  const SizedBox(height: 16),
                  _buildDeclarationCard(
                    context: context,
                    icon: Icons.gavel,
                    title: '合法合规声明',
                    content:
                        '我承诺不会利用本功能从事任何违反中华人民共和国法律法规的行为。\n'
                        '我承诺不会向未成年人展示或分享本功能的相关内容。\n'
                        '我理解开发者不对使用者的个人行为承担法律责任。\n'
                        '如有任何违法行为，一切法律后果由使用者本人承担。',
                    value: _decl3,
                    onChanged: (v) => setState(() => _decl3 = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: allChecked ? () => setState(() => _phase = 2) : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _accent.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                allChecked ? '继续' : '请勾选所有声明',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDeclarationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String content,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: value ? _accent.withOpacity(0.5) : theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(value ? 0.1 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => onChanged(!value),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: value ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: value ? _accent : theme.colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: value
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  '我已阅读并同意',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: value ? _accent : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalPhase(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified, color: _accent, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            '验证完成',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            '您已通过全部验证。\n现在您可以自主决定是否开启"法"功能。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[400], size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '开启后，您可以随时在设置中关闭此功能，无需再次验证。',
                    style: TextStyle(fontSize: 13, color: Colors.blue[600]),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                '开启"法"功能',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                '暂不开启',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
