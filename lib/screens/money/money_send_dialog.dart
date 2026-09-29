import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/chat/chat_bloc.dart';
import '../../config/app_colors.dart';

/// 微信式转账/发红包输入面板（底部弹层）。
///
/// 金额为整数金币（1-2000），备注 ≤ 20 字。
/// 确认后派发 [ChatSendMoneyMessage]，由 ChatBloc/MoneyService 完成
/// 扣款、落流水、生成气泡与角色回应。本页不碰资金逻辑。
class MoneySendDialog extends StatefulWidget {
  final String chatId;
  final String characterId;
  final bool isRedPacket;

  /// 用户当前金币余额（用于提示与校验）
  final int balance;

  const MoneySendDialog({
    super.key,
    required this.chatId,
    required this.characterId,
    required this.isRedPacket,
    required this.balance,
  });

  @override
  State<MoneySendDialog> createState() => _MoneySendDialogState();
}

class _MoneySendDialogState extends State<MoneySendDialog> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_amountCtrl.text.trim());

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null || amount <= 0 || amount > 2000) {
      _toast('请输入 1-2000 的金额');
      return;
    }
    if (!widget.isRedPacket && amount > widget.balance) {
      _toast('余额不足（当前 ${widget.balance} 金币）');
      return;
    }
    if (_noteCtrl.text.trim().length > 20) {
      _toast('备注最多 20 字');
      return;
    }
    setState(() => _sending = true);
    context.read<ChatBloc>().add(ChatSendMoneyMessage(
          chatId: widget.chatId,
          characterId: widget.characterId,
          amount: amount,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          isRedPacket: widget.isRedPacket,
        ));
    Navigator.pop(context);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.isRedPacket ? '发红包' : '转账';
    final accent = widget.isRedPacket ? const Color(0xFFE06A4E) : const Color(0xFFF89D35);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? WeChatColors.darkInputBox : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('¥', style: TextStyle(fontSize: 18, color: accent)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '金额（金币）',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? WeChatColors.darkInputBox : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _noteCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  hintText: '备注（可选）',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isRedPacket
                  ? '角色收到红包后将拆开并感谢你'
                  : '余额 ${widget.balance} 金币，转账后 TA 将收到',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? WeChatColors.darkTextSecondary
                    : WeChatColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isRedPacket
                      ? const Color(0xFFE06A4E)
                      : WeChatColors.brandGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text(
                  '确认',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}