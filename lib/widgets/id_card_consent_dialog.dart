import 'package:flutter/material.dart';

class IdCardConsentDialog extends StatelessWidget {
  const IdCardConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 28, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '年龄验证授权',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(cs, '您填写的身份证号码仅用于本地离线计算年龄'),
                    const SizedBox(height: 8),
                    _bullet(cs, '不上传服务器、不保存明文、不做身份真伪核验'),
                    const SizedBox(height: 8),
                    _bullet(cs, '仅区分未成年以限制情感功能'),
                    const SizedBox(height: 8),
                    _bullet(cs, '可拒绝填写（拒绝则无法使用成年内容）'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '根据《人工智能拟人化互动服务管理暂行办法》，本应用仅限18周岁及以上用户使用。'
                '我们无官方实名认证资质，仅通过身份证编码规则进行基础年龄筛别，无法防范证件冒用。'
                '冒用他人身份证属于违法行为，一切后果由本人及监护人承担。',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('同意并继续验证', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('拒绝，退出应用', style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(ColorScheme cs, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, size: 14, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8), height: 1.4),
          ),
        ),
      ],
    );
  }
}
