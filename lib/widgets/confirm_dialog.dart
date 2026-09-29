// 【对标来源：SillyTavern-1.18.0 — templates/confirmDialog.html】
// 1:1 转译自 SillyTavern 确认弹窗模板
// 参考文件：public/scripts/templates/confirmDialog.html

import 'package:flutter/material.dart';

/// 确认弹窗结果
enum ConfirmResult {
  ok,
  cancel,
}

/// 通用确认弹窗（对标 SillyTavern confirmDialog）
/// 支持自定义标题、内容、按钮文本
class ConfirmDialog extends StatelessWidget {
  /// 标题
  final String title;

  /// 内容文本
  final String content;

  /// 确认按钮文本
  final String confirmText;

  /// 取消按钮文本
  final String cancelText;

  /// 是否显示取消按钮
  final bool showCancel;

  /// 确认按钮颜色
  final Color? confirmColor;

  /// 取消按钮颜色
  final Color? cancelColor;

  /// 是否危险操作（删除等）
  final bool isDestructive;

  /// 自定义内容 Widget
  final Widget? contentWidget;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.showCancel = true,
    this.confirmColor,
    this.cancelColor,
    this.isDestructive = false,
    this.contentWidget,
  });

  /// 显示确认弹窗并返回结果
  static Future<ConfirmResult> show({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = '确认',
    String cancelText = '取消',
    bool showCancel = true,
    Color? confirmColor,
    bool isDestructive = false,
    Widget? contentWidget,
  }) async {
    final result = await showDialog<ConfirmResult>(
      context: context,
      builder: (context) => ConfirmDialog(
        title: title,
        content: content,
        confirmText: confirmText,
        cancelText: cancelText,
        showCancel: showCancel,
        confirmColor: confirmColor,
        isDestructive: isDestructive,
        contentWidget: contentWidget,
      ),
    );
    return result ?? ConfirmResult.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveConfirmColor = confirmColor ??
        (isDestructive ? Colors.red : colorScheme.primary);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: contentWidget ??
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
      actions: [
        if (showCancel)
          TextButton(
            onPressed: () => Navigator.pop(context, ConfirmResult.cancel),
            style: TextButton.styleFrom(
              foregroundColor: cancelColor ?? colorScheme.onSurface.withOpacity(0.6),
            ),
            child: Text(cancelText),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, ConfirmResult.ok),
          style: TextButton.styleFrom(
            foregroundColor: effectiveConfirmColor,
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }
}

/// 输入确认弹窗（对标 SillyTavern confirmDialog 带输入框版本）
class InputConfirmDialog extends StatefulWidget {
  /// 标题
  final String title;

  /// 提示文本
  final String hintText;

  /// 初始值
  final String? initialValue;

  /// 确认按钮文本
  final String confirmText;

  /// 取消按钮文本
  final String cancelText;

  /// 输入验证
  final String? Function(String?)? validator;

  const InputConfirmDialog({
    super.key,
    required this.title,
    this.hintText = '',
    this.initialValue,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.validator,
  });

  /// 显示输入确认弹窗，返回输入值（取消返回 null）
  static Future<String?> show({
    required BuildContext context,
    required String title,
    String hintText = '',
    String? initialValue,
    String confirmText = '确认',
    String cancelText = '取消',
    String? Function(String?)? validator,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => InputConfirmDialog(
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        confirmText: confirmText,
        cancelText: cancelText,
        validator: validator,
      ),
    );
  }

  @override
  State<InputConfirmDialog> createState() => _InputConfirmDialogState();
}

class _InputConfirmDialogState extends State<InputConfirmDialog> {
  late TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          autofocus: true,
          validator: widget.validator,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurface.withOpacity(0.6),
          ),
          child: Text(widget.cancelText),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? true) {
              Navigator.pop(context, _controller.text);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
