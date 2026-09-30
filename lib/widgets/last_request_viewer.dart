import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/llm_request.dart';

/// 「查看上次请求内容」对话框（单聊设置 / 群聊设置共用）。
///
/// 读 `LastLlmRequestSnapshot` 静态快照：最近一次实际发出的 system 全文 +
/// 场景 + 历史条数 + 时间。用户核对"AI 到底被告诉了什么"（代称/性别/追加指令
/// 是否生效）的唯一界面。内容可复制，方便用户拿到「自定义请求指令」里去改。
class LastRequestViewer {
  LastRequestViewer._();

  static Future<void> show(BuildContext context) {
    if (!LastLlmRequestSnapshot.hasData) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('上次请求内容'),
          content: const Text('本机还没有发出过 AI 请求。\n先聊一句，再回来看。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    final snapScope = LastLlmRequestSnapshot.scope;
    final at = LastLlmRequestSnapshot.capturedAt;
    final timeText =
        at == null ? '' : '（${at.hour.toString().padLeft(2, '0')}：'
            '${at.minute.toString().padLeft(2, '0')}：'
            '${at.second.toString().padLeft(2, '0')}）';
    final meta =
        '场景：$snapScope$timeText　历史：${LastLlmRequestSnapshot.historyCount} 条\n'
        '下面是实际发出的 system 全文（含身份/性别/模式/追加指令）：';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上次请求内容'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    LastLlmRequestSnapshot.systemPrompt,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: LastLlmRequestSnapshot.systemPrompt));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('请求内容已复制'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('复制全文'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
