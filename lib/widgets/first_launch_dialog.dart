import 'package:flutter/material.dart';
import '../repositories/local_storage_repository.dart';

/// 715 合规声明对话框 — 不可跳过
///
/// 合并年龄声明 + 用户协议 + 安全功能介绍
/// 所有用户首次安装重构版时弹出，不可跳过
void showComplianceDialog(
  BuildContext context,
  LocalStorageRepository storage,
) {
  showDialog(
    context: context,
    barrierDismissible: false, // 不可跳过（715 合规）
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.favorite, color: Colors.pink),
          SizedBox(width: 8),
          Text('欢迎使用 Solace'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('年龄声明'),
            const Text(
              '本应用包含 AI 互动功能。未满 14 周岁用户禁止使用，'
              '14-17 周岁用户需在监护人指导下使用。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _sectionTitle('用户协议'),
            const Text(
              '使用本应用即表示您同意我们的服务条款和隐私政策。'
              '请文明使用，遵守当地法律法规。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _sectionTitle('安全守护'),
            const Text(
              '本应用内置情绪安全守护功能。如检测到您可能处于'
              '情绪困扰中，AI 会主动提供关怀和心理援助资源。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            storage.setAgeConfirmed();
            storage.setTermsAccepted();
            Navigator.pop(ctx);
          },
          child: const Text('我已阅读并同意'),
        ),
      ],
    ),
  );
}

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}
