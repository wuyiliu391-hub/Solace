/// 微信红包 / 转账创建页
///
/// 数据来源：刷圈兔 9.6.0 逆向
///   - res/layout/activity_create_redpacket.xml
///   - res/layout/activity_create_transfer.xml
/// 还原要点：
///   - 顶部金额输入区：¥ 符号 28sp + 输入框 60dp 高
///   - 内容行 50dp：祝福语/转账说明
///   - 红包额外：红包个数 + 领完延时（秒）
///   - 发送人切换：自己/对方
///   - 底部塞钱按钮（橙色渐变）
library;

import 'package:flutter/material.dart';

import '../../config/wechat_theme.dart';

/// 红包/转账创建结果
class WxMoneyResult {
  WxMoneyResult({
    required this.amount,
    required this.content,
    this.count = 1,
    this.delaySeconds = 0,
    required this.isFromMe,
  });

  final double amount;
  final String content;
  final int count;
  final int delaySeconds;
  final bool isFromMe;
}

/// 创建红包/转账的底部弹窗
///
/// 返回 [WxMoneyResult]；用户取消则返回 null。
Future<WxMoneyResult?> showWxCreateMoneySheet(
  BuildContext context, {
  required bool isRedPacket,
  int groupMemberCount = 1,
}) {
  return showModalBottomSheet<WxMoneyResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WxColors.listBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
    ),
    builder: (ctx) => _CreateMoneySheet(
      isRedPacket: isRedPacket,
      groupMemberCount: groupMemberCount,
    ),
  );
}

class _CreateMoneySheet extends StatefulWidget {
  const _CreateMoneySheet({
    required this.isRedPacket,
    required this.groupMemberCount,
  });

  final bool isRedPacket;
  final int groupMemberCount;

  @override
  State<_CreateMoneySheet> createState() => _CreateMoneySheetState();
}

class _CreateMoneySheetState extends State<_CreateMoneySheet> {
  final _amountCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '1');
  final _delayCtrl = TextEditingController(text: '0');
  bool _isFromMe = true;

  @override
  void initState() {
    super.initState();
    _contentCtrl.text = widget.isRedPacket ? '恭喜发财，大吉大利' : '你发起了一笔转账';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _contentCtrl.dispose();
    _countCtrl.dispose();
    _delayCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }
    Navigator.of(context).pop(WxMoneyResult(
      amount: amount,
      content: _contentCtrl.text.trim().isEmpty
          ? (widget.isRedPacket ? '恭喜发财，大吉大利' : '你发起了一笔转账')
          : _contentCtrl.text.trim(),
      count: widget.isRedPacket
          ? (int.tryParse(_countCtrl.text.trim()) ?? 1)
          : 1,
      delaySeconds: widget.isRedPacket
          ? (int.tryParse(_delayCtrl.text.trim()) ?? 0)
          : 0,
      isFromMe: _isFromMe,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final paddingBottom = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: WxColors.listBg,
      appBar: AppBar(
        backgroundColor: WxColors.navBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: WxColors.textBlack),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isRedPacket ? '发红包' : '转账',
          style: WxText.navTitle,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 80 + paddingBottom),
        child: Column(
          children: [
            // 金额输入区
            Container(
              color: WxColors.listBg,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '¥',
                    style: TextStyle(
                      fontSize: 28,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(width: 30),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      maxLength: 8,
                      style: TextStyle(
                        fontSize: widget.isRedPacket ? 20 : 16,
                        color: WxColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入金额',
                        hintStyle: const TextStyle(
                            color: WxColors.textTime, fontSize: 16),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容行
            _buildContentRow(),
            // 红包专属行
            if (widget.isRedPacket) ...[
              _buildCountRow(),
              _buildDelayRow(),
            ],
            // 发送人切换
            _buildSenderRow(),
          ],
        ),
      ),
      bottomSheet: Padding(
        padding: EdgeInsets.only(bottom: paddingBottom),
        child: _buildSubmitButton(),
      ),
    );
  }

  /// 内容行
  Widget _buildContentRow() {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 10),
      color: WxColors.listBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('内容：',
              style: TextStyle(fontSize: 14, color: WxColors.textPrimary)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _contentCtrl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: WxColors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: WxColors.textGray),
        ],
      ),
    );
  }

  /// 红包个数
  Widget _buildCountRow() {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 10),
      color: WxColors.listBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '红包个数(本群共${widget.groupMemberCount}人)',
            style: const TextStyle(fontSize: 14, color: WxColors.textPrimary),
          ),
          const Spacer(),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _countCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: WxColors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const Text('个',
              style: TextStyle(fontSize: 14, color: WxColors.textPrimary)),
        ],
      ),
    );
  }

  /// 领完延时
  Widget _buildDelayRow() {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 10),
      color: WxColors.listBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('多久被领完',
              style: TextStyle(fontSize: 14, color: WxColors.textPrimary)),
          const Spacer(),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _delayCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: WxColors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const Text('秒',
              style: TextStyle(fontSize: 14, color: WxColors.textPrimary)),
        ],
      ),
    );
  }

  /// 发送人切换
  Widget _buildSenderRow() {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(top: 10),
      color: WxColors.listBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('发送人：',
              style: TextStyle(fontSize: 14, color: WxColors.textPrimary)),
          const Spacer(),
          _senderChip('对方', !_isFromMe),
          const SizedBox(width: 10),
          _senderChip('自己', _isFromMe),
        ],
      ),
    );
  }

  Widget _senderChip(String label, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _isFromMe = label == '自己'),
      child: Container(
        width: 60,
        height: 35,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WxColors.brand : WxColors.listBg,
          border: Border.all(
            color: selected ? WxColors.brand : WxColors.hairline,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.white : WxColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 底部塞钱按钮
  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 50,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF4AB5D), Color(0xFFE89B4A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _submit,
          child: Center(
            child: Text(
              widget.isRedPacket ? '塞钱进红包' : '确认转账',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
